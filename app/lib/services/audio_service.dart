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
/// **Playback architecture (v4 — double-buffered, per-track players):**
///
/// 1. PCM chunks arrive via [queueChunk] → accumulate in [_pcmBuffer].
/// 2. A timer flushes them to WAV files → [_wavQueue].
/// 3. An async [_runPlaybackLoop] creates a **fresh [AudioPlayer] per track**,
///    uses **`await player.play()`** (which blocks until the track finishes),
///    then disposes the player.
/// 4. While the current track plays, the **next track is preloaded** into a
///    second player (`setAudioSource` runs concurrently). When the current
///    track ends, the preloaded player is ready → **zero gap**.
/// 5. Barge-in: [stopPlayback] increments [_turnId], which breaks the loop's
///    `while` condition. It also stops the active player, which makes
///    `await player.play()` return immediately.
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

  // ── Playback ──────────────────────────────────────────────────────
  /// Reference to the currently *playing* player so [stopPlayback] can stop it.
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
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    _sessionConfigured = true;
    _log.info('audio session configured');
  }

  // ── Recording ─────────────────────────────────────────────────────

  int _recordChunkCount = 0;
  DateTime _lastRecordData = DateTime.now();

  Future<void> start() async {
    if (_isCapturing || _disposed) return;
    await _ensureAudioSession();

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
  //  PLAYBACK — double-buffered fresh-player architecture
  // ══════════════════════════════════════════════════════════════════

  /// Queue a base64-encoded PCM chunk from the AI into the buffer.
  void queueChunk(String base64Audio) {
    final bytes = base64Decode(base64Audio);
    _pcmBuffer.addAll(bytes);

    if (_flushTimer == null || !_flushTimer!.isActive) {
      // First chunk → flush quickly (200ms) for low latency.
      // Loop already running → accumulate for 2s for bigger WAV files
      // (fewer tracks = fewer player transitions = smoother).
      final ms = !_loopRunning ? 200 : 2000;
      _flushTimer = Timer(Duration(milliseconds: ms), _flush);
    }
    // Hard cap: don't let buffer grow past ~10s of audio.
    if (_pcmBuffer.length >= 480000) {
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
        scheduleMicrotask(() => _flush());
      }
    }
  }

  Future<void> _doFlush() async {
    if (_pcmBuffer.isEmpty) return;
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
    _log.info('WAV queued: #${_chunkIndex - 1}, ${pcm.length} bytes, '
        'queue=${_wavQueue.length}');

    // Start the playback loop if not already running.
    if (!_loopRunning) {
      _loopRunning = true;
      unawaited(_runPlaybackLoop(turnSnapshot));
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  PLAYBACK LOOP — fresh player per track, with preloading
  // ──────────────────────────────────────────────────────────────────

  Future<void> _runPlaybackLoop(int turnSnapshot) async {
    _log.info('▶ playback loop START (turn=$turnSnapshot)');
    await _ensureAudioSession();
    if (_turnId != turnSnapshot) {
      _loopRunning = false;
      return;
    }

    // The "preloaded" player: while current track plays, we prepare the
    // next track here so it can start with zero latency.
    AudioPlayer? preloadedPlayer;

    try {
      while (_turnId == turnSnapshot) {
        // ────────────────────────────────────────────────────────────
        // STEP 1: Get a player with a loaded track.
        // ────────────────────────────────────────────────────────────
        AudioPlayer player;

        if (preloadedPlayer != null) {
          // Preloaded player is ready → use it (zero latency).
          player = preloadedPlayer;
          preloadedPlayer = null;
          _log.info('♪ using preloaded player');
        } else {
          // No preload available — wait for a WAV in the queue.
          while (_wavQueue.isEmpty) {
            if (_turnComplete && _pcmBuffer.isEmpty) {
              _log.info('✓ turn complete, no more tracks');
              return; // → finally block runs
            }
            if (_turnId != turnSnapshot) return;
            // Demand-driven flush: if PCM is buffered, flush NOW.
            if (_pcmBuffer.isNotEmpty && !_flushing) {
              _flushTimer?.cancel();
              await _flush();
            }
            await Future.delayed(const Duration(milliseconds: 40));
          }
          if (_turnId != turnSnapshot) return;

          // Dequeue and load into a fresh player.
          final path = _wavQueue.removeAt(0);
          player = AudioPlayer();
          try {
            await player.setAudioSource(AudioSource.uri(Uri.file(path)));
          } catch (e) {
            _log.severe('setAudioSource FAILED: $e');
            unawaited(player.dispose().catchError((_) {}));
            continue; // skip this track
          }
          if (_turnId != turnSnapshot) {
            unawaited(player.dispose().catchError((_) {}));
            return;
          }
        }

        // Store reference so stopPlayback() can stop it.
        _player = player;

        // ────────────────────────────────────────────────────────────
        // STEP 2: Preload the NEXT track concurrently while we play.
        // ────────────────────────────────────────────────────────────
        final preloadFuture = _preloadNextTrack(turnSnapshot);

        // ────────────────────────────────────────────────────────────
        // STEP 3: Play and await completion.
        //
        // player.play() returns a Future that resolves when:
        //   a) The track finishes naturally (completed)
        //   b) player.stop() is called (barge-in)
        //   c) An error occurs (throws)
        // This is 100% reliable — no Completers, no stream listeners.
        // ────────────────────────────────────────────────────────────
        try {
          _log.info('♪ PLAY track (queue=${_wavQueue.length} remain)');
          // Timeout = track duration + 5s safety (or 30s default).
          final dur = player.duration;
          final timeout = dur != null
              ? dur + const Duration(seconds: 5)
              : const Duration(seconds: 30);
          await player.play().timeout(timeout, onTimeout: () {
            _log.warning('play() timed out after $timeout — skipping');
          });
          _log.info('♪ track DONE');
        } catch (e) {
          _log.severe('play() error: $e');
        }

        // ────────────────────────────────────────────────────────────
        // STEP 4: Dispose current player, await preload result.
        // ────────────────────────────────────────────────────────────
        _player = null;
        unawaited(player.dispose().catchError((_) {}));

        // Wait for preload to finish (usually already done by now).
        preloadedPlayer = await preloadFuture;
      }
    } finally {
      // Clean up.
      preloadedPlayer?.dispose();
      _loopRunning = false;
      _player = null;
      if (_turnId == turnSnapshot) {
        _log.info('▶ playback loop END — resetForNextTurn');
        _resetForNextTurn();
      } else {
        _log.info('▶ playback loop END — turn was cancelled');
      }
    }
  }

  /// Preload the next WAV into a fresh player while the current track plays.
  /// Returns the preloaded player, or `null` if no track is available.
  Future<AudioPlayer?> _preloadNextTrack(int turnSnapshot) async {
    // Wait for a WAV to become available.
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (_wavQueue.isEmpty && DateTime.now().isBefore(deadline)) {
      if (_turnComplete && _pcmBuffer.isEmpty) return null;
      if (_turnId != turnSnapshot) return null;
      // Demand-driven flush — produce WAVs as fast as PCM arrives.
      if (_pcmBuffer.isNotEmpty && !_flushing) {
        _flushTimer?.cancel();
        await _flush();
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (_wavQueue.isEmpty || _turnId != turnSnapshot) return null;

    final path = _wavQueue.removeAt(0);
    final player = AudioPlayer();
    try {
      await player.setAudioSource(AudioSource.uri(Uri.file(path)));
      if (_turnId != turnSnapshot) {
        unawaited(player.dispose().catchError((_) {}));
        return null;
      }
      _log.info('⟳ preloaded next track');
      return player;
    } catch (e) {
      _log.warning('preload setAudioSource failed: $e');
      unawaited(player.dispose().catchError((_) {}));
      return null;
    }
  }

  /// Called by the provider on `turn_complete`.
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _turnComplete = true;
    _log.info('flushAndPlay — pcmBuf=${_pcmBuffer.length}, '
        'queue=${_wavQueue.length}, loop=$_loopRunning');

    if (_pcmBuffer.isNotEmpty) await _flush();

    if (!_loopRunning && _wavQueue.isEmpty) {
      _log.info('no audio this turn');
      onPlaybackDone?.call();
      return;
    }

    // Safety timeout in case the loop hangs.
    _playbackTimeout?.cancel();
    _playbackTimeout = Timer(const Duration(seconds: 120), () {
      _log.warning('playback TIMEOUT — force-resetting');
      _turnId++;
      // Stopping the player will unblock await player.play() in the loop.
      _player?.stop();
      _resetForNextTurn();
    });
  }

  void _resetForNextTurn() {
    _playbackTimeout?.cancel();
    _turnComplete = false;
    _chunkIndex = 0;
    _wavQueue.clear();
    _player = null;

    final files = List<String>.from(_tempFiles);
    _tempFiles.clear();
    unawaited(Future(() async {
      for (final p in files) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }));

    _log.info('turn reset — onPlaybackDone');
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
    _turnId++; // breaks the loop's while(_turnId == turnSnapshot)
    _wavQueue.clear();

    final files = List<String>.from(_tempFiles);
    _tempFiles.clear();

    // Stop the active player — this makes `await player.play()` return
    // immediately in the loop, which then exits due to _turnId mismatch.
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      unawaited(player.dispose().catchError((_) {}));
    }

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
    _turnId++; // breaks playback loop
    _player?.stop(); // unblocks await player.play()
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
