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
/// **Playback architecture (v7 — ConcatenatingAudioSource, gapless):**
///
/// 1. PCM chunks arrive via [queueChunk] → accumulate in [_pcmBuffer].
/// 2. A timer flushes them to WAV files.
/// 3. Each WAV is added to a [ConcatenatingAudioSource] playlist.
/// 4. A **single [AudioPlayer]** plays the playlist — just_audio handles
///    gapless transitions between tracks automatically by pre-buffering.
/// 5. Barge-in: [stopPlayback] calls `player.stop()` + `playlist.clear()`.
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

  // ── Playback — ConcatenatingAudioSource (gapless) ─────────────────
  AudioPlayer? _player;
  Timer? _playbackTimeout;
  Timer? _flushTimer;

  final List<int> _pcmBuffer = [];
  final List<String> _tempFiles = [];
  ConcatenatingAudioSource? _playlist;
  StreamSubscription<ProcessingState>? _processingStateSub;
  int _chunkIndex = 0;
  int _turnId = 0;
  bool _flushing = false;
  bool _reflushNeeded = false;
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
    _processingStateSub =
        _player!.processingStateStream.listen(_onProcessingState);
    _log.info('persistent player created');
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed && _turnComplete) {
      // Debounce: wait 250ms to let any in-flight _enqueueWav finish.
      // Without this, a flush completing right now would add a new track
      // to the playlist — but we'd have already reset and killed it.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (_turnComplete &&
            _player?.processingState == ProcessingState.completed &&
            _pcmBuffer.isEmpty &&
            !_flushing) {
          _log.info('player completed all tracks + turn complete → done');
          _playbackTimeout?.cancel();
          _resetForNextTurn();
        }
      });
    }
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
  //  PLAYBACK — ConcatenatingAudioSource, gapless (v7)
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
      // First flush of a turn: wait 600ms to accumulate a substantial
      // first WAV (~600ms of audio). This prevents the player from
      // completing a tiny first track before the next is ready.
      // Subsequent flushes: 400ms for smooth streaming.
      final delay = _playlist == null
          ? const Duration(milliseconds: 600)
          : const Duration(milliseconds: 400);
      _flushTimer = Timer(delay, _flush);
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
    final audioDurationMs = (pcm.length / (24000 * 2) * 1000).round();
    _log.info('WAV flushed: #${_chunkIndex - 1}, ${pcm.length} bytes '
        '(${audioDurationMs}ms audio)');

    await _enqueueWav(path, turnSnapshot);
  }

  // ──────────────────────────────────────────────────────────────────
  //  GAPLESS PLAYBACK — ConcatenatingAudioSource
  //  just_audio pre-buffers the next track while the current plays,
  //  eliminating the 20-80ms gap that sequential setAudioSource caused.
  // ──────────────────────────────────────────────────────────────────

  Future<void> _enqueueWav(String path, int turnSnapshot) async {
    await _ensureAudioSession();
    _ensurePlayer();
    if (_turnId != turnSnapshot) return;

    final isFirst = _playlist == null;
    // When the player has completed all previous tracks, we MUST create
    // a fresh ConcatenatingAudioSource and call setAudioSource.
    // Trying to seek+play within a completed playlist is unreliable in
    // just_audio — it silently fails on many devices, causing audio to
    // stop mid-response for long answers.
    final needsResume =
        !isFirst && _player!.processingState == ProcessingState.completed;

    if (isFirst || needsResume) {
      _playlist = ConcatenatingAudioSource(children: []);
      try {
        await _player!.setAudioSource(_playlist!);
      } catch (e) {
        _log.severe('setAudioSource(playlist) failed: $e');
        return;
      }
    }
    if (_turnId != turnSnapshot) return;

    try {
      await _playlist!.add(AudioSource.file(path));
    } catch (e) {
      _log.warning('playlist.add failed: $e');
      return;
    }
    if (_turnId != turnSnapshot) return;

    if (isFirst || needsResume) {
      final label = isFirst ? 'START' : 'RESUME';
      _log.info('▶ $label gapless playback');
      _player!.play();
    } else {
      final idx = _playlist!.length - 1;
      _log.info('♪ track $idx queued (gapless, '
          'playlist=${_playlist!.length})');
    }
  }

  /// Called by the provider on `turn_complete`.
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _turnComplete = true;
    _log.info('flushAndPlay — pcmBuf=${_pcmBuffer.length}, '
        'playlist=${_playlist?.length ?? 0}');

    if (_pcmBuffer.isNotEmpty) await _flush();

    // Wait for any in-progress flush to finish (up to 500ms).
    // Disk writes on slower devices can take 100-300ms.
    int waitMs = 0;
    while ((_flushing || _reflushNeeded) && waitMs < 500) {
      await Future.delayed(const Duration(milliseconds: 15));
      waitMs += 15;
    }
    if (_pcmBuffer.isNotEmpty) await _flush();

    // Second wait: the reflush from the first flush may have started.
    waitMs = 0;
    while (_flushing && waitMs < 300) {
      await Future.delayed(const Duration(milliseconds: 15));
      waitMs += 15;
    }

    // If nothing was played this turn at all.
    if (_playlist == null || _playlist!.length == 0) {
      _log.info('no audio this turn');
      onPlaybackDone?.call();
      return;
    }

    // If player already finished all tracks, fire done now.
    if (_player?.processingState == ProcessingState.completed) {
      if (_pcmBuffer.isEmpty && !_flushing) {
        _log.info('player already completed — turn done');
        _resetForNextTurn();
        return;
      }
    }

    // Safety timeout in case playback hangs.
    // 120s is generous — a long Gemini response can be 30-60s of audio,
    // and the player may need to resume multiple batches.
    _playbackTimeout?.cancel();
    _playbackTimeout = Timer(const Duration(seconds: 120), () {
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
    _playlist = null;
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
    _turnId++;

    try {
      await _player?.stop();
    } catch (_) {}
    // Clear the playlist so player doesn't auto-advance.
    try {
      await _playlist?.clear();
    } catch (_) {}
    _playlist = null;

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
    _processingStateSub?.cancel();
    _turnId++;
    try {
      _player?.stop();
    } catch (_) {}
    _player?.dispose();
    _audioController.close();
    _amplitudeController.close();
    _recorder.dispose();
    _player = null;
    _playlist = null;

    for (final path in _tempFiles) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
