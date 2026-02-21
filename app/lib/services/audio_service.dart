import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

/// Handles microphone capture (outbound) and AI response playback (inbound).
///
/// Lifecycle:
///   - Created eagerly in connectOnly() so AI audio plays even before mic starts.
///   - [start] / [stop] control the microphone only.
///   - [queueChunk] / [flushAndPlay] / [stopPlayback] control the speaker.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _recordSub;
  final _audioController = StreamController<String>.broadcast();
  bool _isCapturing = false;

  /// PCM chunks buffered from the server between audio packets and turn_complete.
  final List<Uint8List> _pcmBuffer = [];

  // ── Recording ──────────────────────────────────────────────────────────

  Stream<String> get audioStream => _audioController.stream;
  bool get isCapturing => _isCapturing;

  Future<void> start() async {
    if (_isCapturing) return;
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

  // ── Playback ───────────────────────────────────────────────────────────

  /// Buffer one incoming PCM chunk from the AI.
  void queueChunk(String base64Audio) {
    try {
      _pcmBuffer.add(base64Decode(base64Audio));
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] Bad chunk: $e');
    }
  }

  /// Called on turn_complete — combine buffered PCM, wrap in WAV, play.
  /// Gemini Live API outputs PCM at 24 kHz, 16-bit, mono.
  Future<void> flushAndPlay() async {
    if (_pcmBuffer.isEmpty) return;
    final totalLen = _pcmBuffer.fold<int>(0, (s, c) => s + c.length);
    final pcm = Uint8List(totalLen);
    var offset = 0;
    for (final chunk in _pcmBuffer) {
      pcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _pcmBuffer.clear();
    if (totalLen == 0) return;
    final wav =
        _buildWav(pcm, sampleRate: 24000, channels: 1, bitsPerSample: 16);
    try {
      await _player.stop();
      await _player.setAudioSource(_WavBytesSource(wav));
      await _player.play();
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] Playback error: $e');
    }
  }

  /// Stop playback and discard buffered chunks (e.g. on interrupted).
  Future<void> stopPlayback() async {
    _pcmBuffer.clear();
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
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

/// Minimal StreamAudioSource that serves in-memory WAV bytes to just_audio.
class _WavBytesSource extends StreamAudioSource {
  _WavBytesSource(this._bytes);
  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
