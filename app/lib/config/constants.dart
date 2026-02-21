/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // Backend — set to your Mac's LAN IP when running locally
  // Change this if your IP changes or you deploy to a server.
  static const String wsScheme = 'ws';
  static const String wsHost = '192.168.2.104';
  static const int wsPort = 8080;
  static String wsUrl(String userId) =>
      '$wsScheme://$wsHost:$wsPort/ws/$userId';
  static String httpBase = 'http://$wsHost:$wsPort';

  // Audio
  static const int audioSampleRate = 16000;
  static const int audioChannels = 1;
  static const int audioBitDepth = 16;

  // Video
  static const int videoFps = 2; // 2 frames per second
  static const Duration frameCaptureInterval =
      Duration(milliseconds: 1000 ~/ videoFps);

  // Heartbeat
  static const Duration heartbeatInterval = Duration(seconds: 12);

  // Reconnect
  static const int maxReconnectAttempts = 5;
  static const Duration baseReconnectDelay = Duration(milliseconds: 500);
}
