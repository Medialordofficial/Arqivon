/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // ── Backend (Cloud Run production) ───────────────────────────────
  static const String _host =
      'arqivon-backend-653546103163.us-central1.run.app';
  static const String wsScheme = 'wss';
  static const String wsHost = _host;
  static const int wsPort = 443;
  static String wsUrl(String userId, {String? token}) {
    final base = '$wsScheme://$_host/ws/$userId';
    if (token != null) return '$base?token=$token';
    return base;
  }

  static String httpBase = 'https://$_host';

  // Audio
  static const int audioSampleRate = 16000;
  static const int audioChannels = 1;
  static const int audioBitDepth = 16;

  // Video
  static const int videoFps = 3; // 3 frames per second
  static const Duration frameCaptureInterval =
      Duration(milliseconds: 1000 ~/ videoFps);

  // Heartbeat
  static const Duration heartbeatInterval = Duration(seconds: 12);

  // Reconnect
  static const int maxReconnectAttempts = 5;
  static const Duration baseReconnectDelay = Duration(milliseconds: 500);
}
