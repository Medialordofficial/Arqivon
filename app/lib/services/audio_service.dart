import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/logger.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// **Playback architecture (v16 — streaming AudioTrack):**
///
/// 1. PCM chunks from Gemini are written directly to Android's AudioTrack
///    via a platform channel — audio plays immediately, no buffering.
/// 2. Each chunk is heard within ~20ms of arriving from the server.
/// 3. Interruption is instant: AudioTrack.pause() + flush().
/// 4. No WAV files, no ExoPlayer, no just_audio overhead.
class AudioService {
  static final _log = AppLogger('AudioService');
  static const _channel = MethodChannel('com.notanovice.arqivon/audio_track');

  // ── Recording ──────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  final StreamController<String> _audioController =
      StreamController<String>.broadcast();
  bool _isCapturing = false;
  bool _disposed = false;

  static const int _chunkTargetBytes = 1600; // 50 ms @ 16 kHz, 16-bit mono
  final List<int> _recordRing = [];

  // ── Playback — streaming AudioTrack (v16) ─────────────────────────
  bool _trackCreated = false;
  int _chunkCount = 0;
  int _turnId = 0;
  bool _isStreamingPlayback = false;
  Timer? _silenceTimer; // fires when no audio for X seconds → turn done

  /// Called when the AI turn's playback finishes (silence detected after audio).
  VoidCallback? onPlaybackDone;

  /// Whether the AI is actively streaming audio right now.
  bool get isPlaying => _isStreamingPlayback;

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

  /// Create the AudioTrack on the native side.
  Future<void> _ensureTrack() async {
    if (_trackCreated) return;
    try {
      final bufSize =
          await _channel.invokeMethod('create', {'sampleRate': 24000});
      _trackCreated = true;
      _log.info('AudioTrack created (bufSize=$bufSize)');
    } catch (e) {
      _log.severe('AudioTrack create failed', e);
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
  //  PLAYBACK — streaming AudioTrack (v16)
  // ══════════════════════════════════════════════════════════════════

  /// Write a base64-encoded PCM chunk directly to AudioTrack for instant playback.
  Future<void> queueChunk(String base64Audio) async {
    final bytes = base64Decode(base64Audio);
    _chunkCount++;
    _isStreamingPlayback = true;

    // Reset silence timer on each chunk — after last chunk + turn_complete,
    // the silence timer fires to signal playback done.
    _silenceTimer?.cancel();

    if (_chunkCount == 1) {
      _log.info(
          '▍ FIRST audio chunk (${bytes.length} B) — streaming to AudioTrack');
      await _ensureAudioSession();
      await _ensureTrack();
    }

    if (_chunkCount % 20 == 0) {
      _log.info('▍ chunk #$_chunkCount streamed');
    }

    // Write PCM directly to AudioTrack — plays immediately.
    try {
      await _channel.invokeMethod('write', {'data': Uint8List.fromList(bytes)});
    } catch (e) {
      _log.severe('AudioTrack write failed', e);
    }
  }

  /// Called on turn_complete. With streaming, audio is already playing.
  /// Just start the silence timer to detect when playback finishes.
  void flushAndPlay() {
    _log.info('▍▍ flushAndPlay — $_chunkCount chunks streamed');

    if (_chunkCount == 0) {
      _log.info('▍▍ no audio this turn — skipping');
      if (!_isStreamingPlayback) {
        onPlaybackDone?.call();
      }
      return;
    }

    // Audio is already playing via AudioTrack streaming.
    // Estimate remaining playback time based on chunks written.
    // Each chunk is ~1920 bytes = 40ms at 24kHz 16-bit mono.
    // Use a generous timer to detect when the AudioTrack buffer drains.
    _startSilenceTimer();
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    // Wait 1.5s after last chunk — AudioTrack buffer should be drained by then.
    _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
      _silenceTimer = null;
      if (_isStreamingPlayback) {
        _log.info('▍▍ silence timer fired — playback done');
        _resetForNextTurn();
      }
    });
  }

  void _resetForNextTurn() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _isStreamingPlayback = false;
    _chunkCount = 0;
    _log.info('▍▍ turn RESET — firing onPlaybackDone');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately (barge-in).
  Future<void> stopPlayback() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _chunkCount = 0;
    _isStreamingPlayback = false;
    _turnId++;

    _log.info('playback stopped (barge-in, turnId=$_turnId)');

    try {
      await _channel.invokeMethod('stop');
      // Re-create the track so it's ready for the next response.
      _trackCreated = false;
    } catch (e) {
      _log.severe('AudioTrack stop failed', e);
    }
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
    _silenceTimer?.cancel();
    _recordSub?.cancel();
    _turnId++;
    try {
      _channel.invokeMethod('release');
    } catch (_) {}
    _trackCreated = false;
    _audioController.close();
    _amplitudeController.close();
    _recorder.dispose();
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
