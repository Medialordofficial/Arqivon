import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../config/logger.dart';
import '../models/ws_message.dart';

/// Connection states exposed to providers.
enum WsConnectionState { disconnected, connecting, connected, reconnecting }

/// Production-grade WebSocket service with heartbeat & exponential backoff.
class WebSocketService {
  WebSocketService({
    required this.userId,
    this.authToken,
    this.tokenRefresher,
  });

  static final _log = AppLogger('WS');

  final String userId;

  /// Firebase ID token for backend authentication.
  String? authToken;

  /// Async callback to refresh the Firebase ID token before reconnection.
  final Future<String?> Function()? tokenRefresher;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _intentionalClose = false;
  bool _connectInProgress = false;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _messageController = StreamController<WsOutbound>.broadcast();

  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<WsOutbound> get messageStream => _messageController.stream;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  // ── Connect ──────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_state == WsConnectionState.connected || _connectInProgress) {
      return;
    }

    _intentionalClose = false;
    _connectInProgress = true;

    // Only show 'connecting' on the FIRST attempt.
    // During retries, keep 'reconnecting' so the UI doesn't flicker
    // between "Connecting…" and "Reconnecting…" on every attempt.
    if (_reconnectAttempt == 0) {
      _setState(WsConnectionState.connecting);
    }

    try {
      if (tokenRefresher != null) {
        try {
          final freshToken = await tokenRefresher!();
          if (freshToken != null) authToken = freshToken;
        } catch (e) {
          _log.warning('Token refresh failed — using cached token: $e');
        }
      }

      final uri = Uri.parse(AppConstants.wsUrl(userId, token: authToken));
      _channelSub?.cancel();
      _channelSub = null;
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(AppConstants.connectTimeout);

      _connectInProgress = false;
      _setState(WsConnectionState.connected);
      _reconnectAttempt = 0;

      _startHeartbeat();
      _listenToMessages();
    } catch (e) {
      _log.severe('Connection failed (attempt $_reconnectAttempt)', e);
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = null;
      _connectInProgress = false;
      _scheduleReconnect();
    }
  }

  // ── Send ─────────────────────────────────────────────────────────────

  void send(WsInbound message) {
    if (_state != WsConnectionState.connected || _channel == null) return;
    try {
      final json = message.toJson();
      // Inject epoch-seconds timestamp for server-side latency measurement.
      json['timestamp'] = DateTime.now().millisecondsSinceEpoch / 1000.0;
      _channel!.sink.add(jsonEncode(json));
    } catch (e) {
      _log.severe('Send error', e);
    }
  }

  void sendPing() {
    send(const WsInbound(type: 'ping'));
  }

  // ── Disconnect ───────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    await _channel?.sink.close();
    _channel = null;
    _connectInProgress = false;
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _messageController.close();
  }

  // ── Internal ─────────────────────────────────────────────────────────

  int _rawFrameCount = 0;

  void _listenToMessages() {
    _channelSub?.cancel();
    _rawFrameCount = 0;
    _channelSub = _channel?.stream.listen(
      (raw) {
        _rawFrameCount++;
        try {
          if (raw is! String) {
            _log.warning('Ignoring non-text WebSocket frame');
            return;
          }
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final msg = WsOutbound.fromJson(json);
          // Only log non-audio, non-pong messages to avoid spam.
          if (msg.type != 'pong' && msg.type != 'audio') {
            _log.info('WS ← ${msg.type}');
          }
          _messageController.add(msg);
        } catch (e) {
          _log.severe('Parse error on frame #$_rawFrameCount', e);
        }
      },
      onDone: () {
        _log.info('WebSocket stream closed (after $_rawFrameCount frames)');
        if (!_intentionalClose) _scheduleReconnect();
      },
      onError: (e) {
        _log.severe('Stream error (after $_rawFrameCount frames)', e);
        if (!_intentionalClose) _scheduleReconnect();
      },
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      AppConstants.heartbeatInterval,
      (_) => sendPing(),
    );
  }

  /// Whether a reconnect cycle is actively running.
  bool get isReconnecting =>
      _state == WsConnectionState.reconnecting ||
      _state == WsConnectionState.connecting;

  void _scheduleReconnect() {
    if (_intentionalClose) return;
    if (_reconnectAttempt >= AppConstants.maxReconnectAttempts) {
      _log.warning('Max reconnect attempts reached — giving up');
      _setState(WsConnectionState.disconnected);
      return;
    }

    _setState(WsConnectionState.reconnecting);
    _reconnectAttempt++;
    final delay = _backoff(_reconnectAttempt);
    _log.info(
        'Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempt)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => connect());
  }

  Duration _backoff(int attempt) {
    // First 3 attempts: retry almost instantly (100ms) so the user
    // barely notices a brief network hiccup or WS reset.
    if (attempt <= 3) return Duration(milliseconds: 100 + Random().nextInt(50));
    // Attempts 4+: gentle exponential backoff capped at 5s.
    final ms = AppConstants.baseReconnectDelay.inMilliseconds *
        pow(2, attempt - 3).toInt();
    final capped = min(ms, 5000);
    final jitter = Random().nextInt((capped * 0.15).toInt() + 1);
    return Duration(milliseconds: capped + jitter);
  }

  void _setState(WsConnectionState s) {
    _state = s;
    _stateController.add(s);
  }
}
