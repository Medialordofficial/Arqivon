import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../config/logger.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// **Playback architecture (v8 — StreamAudioSource, continuous):**
///
/// 1. PCM chunks arrive via [queueChunk].
/// 2. They are appended directly into a single in-memory WAV stream source.
/// 3. A **single [AudioPlayer]** plays that source continuously.
/// 4. Barge-in closes the current stream and stops the player immediately.
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

  // ── Playback — StreamAudioSource (continuous) ─────────────────────
  AudioPlayer? _player;
  Timer? _playbackTimeout;
  Timer? _flushTimer;

  final List<int> _pcmBuffer = [];
  LivePcmStreamSource? _liveSource;
  StreamSubscription<ProcessingState>? _processingStateSub;
  int _turnId = 0;
  bool _flushing = false;
  bool _turnComplete = false;
  Timer? _completionDebounce;
  Timer? _staleWatchdog;
  Timer? _bufferStuckTimer;

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
    _player = AudioPlayer();
    _player!.setVolume(1.0); // explicit max volume for speaker output
    _processingStateSub =
        _player!.processingStateStream.listen(_onProcessingState);
    _log.info('persistent player created');
  }

  /// Check if the turn is truly finished: all audio flushed, enqueued, and played.
  bool get _turnFullyDone => _turnComplete;

  void _onProcessingState(ProcessingState ps) {
    // Cancel buffering-stuck timer on ANY state change.
    _bufferStuckTimer?.cancel();
    _bufferStuckTimer = null;

    if (ps == ProcessingState.completed) {
      if (_turnComplete) {
        // Cancel any previous debounce and start a fresh one.
        _completionDebounce?.cancel();
        _completionDebounce = Timer(const Duration(milliseconds: 500), () {
          _completionDebounce = null;
          if (_turnFullyDone &&
              _player?.processingState == ProcessingState.completed) {
            _log.info('player completed all tracks + turn complete → done');
            _playbackTimeout?.cancel();
            _resetForNextTurn();
          }
        });
      } else {
        // Player finished all queued tracks but turn_complete hasn't arrived
        // yet. Start a stale watchdog: if no new chunks arrive within 5s,
        // auto-finalize to prevent the client from being stuck forever.
        _startStaleWatchdog();
      }
    } else if (ps == ProcessingState.buffering) {
      // If the player is stuck buffering (e.g. corrupt WAV, disk error)
      // for more than 5s, force-finalize to prevent hanging forever.
      _bufferStuckTimer = Timer(const Duration(seconds: 5), () {
        _bufferStuckTimer = null;
        if (_player?.processingState == ProcessingState.buffering) {
          _log.warning(
              'player stuck in BUFFERING for 5s — force-finalizing turn');
          _turnComplete = true;
          _playbackTimeout?.cancel();
          try {
            _player?.stop();
          } catch (_) {}
          _resetForNextTurn();
        }
      });
    }
  }

  /// Start a watchdog that auto-finalizes the turn if no new audio
  /// chunks arrive after the player has finished all queued tracks.
  /// This handles the case where the server never sends turn_complete
  /// (e.g. due to a mid-turn exception or reconnect).
  void _startStaleWatchdog() {
    _staleWatchdog?.cancel();
    _staleWatchdog = Timer(const Duration(seconds: 5), () {
      _staleWatchdog = null;
      if (!_turnComplete &&
          _player?.processingState == ProcessingState.completed &&
          _pcmBuffer.isEmpty &&
          !_flushing) {
        _log.warning('stale-chunk watchdog fired — auto-finalizing turn');
        _turnComplete = true;
        _playbackTimeout?.cancel();
        _resetForNextTurn();
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
  //  PLAYBACK — StreamAudioSource, continuous (v8)
  // ══════════════════════════════════════════════════════════════════

  /// Queue a base64-encoded PCM chunk from the AI into the active stream.
  void queueChunk(String base64Audio) {
    final bytes = base64Decode(base64Audio);

    // New audio arrived — cancel stale-chunk watchdog if active.
    _staleWatchdog?.cancel();
    _staleWatchdog = null;

    if (_liveSource == null) {
      _turnComplete = false;
      _liveSource = LivePcmStreamSource();
      unawaited(_startStreamPlayback(_liveSource!));
    }

    _liveSource!.addPcm(bytes);
  }

  Future<void> _startStreamPlayback(LivePcmStreamSource source) async {
    await _ensureAudioSession();
    _ensurePlayer();

    _completionDebounce?.cancel();
    _completionDebounce = null;
    _staleWatchdog?.cancel();
    _staleWatchdog = null;

    try {
      await _player!.setAudioSource(source, initialPosition: Duration.zero);
      if (!identical(_liveSource, source)) return;
      _log.info('▶ START continuous playback stream');
      await _player!.play();
    } catch (e) {
      _log.severe('setAudioSource(stream) failed: $e');
    }
  }

  /// Called by the provider on `turn_complete`.
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _turnComplete = true;
    _log.info('flushAndPlay — streamOpen=${_liveSource != null}');

    final source = _liveSource;
    source?.closeTurn();

    // If nothing was played this turn at all.
    if (source == null) {
      _log.info('no audio this turn');
      onPlaybackDone?.call();
      return;
    }

    // If player already finished all tracks, schedule a debounced check.
    // Uses _turnFullyDone which also checks _pendingWavCount to prevent
    // premature finalization while WAVs are still being written/enqueued.
    if (_player?.processingState == ProcessingState.completed) {
      if (_turnFullyDone) {
        _completionDebounce?.cancel();
        _completionDebounce = Timer(const Duration(milliseconds: 500), () {
          _completionDebounce = null;
          if (_turnFullyDone &&
              _player?.processingState == ProcessingState.completed) {
            _log.info(
                'player already completed + turn done → reset (debounced)');
            _playbackTimeout?.cancel();
            _resetForNextTurn();
          }
        });
      }
    }

    // Safety timeout in case playback hangs.
    // 60s is generous for multi-sentence responses. If something is
    // stuck, we recover instead of waiting forever.
    _playbackTimeout?.cancel();
    _playbackTimeout = Timer(const Duration(seconds: 60), () {
      _log.warning('playback TIMEOUT — force-resetting');
      _turnId++;
      _player?.stop();
      _resetForNextTurn();
    });
  }

  void _resetForNextTurn() {
    _playbackTimeout?.cancel();
    _flushTimer?.cancel();
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
    _bufferStuckTimer?.cancel();
    _bufferStuckTimer = null;
    _turnComplete = false;
    _pcmBuffer.clear();
    _liveSource = null;

    _log.info('turn reset — firing onPlaybackDone');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately (barge-in).
  ///
  /// **Critical ordering:** All synchronous state is reset FIRST so that
  /// any concurrent queueChunk/flush calls see the new turn immediately.
  /// The async player.stop() and playlist.clear() happen afterwards and
  /// are best-effort — even if they take a few ms, the turnId increment
  /// guarantees any in-flight WAV writes are discarded.
  Future<void> stopPlayback() async {
    // ── Step 1: synchronous state reset (runs on the event loop tick) ──
    _playbackTimeout?.cancel();
    _flushTimer?.cancel();
    _completionDebounce?.cancel();
    _completionDebounce = null;
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
    _bufferStuckTimer?.cancel();
    _bufferStuckTimer = null;
    _pcmBuffer.clear();
    _turnComplete = false;
    _turnId++;

    final oldSource = _liveSource;
    _liveSource = null;
    oldSource?.closeTurn();

    _log.info('playback stopped (barge-in, turnId=$_turnId)');

    // ── Step 2: async cleanup (with timeout to prevent hang) ──
    try {
      await _player?.stop().timeout(const Duration(milliseconds: 500));
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
    _flushTimer?.cancel();
    _completionDebounce?.cancel();
    _staleWatchdog?.cancel();
    _bufferStuckTimer?.cancel();
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
    _liveSource?.closeTurn();
    _liveSource = null;
  }
}

class LivePcmStreamSource extends StreamAudioSource {
  final Queue<Uint8List> _pendingChunks = ListQueue<Uint8List>();
  Completer<void>? _nextChunk;
  bool _closed = false;

  void addPcm(List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    _pendingChunks.add(Uint8List.fromList(bytes));
    _nextChunk?.complete();
    _nextChunk = null;
  }

  void closeTurn() {
    _closed = true;
    _nextChunk?.complete();
    _nextChunk = null;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: null,
      contentLength: null,
      offset: 0,
      contentType: 'audio/wav',
      stream: _streamBytes(),
    );
  }

  Stream<List<int>> _streamBytes() async* {
    yield _wavHeader();
    while (true) {
      while (_pendingChunks.isNotEmpty) {
        yield _pendingChunks.removeFirst();
      }
      if (_closed) break;
      _nextChunk ??= Completer<void>();
      await _nextChunk!.future;
    }
  }

  Uint8List _wavHeader({int sampleRate = 24000}) {
    final byteRate = sampleRate * 2;
    final header = ByteData(44);
    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    header.setUint32(4, 0x7fffffff, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // 1 channel
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    writeString(36, 'data');
    header.setUint32(40, 0x7fffffff, Endian.little);
    return header.buffer.asUint8List();
  }
}

/// Alias so the provider can reference the service by either name.
typedef AudioCaptureService = AudioService;
