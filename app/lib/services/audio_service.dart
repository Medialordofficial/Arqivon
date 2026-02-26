import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../config/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// Recording uses [AudioRecorder] from the `record` package.
/// Playback creates a **fresh [AudioPlayer]** for every AI response turn,
/// eliminating stale player state that caused the mic to go silent after
/// the first turn on Android.
///
/// The mic stays active during AI playback to allow barge-in (Gemini's native
/// VAD detects the user speaking and sends an `interrupted` signal).
class AudioService {
  static final _log = AppLogger('AudioService');

  // ── Recording ──────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  final StreamController<String> _audioController =
      StreamController<String>.broadcast();
  bool _isCapturing = false;
  bool _disposed = false;

  // ── Playback (fresh per turn) ──────────────────────────────────────
  AudioPlayer? _turnPlayer;
  ConcatenatingAudioSource? _turnPlaylist;
  StreamSubscription<PlayerState>? _playbackSub;
  bool _playbackStarted = false;

  // PCM accumulation buffer – flushed periodically into WAV temp files.
  final List<int> _pcmBuffer = [];
  Timer? _flushTimer;
  static const int _flushIntervalMs = 250;
  static const int _minFlushBytes = 2400; // ~50 ms @ 24 kHz 16-bit mono
  int _chunkIndex = 0;
  final List<String> _tempFiles = [];

  /// Called when the AI turn's playback finishes (or if no audio was queued).
  VoidCallback? onPlaybackDone;

  bool _sessionConfigured = false;

  // ── Audio amplitude for visualizer ──────────────────────────────
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  /// Stream of RMS amplitude values (0.0–1.0) from the microphone input.
  /// Used by the orb visualizer for audio-reactive animation.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  // ── Public getters ─────────────────────────────────────────────────
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
        // Use `media` usage to avoid Android's VoIP echo-canceller path which
        // can silently kill the recorder when the player stops/starts.
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

  /// Start microphone capture. Safe to call multiple times – silently returns
  /// if already capturing.
  int _recordChunkCount = 0;

