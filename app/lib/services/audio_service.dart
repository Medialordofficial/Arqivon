import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../config/logger.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// **Playback architecture (v6 — single persistent player, sequential queue):**
///
/// 1. PCM chunks arrive via [queueChunk] → accumulate in [_pcmBuffer].
/// 2. A timer flushes them to WAV files → [_wavQueue].
/// 3. A **single [AudioPlayer]** is reused for the entire session.
///    For each WAV: `setAudioSource` → `await play()`.
///    `play()` returns when the track finishes, then we load the next.
/// 4. No ConcatenatingAudioSource, no player creation/disposal churn.
/// 5. Barge-in: [stopPlayback] calls `player.stop()` (unblocks `await play()`)
///    and increments [_turnId] so the loop exits.
class AudioService {
  static final _log = AppLogger('AudioService');

  // ── Recording ──────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  final StreamController<String> _audioController =
      StreamController<String>.broadcast();
  bool _isCapturing = false;
  bool _disposed = false;

  static const int _chunkTargetBytes = 1600; // 50 ms @ 16 kHz, 16-bit mono
  final List<int> _recordRing = [];

  // ── Playback — single player, sequential queue ────────────────────
  AudioPlayer? _player;
  Timer? _playbackTimeout;
  Timer? _flushTimer;

  final List<int> _pcmBuffer = [];
  final List<String> _tempFiles = [];
  final List<String> _wavQueue = [];
  int _chunkIndex = 0;
  int _turnId = 0;
  bool _flushing = false;
  bool _reflushNeeded = false;
  bool _loopRunning = false;
  bool _turnComplete = false;

  /// Called when the AI turn's playback finishes (all tracks played).
  VoidCallback? onPlaybackDone;

  bool _sessionConfigured = false;

  // ── Audio amplitude for visualizer ──────────────────────────────
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  Stream<double> get amplitudeStream => _amplitudeController.stream;
  Stream<String> get audioStream => _audioController.stream;
  bool get isCapturing => _isCapturing;

  // ── Audio Session ──────────────────────────────────────────────────

