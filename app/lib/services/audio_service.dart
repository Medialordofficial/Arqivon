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
  Timer? _playbackTimeout;
  // Two-phase flush: generous first-audio buffer, then ~1 s sustained
  // chunks so the player never outruns the source.
  static const int _firstFlushMs = 800; // buffer 800 ms before starting
  static const int _sustainedFlushMs = 1000; // subsequent: ~1 s chunks
  static const int _minFlushBytes = 960; // ~20 ms @ 24 kHz 16-bit mono
  static const int _hardCapBytes = 240000; // ~5 s @ 24 kHz 16-bit mono
  int _chunkIndex = 0;
  final List<String> _tempFiles = [];
  bool _flushing = false;
  bool _reflushNeeded = false;

  /// Track the playlist length when the player last completed,
  /// so recovery seeks to the first UNPLAYED track rather than the last.
  int _completedAtLength = 0;

  /// Monotonically increasing turn counter.  Incremented by [stopPlayback]
  /// and checked by [_doFlush] so an in-flight flush from a previous turn
  /// bails out instead of creating a stale player.
  int _turnId = 0;

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
    // do NOT reset it when subsequent chunks arrive.
    // Phase 1 (first audio): flush in 150 ms for fast time-to-voice.
    // Phase 2 (sustained):   flush every 2.5 s so each WAV is long enough
    //                        that the player never outruns the source.
    if (_flushTimer == null || !_flushTimer!.isActive) {
      final ms = _playbackStarted ? _sustainedFlushMs : _firstFlushMs;
      _flushTimer = Timer(
        Duration(milliseconds: ms),
        _flushPartial,
      );
    }
    // Hard cap: ~5 s of audio to prevent unbounded buffering.
    if (_pcmBuffer.length >= _hardCapBytes) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _flushPartial();
    }
  }

  /// Write buffered PCM to a temp WAV file, add it to the turn's playlist,
  /// and start (or resume) the player.
  ///
  /// Serialized with [_flushing] to prevent async re-entrancy which caused
  /// player state corruption and audio dropout on long AI responses.
  Future<void> _flushPartial({bool force = false}) async {
    if (_flushing) {
      // Don't drop the flush — flag for retry after current flush completes.
      _reflushNeeded = true;
      _log.fine('_flushPartial re-entrant — flagged for retry');
      return;
    }
    _flushing = true;
    try {
      await _doFlush(force: force);
    } finally {
      _flushing = false;
      // If someone tried to flush while we were busy, do it now.
      if (_reflushNeeded && _pcmBuffer.isNotEmpty) {
        _reflushNeeded = false;
        scheduleMicrotask(() => _flushPartial(force: true));
      }
    }
  }

  Future<void> _doFlush({bool force = false}) async {
    if (!force && _pcmBuffer.length < _minFlushBytes) return;
    if (_pcmBuffer.isEmpty) return;

    // Snapshot the current turn so we can detect if stopPlayback fired
    // during one of our awaits (invalidating player/playlist).
    final flushTurn = _turnId;

    final pcm = Uint8List.fromList(_pcmBuffer);
    _pcmBuffer.clear();

    final dir = await getTemporaryDirectory();
    // Bail if the turn changed while we were awaiting.
    if (_turnId != flushTurn) return;

    final filePath = '${dir.path}/ai_chunk_${_chunkIndex++}.wav';
    final wav = _buildWav(pcm, sampleRate: 24000);
    await File(filePath).writeAsBytes(wav, flush: true);
    // Bail if the turn changed while writing.
    if (_turnId != flushTurn) {
      // Clean up the orphaned file.
      unawaited(File(filePath).delete().catchError((_) => File(filePath)));
      return;
    }
    _tempFiles.add(filePath);

    // First chunk of a new turn → create a fresh player & playlist.
    if (_turnPlaylist == null) {
      _disposeOldPlayer();
      await _ensureAudioSession();
      _player = AudioPlayer();
      _turnPlaylist = ConcatenatingAudioSource(
        useLazyPreparation: false,
        children: [],
      );
      _playbackStarted = false;
      _completedAtLength = 0;

      // Track when the player finishes all currently-queued tracks.
      _setupCompletionListener();
    }

    // Bail if the turn changed during player setup.
    if (_turnId != flushTurn) return;

    await _turnPlaylist!.add(AudioSource.uri(Uri.file(filePath)));

    if (_player == null) {
      _log.warning('_player is null after playlist setup — skipping');
      return;
    }

    // Final bail-out check after async playlist add.
    if (_turnId != flushTurn) return;

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
    } else {
      // Detect and recover from ALL stalled player states.
      final ps = _player!.processingState;
      if (ps == ProcessingState.completed) {
        // Simple seek + play: fast (<10 ms), doesn't block _flushing.
        try {
          final idx = _completedAtLength < _turnPlaylist!.length
              ? _completedAtLength
              : _turnPlaylist!.length - 1;
          await _player!.seek(Duration.zero, index: idx);
          _player!.play();
          _log.info('resumed at index $idx / ${_turnPlaylist!.length}');
        } catch (e) {
          _log.severe('seek-resume failed — recreating player', e);
          await _recreatePlayerForTurn();
        }
      } else if (ps == ProcessingState.idle) {
        _log.warning('player in idle state — re-attaching audio source');
        try {
          await _player!.setAudioSource(_turnPlaylist!);
          final idx = _turnPlaylist!.length - 1;
          await _player!.seek(Duration.zero, index: idx);
          _player!.play();
        } catch (e) {
          _log.severe('idle recovery failed — recreating player', e);
          await _recreatePlayerForTurn();
        }
      } else if (ps == ProcessingState.ready && !_player!.playing) {
        _log.warning('player ready but not playing — kicking');
        _player!.play();
      }
    }
  }

  /// Last-resort recovery: create a brand-new player from the turn's
  /// temp files.  Seeks to the latest chunk to resume close to where
  /// the old player stalled.
  Future<void> _recreatePlayerForTurn() async {
    _log.info('recreating player for current turn');
    final oldPlayer = _player;
    try {
      _player = AudioPlayer();
      _turnPlaylist = ConcatenatingAudioSource(
        useLazyPreparation: false,
        children: _tempFiles
            .map<AudioSource>((f) => AudioSource.uri(Uri.file(f)))
            .toList(),
      );
      await _player!.setAudioSource(_turnPlaylist!);
      if (_turnPlaylist!.length > 0) {
        final idx = _turnPlaylist!.length - 1;
        await _player!.seek(Duration.zero, index: idx);
      }
      _player!.play();
      _playbackStarted = true;
      _log.info('player recreated with ${_turnPlaylist!.length} items');
    } catch (e) {
      _log.severe('player recreation failed', e);
      _playbackStarted = false;
    }
    if (oldPlayer != null) {
      unawaited(Future(() async {
        try {
          await oldPlayer.stop();
        } catch (_) {}
        try {
          await oldPlayer.dispose();
        } catch (_) {}
      }));
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

  /// Set up a [playerStateStream] listener that:
  /// 1. Records which items have been played ([_completedAtLength]).
  /// 2. Proactively flushes buffered PCM so audio resumes without waiting
  ///    for the next chunk from Gemini.
  void _setupCompletionListener() {
    _playbackSub?.cancel();
    _playbackSub = _player!.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _completedAtLength = _turnPlaylist?.length ?? 0;
        _log.info('player completed at index $_completedAtLength, '
            'pcmBuf=${_pcmBuffer.length}, tempFiles=${_tempFiles.length}');
        // Don't call _flushPartial here — the re-flush loop in
        // _flushPartial's finally block will handle it.  Just kick
        // the sustained timer to fire sooner if there's buffered PCM.
        if (_pcmBuffer.isNotEmpty &&
            (_flushTimer == null || !_flushTimer!.isActive)) {
          _flushTimer = Timer(
            const Duration(milliseconds: 30),
            () => _flushPartial(force: true),
          );
        }
      }
    });
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
      // Force-flush the final tail so short replies (common after
      // interruption) are never dropped.
      await _flushPartial(force: true);
    }

    // Listen for playback completion, then reset for the next turn.
    if (_player != null && _turnPlaylist != null) {
      _playbackSub?.cancel();

      // If already done or in a broken idle state, reset immediately.
      final ps = _player!.processingState;
      if (ps == ProcessingState.completed || ps == ProcessingState.idle) {
        _resetForNextTurn();
        return;
      }

      _playbackSub = _player!.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _playbackSub?.cancel();
          _playbackSub = null;
          _playbackTimeout?.cancel();
          _resetForNextTurn();
        }
      });

      // Failsafe: if playback never completes (player stuck), force-reset
      // so subsequent turns aren't permanently broken.  60s is generous enough
      // for even very long AI responses.
      _playbackTimeout?.cancel();
      _playbackTimeout = Timer(const Duration(seconds: 60), () {
        _log.warning('playback timeout (60s) — force-resetting turn');
        _playbackSub?.cancel();
        _playbackSub = null;
        _resetForNextTurn();
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
    _playbackTimeout?.cancel();
    _playbackStarted = false;
    _completedAtLength = 0;
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
    _playbackTimeout?.cancel();
    _flushTimer?.cancel();
    _pcmBuffer.clear();
    _playbackSub?.cancel();
    _playbackSub = null;
    _playbackStarted = false;
    _completedAtLength = 0;
    // Increment turn counter so any in-flight _doFlush bails out.
    _turnId++;

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
    _playbackTimeout?.cancel();
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
