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
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _intentionalClose = false;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _messageController = StreamController<WsOutbound>.broadcast();

  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<WsOutbound> get messageStream => _messageController.stream;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  // ── Connect ──────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      return;
    }

    _intentionalClose = false;
    _setState(WsConnectionState.connecting);

    try {
      // Refresh the auth token before every connection attempt so reconnects
      // after >1 hour don't fail with a stale/expired token.
      if (tokenRefresher != null) {
        final freshToken = await tokenRefresher!();
        if (freshToken != null) authToken = freshToken;
      }

      final uri = Uri.parse(AppConstants.wsUrl(userId, token: authToken));
      _channel = WebSocketChannel.connect(uri);
      // Timeout the handshake so we don't hang for 30-60s on a
      // cold-starting backend or unreachable server.
      await _channel!.ready.timeout(AppConstants.connectTimeout);

      _setState(WsConnectionState.connected);
      _reconnectAttempt = 0;

      _startHeartbeat();
      _listenToMessages();
    } catch (e) {
      _log.severe('Connection failed', e);
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
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _messageController.close();
  }

  // ── Internal ─────────────────────────────────────────────────────────

  void _listenToMessages() {
    _channel?.stream.listen(
      (raw) {
        try {
          if (raw is! String) {
            _log.warning('Ignoring non-text WebSocket frame');
            return;
          }
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final msg = WsOutbound.fromJson(json);
          _messageController.add(msg);
        } catch (e) {
          _log.severe('Parse error', e);
        }
      },
      onDone: () {
        if (!_intentionalClose) _scheduleReconnect();
      },
      onError: (e) {
        _log.severe('Stream error', e);
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

  void _scheduleReconnect() {
    if (_intentionalClose) return;
    if (_reconnectAttempt >= AppConstants.maxReconnectAttempts) {
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
    final ms = AppConstants.baseReconnectDelay.inMilliseconds *
        pow(2, attempt).toInt();
    // Cap at 8s instead of 30s — faster recovery from backend cold starts
    // and network blips.  With 50 max attempts the total across all retries
    // is ~6-7 minutes, which is generous.
    final capped = min(ms, 8000);
    final jitter = Random().nextInt((capped * 0.1).toInt() + 1);
    return Duration(milliseconds: capped + jitter);
  }

  void _setState(WsConnectionState s) {
    _state = s;
    _stateController.add(s);
  }
}