  Future<void> _ensureAudioSession() async {
    if (_sessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    _sessionConfigured = true;
    _log.info('audio session configured (voiceCommunication)');
  }

  /// Lazily create a single AudioPlayer that lives for the entire session.
  void _ensurePlayer() {
    if (_player != null) return;
    _player = AudioPlayer();
    _log.info('persistent player created');
  }

  // ── Recording ─────────────────────────────────────────────────────

  int _recordChunkCount = 0;
  DateTime _lastRecordData = DateTime.now();
  bool _startInProgress = false;

  Future<void> start() async {
    if (_isCapturing || _disposed || _startInProgress) return;
    _startInProgress = true;
    try {
      await _ensureAudioSession();
    } catch (e) {
      _log.severe('audio session setup failed — recorder blocked', e);
      _startInProgress = false;
      return;
    }

    try {
      await _recorder.stop();
    } catch (e) {
      _log.fine('pre-start recorder stop: $e');
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );

      _startInProgress = false;
      _isCapturing = true;
      _recordChunkCount = 0;
      _recordRing.clear();
      _recordSub?.cancel();
      _recordSub = stream.listen(
        (data) {
          _lastRecordData = DateTime.now();
          _recordChunkCount++;
          if (_recordChunkCount % 100 == 1) {
            _log.fine(
              'recorder data chunk #$_recordChunkCount (${data.length} bytes)',
            );
          }
          _recordRing.addAll(data);
          while (_recordRing.length >= _chunkTargetBytes) {
            final chunk = Uint8List.fromList(
              _recordRing.sublist(0, _chunkTargetBytes),
            );
            _recordRing.removeRange(0, _chunkTargetBytes);
            if (!_audioController.isClosed) {
              _audioController.add(base64Encode(chunk));
            }
          }
          if (!_amplitudeController.isClosed && data.length >= 2) {
            _emitAmplitude(data);
          }
        },
        onError: (e) {
          _log.severe('recorder error', e);
        },
        onDone: () {
          _log.warning('recorder stream ended — will auto-restart');
          _isCapturing = false;
          _recordSub = null;
          if (!_disposed && !_audioController.isClosed) {
            Future.delayed(const Duration(milliseconds: 120), () {
              if (!_disposed && !_isCapturing) {
                _log.info('auto-restarting recorder');
                start();
              }
            });
          }
        },
      );
      _log.info('recorder started');
    } catch (e) {
      _log.severe('recorder startStream FAILED — will retry in 500ms', e);
      _startInProgress = false;
      _isCapturing = false;
      if (!_disposed) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_disposed && !_isCapturing) {
            start();
          }
        });
      }
    }
  }

  Future<void> stop() async {
    _isCapturing = false;
    _recordSub?.cancel();
    _recordSub = null;
    if (_recordRing.isNotEmpty && !_audioController.isClosed) {
      final residual = Uint8List.fromList(_recordRing);
      _audioController.add(base64Encode(residual));
      _log.info('flushed ${_recordRing.length} residual ring-buffer bytes');
      _recordRing.clear();
    }
    try {
      await _recorder.stop();
    } catch (e) {
      _log.fine('stop recorder: $e');
    }
    _log.info('recorder stopped');
  }

  Future<void> ensureRecording() async {
    if (_disposed) return;
    if (_isCapturing &&
        DateTime.now().difference(_lastRecordData).inMilliseconds < 2000) {
      _log.fine('ensureRecording — recorder still alive, skipping restart');
      return;
    }
    _log.info('ensureRecording — force-restarting recorder');
    _isCapturing = false;
    _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
    } catch (e) {
      _log.fine('ensureRecording stop: $e');
    }
    await start();
  }

  // ══════════════════════════════════════════════════════════════════
  //  PLAYBACK — single persistent player, sequential WAV queue (v6)
  // ══════════════════════════════════════════════════════════════════

  /// Queue a base64-encoded PCM chunk from the AI into the buffer.
  void queueChunk(String base64Audio) {
    final bytes = base64Decode(base64Audio);
    _pcmBuffer.addAll(bytes);

    if (_turnComplete) {
      // Late chunk after turn_complete — flush urgently.
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(milliseconds: 15), _flush);
    } else if (_flushTimer == null || !_flushTimer!.isActive) {
      // First chunk → buffer 300ms for quick time-to-first-audio.
      // Loop already running → accumulate 600ms — balances fewer WAV
      // transitions (each causes a 20-50ms gap) against responsiveness.
      final ms = !_loopRunning ? 300 : 600;
      _flushTimer = Timer(Duration(milliseconds: ms), _flush);
    }
    // Hard cap: ~2s of audio at 24kHz 16-bit mono.
    if (_pcmBuffer.length >= 96000) {
      _flushTimer?.cancel();
      _flush();
    }
  }

  /// Serialized flush — only one runs at a time.
  Future<void> _flush() async {
    if (_flushing) {
      _reflushNeeded = true;
      return;
    }
    _flushing = true;
    try {
      await _doFlush();
    } finally {
      _flushing = false;
      if (_reflushNeeded && _pcmBuffer.isNotEmpty) {
        _reflushNeeded = false;
        // Use a short timer instead of scheduleMicrotask to avoid
        // a CPU-wasting spin loop when the buffer is below minimum.
        Timer(const Duration(milliseconds: 50), () => _flush());
      }
    }
  }

  Future<void> _doFlush() async {
    // When turn is complete, flush ANY remaining PCM regardless of size.
    // During streaming, require at least ~20ms of audio (960 bytes at
    // 24kHz 16-bit mono). Small threshold avoids creating tiny WAVs
    // that are mostly click artifacts, while not blocking real audio.
    if (_pcmBuffer.isEmpty) return;
    if (!_turnComplete && _pcmBuffer.length < 960) {
      return;
    }
    final turnSnapshot = _turnId;

    final pcm = Uint8List.fromList(_pcmBuffer);
    _pcmBuffer.clear();

    final dir = await getTemporaryDirectory();
    if (_turnId != turnSnapshot) return;

    final path = '${dir.path}/ai_t${turnSnapshot}_${_chunkIndex++}.wav';
    try {
      await File(path)
          .writeAsBytes(_buildWav(pcm, sampleRate: 24000), flush: true);
    } catch (e) {
      _log.severe('WAV write failed: $e');
      return;
    }
    if (_turnId != turnSnapshot) {
      unawaited(File(path).delete().catchError((_) => File(path)));
      return;
    }
    _tempFiles.add(path);
    _wavQueue.add(path);
    final audioDurationMs = (pcm.length / (24000 * 2) * 1000).round();
    _log.info('WAV queued: #${_chunkIndex - 1}, ${pcm.length} bytes '
        '(${audioDurationMs}ms audio), queue=${_wavQueue.length}');

    // Start the playback loop if not already running.
    if (!_loopRunning) {
      _loopRunning = true;
      unawaited(_runPlaybackLoop(turnSnapshot));
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  PLAYBACK LOOP — single player, sequential queue
  //  `await player.play()` blocks until the track finishes or stop()
  //  is called (barge-in). Simple and 100% reliable.
  // ──────────────────────────────────────────────────────────────────

  Future<void> _runPlaybackLoop(int turnSnapshot) async {
    _log.info('▶ playback loop START (turn=$turnSnapshot)');
    await _ensureAudioSession();
    _ensurePlayer();
    if (_turnId != turnSnapshot) {
      _loopRunning = false;
      return;
    }

    try {
      while (_turnId == turnSnapshot) {
        // ── Wait for a WAV in the queue ─────────────────────────
        while (_wavQueue.isEmpty) {
          if (_turnComplete && _pcmBuffer.isEmpty) {
            if (_flushing) {
              await Future.delayed(const Duration(milliseconds: 15));
              continue;
            }
            // Brief grace for final in-flight flush.
            await Future.delayed(const Duration(milliseconds: 50));
            // Final flush — flush ANY remaining PCM when turn is done.
            if (_pcmBuffer.isNotEmpty && !_flushing) {
              _flushTimer?.cancel();
              await _flush();
            }
            if (_wavQueue.isEmpty && _pcmBuffer.isEmpty && !_flushing) {
              _log.info('✓ turn complete, no more tracks');
              return; // → finally block fires onPlaybackDone
            }
            continue;
          }
          if (_turnId != turnSnapshot) return;
          // When queue is empty but PCM data exists, force-flush
          // immediately. The 1500ms accumulation timer is for steady-
          // state streaming; here we're between tracks and need audio.
          if (_pcmBuffer.isNotEmpty && !_flushing) {
            _flushTimer?.cancel();
            await _flush();
          }
          await Future.delayed(const Duration(milliseconds: 20));
        }
        if (_turnId != turnSnapshot) return;

        // ── Dequeue and play ────────────────────────────────────
        final path = _wavQueue.removeAt(0);
        try {
          await _player!.setAudioSource(
            AudioSource.uri(Uri.file(path)),
            preload: true,
          );
        } catch (e) {
          _log.warning('setAudioSource failed: $e — skipping track');
          continue;
        }
        if (_turnId != turnSnapshot) return;

        try {
          _log.info('♪ PLAY track (queue=${_wavQueue.length} remain)');
          // player.play() blocks until track finishes or stop() is called.
          await _player!.play();
          _log.info('♪ track DONE');
        } catch (e) {
          _log.severe('play() error: $e');
        }
        if (_turnId != turnSnapshot) return;

        // Immediately seek to start of the player so it's in idle/ready
        // state for the next setAudioSource call.
        try {
          await _player!.seek(Duration.zero);
        } catch (_) {}
      }
    } finally {
      if (_turnId == turnSnapshot) {
        _loopRunning = false;
        _log.info('▶ playback loop END — resetForNextTurn');
        _resetForNextTurn();
      } else {
        _log.info('▶ playback loop END — turn was cancelled');
      }
    }
  }

  /// Called by the provider on `turn_complete`.
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _turnComplete = true;
    _log.info('flushAndPlay — pcmBuf=${_pcmBuffer.length}, '
        'queue=${_wavQueue.length}, loop=$_loopRunning');

    if (_pcmBuffer.isNotEmpty) await _flush();

    // Wait for any in-progress flush to finish (up to 200ms).
    int waitMs = 0;
    while (_flushing && waitMs < 200) {
      await Future.delayed(const Duration(milliseconds: 10));
      waitMs += 10;
    }
    if (_pcmBuffer.isNotEmpty) await _flush();

    if (!_loopRunning && _wavQueue.isEmpty) {
      _log.info('no audio this turn');
      onPlaybackDone?.call();
      return;
    }

    // Safety timeout in case playback hangs.
    _playbackTimeout?.cancel();
    _playbackTimeout = Timer(const Duration(seconds: 30), () {
      _log.warning('playback TIMEOUT — force-resetting');
      _turnId++;
      _player?.stop();
      _resetForNextTurn();
    });
  }

  void _resetForNextTurn() {
    _playbackTimeout?.cancel();
    _turnComplete = false;
    _chunkIndex = 0;
    _loopRunning = false;
    _wavQueue.clear();
    // Player is NOT disposed — reused for next turn.

    final files = List<String>.from(_tempFiles);
    _tempFiles.clear();
    unawaited(Future(() async {
      for (final p in files) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }));

    _log.info('turn reset — firing onPlaybackDone');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately (barge-in).
  Future<void> stopPlayback() async {
    _playbackTimeout?.cancel();
    _flushTimer?.cancel();
    _pcmBuffer.clear();
    _turnComplete = false;
    _chunkIndex = 0;
    _flushing = false;
    _reflushNeeded = false;
    _loopRunning = false;
    _turnId++; // makes the loop exit
    _wavQueue.clear();

    // stop() unblocks `await player.play()` in the loop.
    // Player is NOT disposed — reused for next turn.
    try {
      await _player?.stop();
    } catch (_) {}

    final files = List<String>.from(_tempFiles);
    _tempFiles.clear();
    unawaited(Future(() async {
      for (final p in files) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }));
    _log.info('playback stopped (barge-in)');
  }

  // ── WAV builder ───────────────────────────────────────────────────

  Uint8List _buildWav(Uint8List pcm, {int sampleRate = 24000}) {
    final byteRate = sampleRate * 2;
    final totalDataLen = pcm.length;
    final totalLen = 36 + totalDataLen;
    final header = ByteData(44);
    void w(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    w(0, 'RIFF');
    header.setUint32(4, totalLen, Endian.little);
    w(8, 'WAVE');
    w(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    w(36, 'data');
    header.setUint32(40, totalDataLen, Endian.little);
    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + pcm.length, pcm);
    return wav;
  }

  // ── Amplitude calculation ───────────────────────────────────────

  void _emitAmplitude(Uint8List pcm) {
    final sampleCount = pcm.length ~/ 2;
    if (sampleCount == 0) return;

    double sumSquares = 0;
    for (var i = 0; i < sampleCount; i++) {
      final lo = pcm[i * 2];
      final hi = pcm[i * 2 + 1];
      int sample = lo | (hi << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      sumSquares += sample * sample;
    }

    final rms = (sumSquares / sampleCount);
    const maxRms = 32767.0 * 32767.0;
    final linear = (rms / maxRms).clamp(0.0, 1.0);
    final normalized = (linear * 4.0).clamp(0.0, 1.0);
    final perceptual =
        normalized > 0 ? normalized * 0.7 + 0.3 * normalized * normalized : 0.0;

    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(perceptual.clamp(0.0, 1.0));
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _playbackTimeout?.cancel();
    _flushTimer?.cancel();
    _recordSub?.cancel();
    _turnId++;
    try {
      _player?.stop();
    } catch (_) {}
    _player?.dispose();
    _audioController.close();
    _amplitudeController.close();
    _recorder.dispose();
    _player = null;

    for (final path in _tempFiles) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
