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

  // ── 100 ms audio chunking ring buffer ──────────────────────────────
  // The `record` package emits variable-size PCM chunks. We accumulate
  // them and emit exact 100 ms chunks (3 200 bytes at 16 kHz mono 16-bit)
  // for consistent Gemini VAD behaviour and optimal bandwidth while
  // keeping input latency under 100 ms.
  static const int _chunkTargetBytes = 1600; // 50 ms @ 16 kHz, 16-bit mono
  final List<int> _recordRing = [];

  // ── Playback (fresh player per turn) ──────────────────────────────
  /// Each AI response turn gets its own [AudioPlayer].  The previous
  /// turn's player is disposed lazily when the NEW turn starts, so
  /// audio focus is never released between turns (the root-cause of the
  /// "no voice after N turns" bug on Android).
  AudioPlayer? _player;
  AudioPlayer? _oldPlayer; // kept alive until the next turn starts
  ConcatenatingAudioSource? _turnPlaylist;
  StreamSubscription<PlayerState>? _playbackSub;
  bool _playbackStarted = false;

  // PCM accumulation buffer – flushed periodically into WAV temp files.
  final List<int> _pcmBuffer = [];
  Timer? _flushTimer;
  static const int _flushIntervalMs = 40; // lower = faster first-audio
  static const int _minFlushBytes = 480; // ~10 ms @ 24 kHz 16-bit mono
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
      _recordRing.clear();
      _recordSub?.cancel();
      _recordSub = stream.listen(
        (data) {
          _recordChunkCount++;
          if (_recordChunkCount % 100 == 1) {
            _log.fine(
              'recorder data chunk #$_recordChunkCount (${data.length} bytes)',
            );
          }
          // ── Ring-buffer: accumulate then emit exact 100ms chunks ──
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
  ///
  /// Flushes any residual bytes in the ring buffer so the last partial
  /// chunk of user speech is not silently dropped.
  Future<void> stop() async {
    _isCapturing = false;
    _recordSub?.cancel();
    _recordSub = null;
    // Flush residual ring-buffer bytes so the user's last syllable
    // isn't lost. Gemini handles variable-size chunks fine.
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

    // Throttle (NOT debounce): start a timer on the first chunk, and
    // do NOT reset it when subsequent chunks arrive. This guarantees
    // audio starts playing within _flushIntervalMs of the very first
    // chunk, even if Gemini sends chunks in rapid succession.
    if (_flushTimer == null || !_flushTimer!.isActive) {
      _flushTimer = Timer(
        const Duration(milliseconds: _flushIntervalMs),
        _flushPartial,
      );
    }
    // Hard cap: if buffer grows beyond 0.5 s of audio (24 000 bytes at
    // 24 kHz 16-bit mono), flush immediately to prevent unbounded
    // buffering during fast Gemini responses.
    if (_pcmBuffer.length >= 24000) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _flushPartial();
    }
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

    // First chunk of a new turn → create a fresh player & playlist.
    if (_turnPlaylist == null) {
      // Dispose the OLD turn's player in the background — but only now,
      // so audio focus was held continuously between turns.
      _disposeOldPlayer();
      await _ensureAudioSession();
      _player = AudioPlayer();
      _turnPlaylist = ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: [],
      );
      _playbackStarted = false;
    }

    await _turnPlaylist!.add(AudioSource.uri(Uri.file(filePath)));

    if (!_playbackStarted) {
      _playbackStarted = true;
      try {
        await _player!.setAudioSource(_turnPlaylist!);
        _player!.play();
        _log.info('turn playback started');
      } catch (e) {
        _log.severe('turn playback start error', e);
        _playbackStarted = false;
      }
    } else if (_player!.processingState == ProcessingState.completed) {
      // Player reached end before the new chunk was added — seek to it.
      try {
        final idx = _turnPlaylist!.length - 1;
        await _player!.seek(Duration.zero, index: idx);
        _player!.play();
        _log.info('resumed playback at index $idx');
      } catch (e) {
        _log.severe('seek-to-new-chunk error', e);
      }
    }
  }

  /// Dispose the previous turn's player in the background.
  void _disposeOldPlayer() {
    final old = _oldPlayer;
    _oldPlayer = null;
    if (old == null) return;
    unawaited(Future(() async {
      try {
        await old.stop();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }));
  }

  /// Called on `turn_complete` — flush any remaining PCM, then wait for the
  /// turn player to finish before calling [onPlaybackDone].
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _log.info(
      'flushAndPlay called, pcmBuffer=${_pcmBuffer.length} bytes, player=${_player != null}',
    );

    // Flush remaining PCM.
    if (_pcmBuffer.isNotEmpty) {
      await _flushPartial();
    }

    // Listen for playback completion, then reset for the next turn.
    if (_player != null && _turnPlaylist != null) {
      // Cancel any previous listener.
      _playbackSub?.cancel();

      // Check if already completed *before* subscribing.
      if (_player!.processingState == ProcessingState.completed) {
        _resetForNextTurn();
        return;
      }

      _playbackSub = _player!.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _playbackSub?.cancel();
          _playbackSub = null;
          _resetForNextTurn();
        }
      });
    } else {
      // No audio arrived this turn — fire done immediately.
      _log.info('no audio this turn, firing onPlaybackDone');
      onPlaybackDone?.call();
    }
  }

  /// Reset playback state for the next AI turn.
  ///
  /// The current player is moved to [_oldPlayer] and kept alive so Android
  /// does NOT release audio focus between turns.  It will be disposed when
  /// the next turn's first audio chunk arrives (in [_flushPartial]).
  void _resetForNextTurn() {
    _playbackStarted = false;
    _playbackSub?.cancel();
    _playbackSub = null;

    // Stash the current player as "old" — _flushPartial will dispose it
    // only when the NEW turn's player is ready to take over.
    _disposeOldPlayer(); // dispose any previously stashed player first
    _oldPlayer = _player;
    _player = null;
    _turnPlaylist = null;

    // Delete temp files in background.
    final files = List<String>.from(_tempFiles);
    _tempFiles.clear();
    unawaited(Future(() async {
      for (final path in files) {
        try {
          await File(path).delete();
        } catch (e) {
          _log.fine('temp file delete: $e');
        }
      }
    }));

    _log.info('turn reset complete — calling onPlaybackDone');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately (barge-in from user).
  Future<void> stopPlayback() async {
    _flushTimer?.cancel();
    _pcmBuffer.clear();
    _playbackSub?.cancel();
    _playbackSub = null;
    _playbackStarted = false;

    final files = List<String>.from(_tempFiles);
    _turnPlaylist = null;
    _tempFiles.clear();

    // Stop + dispose player immediately for instant silence.
    // On barge-in we don't need to hold audio focus — the recorder is
    // about to reclaim it via ensureRecording() in the provider.
    final player = _player;
    _player = null;
    _disposeOldPlayer(); // also dispose any stashed old player
    if (player != null) {
      try {
        await player.stop();
      } catch (e) {
        _log.fine('stopPlayback stop: $e');
      }
      unawaited(Future(() async {
        try {
          await player.dispose();
        } catch (_) {}
      }));
    }
    // Delete temp files in background.
    unawaited(Future(() async {
      for (final path in files) {
        try {
          await File(path).delete();
        } catch (e) {
          _log.fine('stopPlayback file delete: $e');
        }
      }
    }));
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

    for (final p in [_player, _oldPlayer]) {
      if (p != null) {
        try {
          p.stop();
        } catch (_) {}
        try {
          p.dispose();
        } catch (_) {}
      }
    }
    _player = null;
    _oldPlayer = null;

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
