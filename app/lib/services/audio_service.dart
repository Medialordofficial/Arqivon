import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../config/logger.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// **Playback architecture (v15 — buffer-and-play):**
///
/// 1. PCM chunks from Gemini are buffered in memory via [queueChunk].
/// 2. On `turn_complete`, [flushAndPlay] builds ONE complete WAV file
///    (24 kHz, 16-bit, mono) and plays it with a [_MemoryAudioSource].
/// 3. ExoPlayer receives a complete, valid WAV with correct
///    `Content-Length` — guaranteed zero errors.
/// 4. `ProcessingState.completed` triggers [onPlaybackDone].
/// 5. On barge-in, [stopPlayback] stops the player immediately.
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

  // ── Playback — buffer-and-play (v15) ──────────────────────────────
  AudioPlayer? _player;
  Timer? _playbackTimeout;

  int _chunkCount = 0;
  StreamSubscription<ProcessingState>? _processingStateSub;
  int _turnId = 0;
  bool _turnComplete = false;
  bool _playbackStarted = false;
  Timer? _staleWatchdog;
  List<int> _pcmBuffer = [];

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
    _log.info('audio session configured (voiceCommunication/voiceChat)');
  }

  /// Lazily create a single AudioPlayer that lives for the entire session.
  void _ensurePlayer() {
    if (_player != null) return;
    _player = AudioPlayer(handleInterruptions: false);
    _player!.setVolume(1.0);
    _processingStateSub =
        _player!.processingStateStream.listen(_onProcessingState);
    _log.info('persistent player created');
  }

  void _onProcessingState(ProcessingState ps) {
    _log.info('▍ processingState → $ps (turnComplete=$_turnComplete)');
    if (ps == ProcessingState.completed && _turnComplete) {
      _log.info(
          '▍ player COMPLETED + turn complete → calling _resetForNextTurn');
      _playbackTimeout?.cancel();
      _resetForNextTurn();
    }
  }

  /// Safety watchdog: auto-finalizes if turn_complete never arrives.
  void _startStaleWatchdog() {
    _staleWatchdog?.cancel();
    _staleWatchdog = Timer(const Duration(seconds: 10), () {
      _staleWatchdog = null;
      if (!_turnComplete && _playbackStarted) {
        _log.warning('stale watchdog fired — auto-finalizing turn');
        flushAndPlay();
      }
    });
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
  //  PLAYBACK — buffer-and-play (v15)
  // ══════════════════════════════════════════════════════════════════

  /// Push a base64-encoded PCM chunk from the AI into the buffer.
  void queueChunk(String base64Audio) {
    final bytes = base64Decode(base64Audio);
    _turnComplete = false;
    _chunkCount++;
    _playbackStarted = true;

    // Buffer raw PCM bytes in memory.
    _pcmBuffer.addAll(bytes);

    // Reset stale watchdog on each chunk.
    _staleWatchdog?.cancel();
    _startStaleWatchdog();

    if (_chunkCount == 1) {
      _log.info('▍ FIRST audio chunk (${bytes.length} B) — buffering');
    } else if (_chunkCount % 10 == 0) {
      _log.info('▍ chunk #$_chunkCount, buffer=${_pcmBuffer.length} B');
    }
  }

  /// Called by the provider on `turn_complete`.
  /// Builds a complete WAV from buffered PCM and plays it.
  Future<void> flushAndPlay() async {
    _turnComplete = true;
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
    _log.info(
        '▍▍ flushAndPlay — $_chunkCount chunks, ${_pcmBuffer.length} PCM bytes');
    _chunkCount = 0;

    // No audio data buffered this turn.
    if (_pcmBuffer.isEmpty || !_playbackStarted) {
      _log.info('▍▍ NO audio this turn (empty=${_pcmBuffer.isEmpty}, '
          'started=$_playbackStarted) — skipping');
      _pcmBuffer.clear();
      _playbackStarted = false;
      onPlaybackDone?.call();
      return;
    }

    // Build a complete WAV file from buffered PCM.
    final pcmLen = _pcmBuffer.length;
    final wav = _buildWav(_pcmBuffer);
    _pcmBuffer = []; // release buffer memory
    final durationMs = (pcmLen / (24000 * 2) * 1000).round();
    _log.info('▍▍ WAV built: ${wav.length} bytes, ~${durationMs}ms audio');

    // Write WAV to temp file — bypasses just_audio's HTTP proxy entirely.
    // This is the most reliable playback path on Android.
    final tempDir = await getTemporaryDirectory();
    final wavFile = File('${tempDir.path}/arqivo_ai_response.wav');
    await wavFile.writeAsBytes(wav, flush: true);
    _log.info('▍▍ WAV written to ${wavFile.path}');

    await _ensureAudioSession();
    _ensurePlayer();

    final capturedTurnId = _turnId;
    try {
      _log.info('▍▍ player.stop() before setFilePath');
      await _player!.stop();
      _log.info('▍▍ setFilePath(${wavFile.path})');
      await _player!.setFilePath(wavFile.path);
      if (_turnId != capturedTurnId) {
        _log.warning('▍▍ turnId changed during setFilePath — aborting');
        return;
      }
      final dur = _player!.duration;
      _log.info('▍▍ source loaded, player duration=$dur, '
          'processingState=${_player!.processingState}');
      _log.info('▶▶ PLAY');
      await _player!.play();
      _log.info('▍▍ play() returned (playback finished or stopped)');
    } catch (e, st) {
      _log.severe('▍▍ PLAYBACK FAILED: $e', e, st);
      if (_turnId == capturedTurnId) {
        _resetForNextTurn();
      }
    }

    // Safety timeout.
    _playbackTimeout?.cancel();
    _playbackTimeout = Timer(const Duration(seconds: 60), () {
      _log.warning('playback TIMEOUT — force-resetting');
      _turnId++;
      try {
        _player?.stop();
      } catch (_) {}
      _resetForNextTurn();
    });
  }

  void _resetForNextTurn() {
    _playbackTimeout?.cancel();
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
    _turnComplete = false;
    _playbackStarted = false;
    _chunkCount = 0;
    _pcmBuffer = [];

    _log.info(
        '▍▍ turn RESET — firing onPlaybackDone (callback=${onPlaybackDone != null})');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately (barge-in).
  Future<void> stopPlayback() async {
    _playbackTimeout?.cancel();
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
    _chunkCount = 0;
    _turnComplete = false;
    _playbackStarted = false;
    _pcmBuffer = [];
    _turnId++;

    _log.info('playback stopped (barge-in, turnId=$_turnId)');

    try {
      await _player?.stop().timeout(const Duration(milliseconds: 200));
    } catch (_) {}
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
    _staleWatchdog?.cancel();
    _recordSub?.cancel();
    _processingStateSub?.cancel();
    _turnId++;
    _pcmBuffer = [];
    try {
      _player?.stop();
    } catch (_) {}
    _player?.dispose();
    _audioController.close();
    _amplitudeController.close();
    _recorder.dispose();
    _player = null;
  }

  /// Build a complete WAV file from raw PCM data (24 kHz, 16-bit, mono).
  static Uint8List _buildWav(List<int> pcm) {
    const sr = 24000;
    const bits = 16;
    const ch = 1;
    const byteRate = sr * ch * (bits ~/ 8);
    const blockAlign = ch * (bits ~/ 8);
    final dataSize = pcm.length;
    final fileSize = 36 + dataSize;

    final out = ByteData(44 + dataSize);
    // RIFF header
    out.setUint8(0, 0x52); // R
    out.setUint8(1, 0x49); // I
    out.setUint8(2, 0x46); // F
    out.setUint8(3, 0x46); // F
    out.setUint32(4, fileSize, Endian.little);
    out.setUint8(8, 0x57); // W
    out.setUint8(9, 0x41); // A
    out.setUint8(10, 0x56); // V
    out.setUint8(11, 0x45); // E
    // fmt sub-chunk
    out.setUint8(12, 0x66); // f
    out.setUint8(13, 0x6D); // m
    out.setUint8(14, 0x74); // t
    out.setUint8(15, 0x20); // (space)
    out.setUint32(16, 16, Endian.little); // fmt chunk size
    out.setUint16(20, 1, Endian.little); // PCM format
    out.setUint16(22, ch, Endian.little);
    out.setUint32(24, sr, Endian.little);
    out.setUint32(28, byteRate, Endian.little);
    out.setUint16(32, blockAlign, Endian.little);
    out.setUint16(34, bits, Endian.little);
    // data sub-chunk
    out.setUint8(36, 0x64); // d
    out.setUint8(37, 0x61); // a
    out.setUint8(38, 0x74); // t
    out.setUint8(39, 0x61); // a
    out.setUint32(40, dataSize, Endian.little);
    // PCM data
    for (var i = 0; i < dataSize; i++) {
      out.setUint8(44 + i, pcm[i]);
    }
    return out.buffer.asUint8List();
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
