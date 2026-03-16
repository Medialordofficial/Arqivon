import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';

/// Centralised logging for Arqivon.
///
/// Usage:
///   final _log = AppLogger('AudioService');
///   _log.info('recorder started');
///   _log.warning('stream ended');
///   _log.severe('fatal error', error, stackTrace);
///
/// In debug builds the output goes to the console via `debugPrint`.
/// In release builds log records are suppressed (Crashlytics handles errors).
class AppLogger {
  final Logger _logger;

  AppLogger(String name) : _logger = Logger(name);

  /// Initialise the root logger. Must be called once at startup.
  static void init() {
    Logger.root.level = kReleaseMode ? Level.WARNING : Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (kDebugMode) {
        debugPrint(
          '[${record.loggerName}] ${record.level.name}: ${record.message}'
          '${record.error != null ? ' | ${record.error}' : ''}',
        );
      }
    });
  }

  void fine(String message) => _logger.fine(message);
  void info(String message) => _logger.info(message);
  void warning(String message, [Object? error]) =>
      _logger.warning(message, error);
  void severe(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);
}
