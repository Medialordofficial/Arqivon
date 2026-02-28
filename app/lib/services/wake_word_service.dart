import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../config/logger.dart';

/// Lightweight wake-word detector that uses on-device speech recognition
/// to listen for "Hey Arqivon" (or just "Arqivon").
///
/// Usage:
///   final ww = WakeWordService(onDetected: () => startSession());
///   await ww.start();   // begin passive listening
///   ww.stop();           // suspend listening
///   ww.dispose();        // permanent teardown
class WakeWordService {
  WakeWordService({required this.onDetected});

  static final _log = AppLogger('WakeWord');

  /// Called once when the wake word is recognised.
  /// The service automatically pauses after triggering so it doesn't
  /// fire repeatedly.
  final VoidCallback onDetected;

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _running = false;
  bool _disposed = false;
  Timer? _restartTimer;

  /// The keywords we look for (all lowercase).
  static const _triggers = [
    'arqivon',
    'archive on',
    'archivon',
    'arc evon',
    'arki von',
    'arq von',
    'hey arqivon',
    'hey archive on',
    'hey archivon',
  ];

  /// Initialise the speech engine (only once).
  Future<bool> _ensureInit() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: false,
      );
      if (!_initialized) {
        _log.warning('speech_to_text init returned false');
      }
    } catch (e) {
      _log.severe('speech_to_text init failed', e);
      _initialized = false;
    }
    return _initialized;
  }

  /// Start passively listening for the wake word.
  Future<void> start() async {
    if (_disposed || _running) return;
    if (!await _ensureInit()) return;

    _running = true;
    _listen();
  }

  void _listen() {
    if (!_running || _disposed) return;
    if (_stt.isListening) return;

    _stt.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      listenMode: ListenMode.dictation,
      cancelOnError: false,
    );
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.toLowerCase();
    if (words.isEmpty) return;

    _log.fine('heard: "$words"');

    for (final trigger in _triggers) {
      if (words.contains(trigger)) {
        _log.info('🎤 Wake word detected: "$words"');
        // Pause listening so the live recorder can take over the mic.
        stop();
        onDetected();
        return;
      }
    }
  }

  void _onStatus(String status) {
    _log.fine('STT status: $status');
    // When the speech engine goes idle (notListening/done), restart after
    // a short delay to keep passive listening alive.
    if (status == 'notListening' || status == 'done') {
      if (_running && !_disposed) {
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(milliseconds: 500), () {
          if (_running && !_disposed) _listen();
        });
      }
    }
  }

  void _onError(dynamic error) {
    _log.fine('STT error: $error');
    // Auto-restart after transient errors.
    if (_running && !_disposed) {
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(seconds: 2), () {
        if (_running && !_disposed) _listen();
      });
    }
  }

  /// Stop passive listening (e.g. when audio recording takes over).
  void stop() {
    _running = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    if (_stt.isListening) {
      _stt.stop();
    }
  }

  /// Permanent teardown.
  void dispose() {
    _disposed = true;
    stop();
    _stt.cancel();
  }
}
