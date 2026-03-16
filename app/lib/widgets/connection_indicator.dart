import 'package:flutter/material.dart';

import '../services/websocket_service.dart';

/// Small dot indicator for WebSocket connection state.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.state});

  final WsConnectionState state;

  Color get _color {
    switch (state) {
      case WsConnectionState.connected:
        return const Color(0xFF10B981);
      case WsConnectionState.connecting:
      case WsConnectionState.reconnecting:
        return const Color(0xFFF59E0B);
      case WsConnectionState.disconnected:
        return const Color(0xFFEF4444);
    }
  }

  String get _label {
    switch (state) {
      case WsConnectionState.connected:
        return 'Connected';
      case WsConnectionState.connecting:
        return 'Connecting…';
      case WsConnectionState.reconnecting:
        return 'Reconnecting…';
      case WsConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Connection status: $_label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}