  Future<void> start() async {
    if (_isCapturing || _disposed) return;
    await _ensureAudioSession();

    // Always stop first for a clean slate.
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
      _recordSub?.cancel();
      _recordSub = stream.listen(
        (data) {
          _recordChunkCount++;
          if (_recordChunkCount % 100 == 1) {
            _log.fine(
              'recorder data chunk #$_recordChunkCount (${data.length} bytes)',
            );
          }
          if (!_audioController.isClosed) {
            _audioController.add(base64Encode(data));
          }
          // Compute RMS amplitude for the orb visualizer.
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
          // Auto-restart after a brief delay unless we were disposed.
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
      // Retry after a delay — audio focus may not be released yet
      if (!_disposed) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_disposed && !_isCapturing) {
            start();
          }
        });
      }
    }
  }

  /// Stop microphone capture.
  Future<void> stop() async {
    _isCapturing = false;
    _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
    } catch (e) {
      _log.fine('stop recorder: $e');
    }
    _log.info('recorder stopped');
  }

  /// Force-restart the recorder after AI playback finishes.
  ///
  /// On Android, the native recorder can silently stop emitting data when
  /// audio focus changes (e.g. during AI playback) WITHOUT firing `onDone`.
  /// The `_isCapturing` flag stays `true` but the platform stream is dead.
  /// The only reliable fix is to tear down and recreate the stream.
  Future<void> ensureRecording() async {
    if (_disposed) return;
    _log.info('ensureRecording — force-restarting recorder');
    // Tear down existing stream regardless of _isCapturing flag
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

  // ── Playback ──────────────────────────────────────────────────────

  /// Queue a base64-encoded PCM chunk from the AI into the playback buffer.
  void queueChunk(String base64Audio) {
    final bytes = base64Decode(base64Audio);
    _pcmBuffer.addAll(bytes);

    // Debounce: flush after a short idle window so we accumulate small chunks
    // into a larger WAV.
    _flushTimer?.cancel();
    _flushTimer = Timer(
      const Duration(milliseconds: _flushIntervalMs),
      _flushPartial,
    );
  }

  /// Write buffered PCM to a temp WAV file, add it to the turn's playlist,
  /// and start (or resume) the player.
  Future<void> _flushPartial() async {
    if (_pcmBuffer.length < _minFlushBytes) return;

    final pcm = Uint8List.fromList(_pcmBuffer);
    _pcmBuffer.clear();

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/ai_chunk_${_chunkIndex++}.wav';
    final wav = _buildWav(pcm, sampleRate: 24000);
    await File(filePath).writeAsBytes(wav, flush: true);
    _tempFiles.add(filePath);

    // Lazily create a brand-new player + playlist for this turn.
    _turnPlayer ??= AudioPlayer();
    _turnPlaylist ??= ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: [],
    );

    await _turnPlaylist!.add(AudioSource.uri(Uri.file(filePath)));

    if (!_playbackStarted) {
      _playbackStarted = true;
      try {
        await _turnPlayer!.setAudioSource(_turnPlaylist!);
        _turnPlayer!.play();
        _log.info('turn playback started');
      } catch (e) {
        _log.severe('turn playback start error', e);
        _playbackStarted = false;
      }
    } else if (_turnPlayer!.processingState == ProcessingState.completed) {
      // Player reached end before the new chunk was added — seek to it.
      try {
        final idx = _turnPlaylist!.length - 1;
        await _turnPlayer!.seek(Duration.zero, index: idx);
        _turnPlayer!.play();
        _log.info('resumed playback at index $idx');
      } catch (e) {
        _log.severe('seek-to-new-chunk error', e);
      }
    }
  }

  /// Called on `turn_complete` — flush any remaining PCM, then wait for the
  /// turn player to finish before calling [onPlaybackDone].
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _log.info(
      'flushAndPlay called, pcmBuffer=${_pcmBuffer.length} bytes, turnPlayer=${_turnPlayer != null}',
    );

    // Flush remaining PCM.
    if (_pcmBuffer.isNotEmpty) {
      final pcm = Uint8List.fromList(_pcmBuffer);
      _pcmBuffer.clear();

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/ai_chunk_${_chunkIndex++}.wav';
      final wav = _buildWav(pcm, sampleRate: 24000);
      await File(filePath).writeAsBytes(wav, flush: true);
      _tempFiles.add(filePath);

      _turnPlayer ??= AudioPlayer();
      _turnPlaylist ??= ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: [],
      );
      await _turnPlaylist!.add(AudioSource.uri(Uri.file(filePath)));

      if (!_playbackStarted) {
        _playbackStarted = true;
        try {
          await _turnPlayer!.setAudioSource(_turnPlaylist!);
          _turnPlayer!.play();
        } catch (e) {
          _log.severe('flush play error', e);
          _playbackStarted = false;
        }
      } else if (_turnPlayer!.processingState == ProcessingState.completed) {
        try {
          final idx = _turnPlaylist!.length - 1;
          await _turnPlayer!.seek(Duration.zero, index: idx);
          _turnPlayer!.play();
        } catch (e) {
          _log.severe('flush seek error', e);
        }
      }
    }

    // Listen for playback completion, then dispose the turn player.
    if (_turnPlayer != null) {
      // Cancel any previous listener.
      _playbackSub?.cancel();

      // Check if already completed *before* subscribing.
      if (_turnPlayer!.processingState == ProcessingState.completed) {
        _disposeTurnPlayer();
        return;
      }

      _playbackSub = _turnPlayer!.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _playbackSub?.cancel();
          _playbackSub = null;
          _disposeTurnPlayer();
        }
      });
    } else {
      // No audio arrived this turn — fire done immediately.
      _log.info('no audio this turn, firing onPlaybackDone');
      onPlaybackDone?.call();
    }
  }

  /// Tear down the current turn's player and playlist, then notify caller.
  void _disposeTurnPlayer() {
    _playbackStarted = false;
    final player = _turnPlayer;
    final playlist = _turnPlaylist;
    final files = List<String>.from(_tempFiles);
    _turnPlayer = null;
    _turnPlaylist = null;
    _tempFiles.clear();

    // Run disposal asynchronously to avoid re-entrance inside the player
    // state listener callback.
    unawaited(
      Future(() async {
        try {
          await player?.stop();
        } catch (e) {
          _log.fine('turn player stop: $e');
        }
        try {
          await player?.dispose();
        } catch (e) {
          _log.fine('turn player dispose: $e');
        }
        // Clear the ConcatenatingAudioSource children (optional but tidy).
        try {
          await playlist?.clear();
        } catch (e) {
          _log.fine('turn playlist clear: $e');
        }

        for (final path in files) {
          try {
            await File(path).delete();
          } catch (e) {
            _log.fine('temp file delete: $e');
          }
        }

        _log.info('turn player disposed — calling onPlaybackDone');
        onPlaybackDone?.call();
      }),
    );
  }

  /// Stop playback immediately (barge-in from user).
  Future<void> stopPlayback() async {
    _flushTimer?.cancel();
    _pcmBuffer.clear();
    _playbackSub?.cancel();
    _playbackSub = null;
    _playbackStarted = false;

    final player = _turnPlayer;
    _turnPlayer = null;
    _turnPlaylist = null;

    try {
      await player?.stop();
    } catch (e) {
      _log.fine('stopPlayback stop: $e');
    }
    try {
      await player?.dispose();
    } catch (e) {
      _log.fine('stopPlayback dispose: $e');
    }

    for (final path in _tempFiles) {
      try {
        await File(path).delete();
      } catch (e) {
        _log.fine('stopPlayback file delete: $e');
      }
    }
    _tempFiles.clear();
    _log.info('playback stopped (barge-in)');
  }

  // ── WAV builder ───────────────────────────────────────────────────

  /// Build a minimal WAV (RIFF) container around raw PCM-16 mono data.
  Uint8List _buildWav(Uint8List pcm, {int sampleRate = 24000}) {
    final byteRate = sampleRate * 2; // 16-bit mono
    final totalDataLen = pcm.length;
    final totalLen = 36 + totalDataLen;

    final header = ByteData(44);
    void writeStr(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    header.setUint32(4, totalLen, Endian.little);
    writeStr(8, 'WAVE');

    // fmt sub-chunk
    writeStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // sub-chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample

    // data sub-chunk
    writeStr(36, 'data');
    header.setUint32(40, totalDataLen, Endian.little);

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + pcm.length, pcm);
    return wav;
  }

  // ── Amplitude calculation ───────────────────────────────────────

  /// Compute RMS amplitude from raw PCM-16 data and emit a normalized
  /// value (0.0–1.0) for the orb visualizer.
  void _emitAmplitude(Uint8List pcm) {
    // PCM-16 LE mono: 2 bytes per sample
    final sampleCount = pcm.length ~/ 2;
    if (sampleCount == 0) return;

    double sumSquares = 0;
    for (var i = 0; i < sampleCount; i++) {
      // Read 16-bit signed little-endian sample.
      final lo = pcm[i * 2];
      final hi = pcm[i * 2 + 1];
      int sample = lo | (hi << 8);
      if (sample >= 0x8000) sample -= 0x10000; // sign-extend
      sumSquares += sample * sample;
    }

    final rms = (sumSquares / sampleCount);
    // Normalize: PCM-16 max is 32767, so max squared is ~1.07e9.
    // Use a log scale for perceptual mapping, clamped to 0.0–1.0.
    const maxRms = 32767.0 * 32767.0;
    final linear = (rms / maxRms).clamp(0.0, 1.0);
    // Apply sqrt for more perceptual response (quiet sounds are more visible).
    final normalized = (linear * 4.0).clamp(0.0, 1.0); // boost sensitivity
    final perceptual =
        normalized > 0 ? normalized * 0.7 + 0.3 * normalized * normalized : 0.0;

    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(perceptual.clamp(0.0, 1.0));
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _recordSub?.cancel();
    _playbackSub?.cancel();
    _audioController.close();
    _amplitudeController.close();
    _recorder.dispose();

    try {
      _turnPlayer?.stop();
    } catch (e) {
      _log.fine('dispose stop: $e');
    }
    try {
      _turnPlayer?.dispose();
    } catch (e) {
      _log.fine('dispose player: $e');
    }

    for (final path in _tempFiles) {
      try {
        File(path).deleteSync();
      } catch (e) {
        _log.fine('dispose file delete: $e');
      }
    }
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
