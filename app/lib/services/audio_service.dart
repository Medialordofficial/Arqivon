import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Manages microphone capture and exposes a stream of base64-encoded PCM chunks.
class AudioCaptureService {
  AudioCaptureService();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final _audioController = StreamController<String>.broadcast();
  bool _isCapturing = false;

  /// Stream of base64-encoded PCM audio chunks.
  Stream<String> get audioStream => _audioController.stream;
  bool get isCapturing => _isCapturing;

  /// Start capturing audio from the microphone.
  Future<void> start() async {
    if (_isCapturing) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('[Audio] Microphone permission denied');
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

    _subscription = stream.listen(
      (chunk) {
        if (chunk.isNotEmpty) {
          _audioController.add(base64Encode(chunk));
        }
      },
      onError: (e) => debugPrint('[Audio] Capture error: $e'),
    );

    _isCapturing = true;
    debugPrint('[Audio] Capture started');
  }

  /// Stop capturing.
  Future<void> stop() async {
    if (!_isCapturing) return;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    _isCapturing = false;
    debugPrint('[Audio] Capture stopped');
  }

  /// Play raw PCM audio bytes received from the server.
  /// In production, you'd use just_audio or a platform channel for real-time
  /// PCM playback.  This is a placeholder for the playback pipeline.
  void enqueuePlayback(String base64Audio) {
    // TODO: implement real-time PCM playback via just_audio or native plugin
    // final bytes = base64Decode(base64Audio);
  }

  void dispose() {
    stop();
    _audioController.close();
  }
}
