import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// Audio playback is STREAMING — chunks are flushed into small WAV segments
/// every ~300 ms and queued via [ConcatenatingAudioSource] so the user hears
/// the AI reply immediately while it's still generating.
///
/// The mic stays active during AI playback to allow barge-in (Gemini's native
/// VAD detects the user speaking and sends an `interrupted` signal).
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _recordSub;
  final _audioController = StreamController<String>.broadcast();
  bool _isCapturing = false;
  bool _audioSessionConfigured = false;

  /// PCM chunks buffered between periodic flushes.
  final List<Uint8List> _pcmBuffer = [];

  /// Streaming playback queue — small WAV segments are appended as they arrive.
  final ConcatenatingAudioSource _playlist =
      ConcatenatingAudioSource(children: []);
  final List<String> _tempFiles = [];
  Timer? _flushTimer;
  bool _playbackStarted = false;
  StreamSubscription? _playbackSub;

  /// Callback fired when AI finishes speaking (playback done).
  VoidCallback? onPlaybackDone;

  /// Configure audio session for simultaneous play + record.
  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ));

      // Force speaker output for voiceCommunication on Android
      if (Platform.isAndroid) {
        await AndroidAudioManager().setSpeakerphoneOn(true);
      }

      _audioSessionConfigured = true;
      if (kDebugMode)
        debugPrint('[Audio] Audio session configured (play+record, speaker)');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] Audio session config failed: $e');
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────

  Stream<String> get audioStream => _audioController.stream;
  bool get isCapturing => _isCapturing;

  Future<void> start() async {
    if (_isCapturing) return;
    await _ensureAudioSession();
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (kDebugMode) debugPrint('[Audio] Microphone permission denied');
      return;
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _recordSub = stream.listen(
      (chunk) {
        if (chunk.isNotEmpty) _audioController.add(base64Encode(chunk));
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('[Audio] Capture error: $e');
      },
    );
    _isCapturing = true;
    if (kDebugMode) debugPrint('[Audio] Capture started');
  }

  Future<void> stop() async {
    if (!_isCapturing) return;
    await _recordSub?.cancel();
    _recordSub = null;
    await _recorder.stop();
    _isCapturing = false;
  }

  // ── Streaming Playback ─────────────────────────────────────────────────

  /// Buffer one incoming PCM chunk from the AI and start periodic flushing.
  void queueChunk(String base64Audio) {
    try {
      final decoded = base64Decode(base64Audio);
      _pcmBuffer.add(decoded);
      // Kick off a periodic flush timer so audio starts playing ~300 ms after
      // the first chunk arrives — no need to wait for turn_complete.
      _flushTimer ??= Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _flushPartial(),
      );
      if (kDebugMode && _pcmBuffer.length % 10 == 1) {
        debugPrint(
            '[Audio] Buffered ${_pcmBuffer.length} chunks (latest ${decoded.length} bytes)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] Bad chunk: $e');
    }
  }

  /// Flush any accumulated PCM into a mini WAV segment and append to playlist.
  Future<void> _flushPartial() async {
    if (_pcmBuffer.isEmpty) return;
    final totalLen = _pcmBuffer.fold<int>(0, (s, c) => s + c.length);
    if (totalLen == 0) return;

    final pcm = Uint8List(totalLen);
    var offset = 0;
    for (final chunk in _pcmBuffer) {
      pcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _pcmBuffer.clear();

    final wav =
        _buildWav(pcm, sampleRate: 24000, channels: 1, bitsPerSample: 16);

    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().microsecondsSinceEpoch;
      final filePath = '${dir.path}/arqivon_resp_chunk_$ts.wav';
      final file = File(filePath);
      await file.writeAsBytes(wav, flush: true);
      _tempFiles.add(filePath);

      await _playlist.add(AudioSource.uri(Uri.file(filePath)));
      if (kDebugMode)
        debugPrint(
            '[Audio] Queued segment: ${wav.length} bytes (${_playlist.length} in queue)');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] Failed to queue segment: $e');
      return;
    }

    if (!_playbackStarted) {
      _playbackStarted = true;
      await _ensureAudioSession();
      try {
        await _player.setAudioSource(_playlist);
        _player.play();
        if (kDebugMode) debugPrint('[Audio] Streaming playback started');
      } catch (e) {
        if (kDebugMode) debugPrint('[Audio] Playback start failed: $e');
        _playbackStarted = false;
      }
    } else if (_player.processingState == ProcessingState.completed) {
      // The player finished the previous chunks before this one arrived.
      // We need to seek to the new chunk and resume playing.
      try {
        await _player.seek(Duration.zero, index: _playlist.length - 1);
        _player.play();
        if (kDebugMode) debugPrint('[Audio] Resumed streaming playback');
      } catch (e) {
        if (kDebugMode) debugPrint('[Audio] Failed to resume playback: $e');
      }
    }
  }

  /// Called on turn_complete — flush remaining buffer.
  /// Playback continues from the queue; the provider handles post-playback
  /// state via [onPlaybackDone].
  Future<void> flushAndPlay() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    // Flush any remaining buffered PCM.
    await _flushPartial();

    if (!_playbackStarted) {
      if (kDebugMode) debugPrint('[Audio] flushAndPlay: nothing was queued');
      onPlaybackDone?.call();
      return;
    }

    if (kDebugMode)
      debugPrint(
          '[Audio] turn_complete — ${_playlist.length} segments in queue');

    // Listen for playlist completion, then reset.
    _playbackSub?.cancel();
    _playbackSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _playbackSub?.cancel();
        _playbackSub = null;
        _resetPlayback();
      }
    });
  }

  /// Clean up after playback finishes.
  void _resetPlayback() {
    _playbackStarted = false;
    _playlist.clear();
    for (final path in _tempFiles) {
      File(path).delete().ignore();
    }
    _tempFiles.clear();
    if (kDebugMode) debugPrint('[Audio] Playback complete — queue cleared');
    onPlaybackDone?.call();
  }

  /// Stop playback immediately and discard everything (e.g. barge-in).
  Future<void> stopPlayback() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _playbackSub?.cancel();
    _playbackSub = null;
    _pcmBuffer.clear();
    if (kDebugMode) debugPrint('[Audio] stopPlayback — interrupted');
    try {
      await _player.stop();
      await _playlist.clear();
      for (final path in _tempFiles) {
        File(path).delete().ignore();
      }
      _tempFiles.clear();
    } catch (_) {}
    _playbackStarted = false;
  }

  void dispose() {
    _flushTimer?.cancel();
    _playbackSub?.cancel();
    stop();
    _player.dispose();
    _audioController.close();
  }

  // ── WAV builder ────────────────────────────────────────────────────────

  static Uint8List _buildWav(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final bd = ByteData(44 + dataSize);
    var p = 0;
    void str(String s) {
      for (final c in s.codeUnits) {
        bd.setUint8(p++, c);
      }
    }

    void u32(int v) {
      bd.setUint32(p, v, Endian.little);
      p += 4;
    }

    void u16(int v) {
      bd.setUint16(p, v, Endian.little);
      p += 2;
    }

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1);
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    str('data');
    u32(dataSize);
    final result = bd.buffer.asUint8List();
    result.setRange(44, 44 + dataSize, pcm);
    return result;
  }
}

// Backwards-compat alias so existing references compile unchanged.
typedef AudioCaptureService = AudioService;
