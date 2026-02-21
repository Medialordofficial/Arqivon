import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../models/ws_message.dart';

/// Connection states exposed to providers.
enum WsConnectionState { disconnected, connecting, connected, reconnecting }

/// Production-grade WebSocket service with heartbeat & exponential backoff.
class WebSocketService {
  WebSocketService({required this.userId});

  final String userId;

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
        _state == WsConnectionState.connecting) return;

    _intentionalClose = false;
    _setState(WsConnectionState.connecting);

    try {
      final uri = Uri.parse(AppConstants.wsUrl(userId));
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _setState(WsConnectionState.connected);
      _reconnectAttempt = 0;

      _startHeartbeat();
      _listenToMessages();
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  // ── Send ─────────────────────────────────────────────────────────────

  void send(WsInbound message) {
    if (_state != WsConnectionState.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
    } catch (e) {
      debugPrint('[WS] Send error: $e');
    }
  }

  void sendAudio(String base64Audio) {
    send(const WsInbound(type: 'audio').copyWith(data: base64Audio));
  }

  void sendVideo(String base64Frame) {
    send(WsInbound(type: 'video', data: base64Frame));
  }

  void sendText(String text) {
    send(WsInbound(type: 'text', text: text));
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
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          final msg = WsOutbound.fromJson(json);
          _messageController.add(msg);
        } catch (e) {
          debugPrint('[WS] Parse error: $e');
        }
      },
      onDone: () {
        if (!_intentionalClose) _scheduleReconnect();
      },
      onError: (e) {
        debugPrint('[WS] Stream error: $e');
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
    debugPrint(
        '[WS] Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempt)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => connect());
  }

  Duration _backoff(int attempt) {
    final ms = AppConstants.baseReconnectDelay.inMilliseconds *
        pow(2, attempt).toInt();
    final capped = min(ms, 30000);
    final jitter = Random().nextInt((capped * 0.1).toInt() + 1);
    return Duration(milliseconds: capped + jitter);
  }

  void _setState(WsConnectionState s) {
    _state = s;
    _stateController.add(s);
  }
}

/// Tiny extension so WsInbound can be "copied" with data.
extension _WsInboundCopy on WsInbound {
  WsInbound copyWith({String? type, String? data, String? text}) => WsInbound(
        type: type ?? this.type,
        data: data ?? this.data,
        text: text ?? this.text,
      );
}
