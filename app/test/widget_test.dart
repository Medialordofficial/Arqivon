import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/config/constants.dart';
import 'package:arqivon/models/agent_mode.dart';
import 'package:arqivon/models/session_model.dart';
import 'package:arqivon/providers/live_session_provider.dart';
import 'package:arqivon/services/websocket_service.dart';

void main() {
  // ── AppConstants ────────────────────────────────────────────────────

  group('AppConstants', () {
    test('wsUrl contains userId', () {
      final url = AppConstants.wsUrl('user_123');
      expect(url, contains('user_123'));
      expect(url, startsWith('wss://'));
    });

    test('heartbeat interval is reasonable', () {
      expect(
        AppConstants.heartbeatInterval.inSeconds,
        greaterThanOrEqualTo(5),
      );
      expect(
        AppConstants.heartbeatInterval.inSeconds,
        lessThanOrEqualTo(30),
      );
    });

    test('frameCaptureInterval matches videoFps', () {
      expect(
        AppConstants.frameCaptureInterval.inMilliseconds,
        equals(1000 ~/ AppConstants.videoFps),
      );
    });

    test('reconnect params are sane', () {
      expect(AppConstants.maxReconnectAttempts, greaterThan(0));
      expect(AppConstants.baseReconnectDelay.inMilliseconds, greaterThan(0));
    });
  });

  // ── AgentMode ──────────────────────────────────────────────────────

  group('AgentMode values', () {
    test('there are exactly 4 modes', () {
      expect(AgentMode.values.length, 4);
    });

    test('wsValue matches enum name', () {
      for (final mode in AgentMode.values) {
        expect(mode.wsValue, mode.name);
      }
    });
  });

  // ── LiveSessionState ──────────────────────────────────────────────

  group('LiveSessionState', () {
    test('default state is disconnected and idle', () {
      const s = LiveSessionState();
      expect(s.connectionState, WsConnectionState.disconnected);
      expect(s.isStreaming, false);
      expect(s.isResponding, false);
      expect(s.mode, AgentMode.general);
      expect(s.transcript, isNull);
      expect(s.currentAction, isNull);
      expect(s.actionHistory, isEmpty);
    });

    test('copyWith preserves unchanged fields', () {
      const s = LiveSessionState(isStreaming: true, mode: AgentMode.tutor);
      final s2 = s.copyWith(isResponding: true);
      expect(s2.isStreaming, true);
      expect(s2.mode, AgentMode.tutor);
      expect(s2.isResponding, true);
    });

    test('copyWith clearTranscript works', () {
      const s = LiveSessionState(isStreaming: true);
      final s2 = s.copyWith(transcript: 'Hello');
      expect(s2.transcript, 'Hello');
      final s3 = s2.copyWith(clearTranscript: true);
      expect(s3.transcript, isNull);
    });
  });

  // ── SessionModel ──────────────────────────────────────────────────

  group('SessionModel', () {
    test('fromFirestore parses basic document', () {
      final model = SessionModel.fromFirestore({
        'id': 'sess_001',
        'mode': 'translator',
        'started_at': 1700000,
        'ended_at': 1700018,
        'turn_count': 12,
        'summary': 'Discussed Spanish vocabulary',
        'topics': ['greetings', 'colors'],
        'tags': ['language', 'spanish'],
      });

      expect(model.id, 'sess_001');
      expect(model.mode, AgentMode.translator);
      expect(model.turnCount, 12);
      expect(model.summary, 'Discussed Spanish vocabulary');
      expect(model.topics.length, 2);
      expect(model.tags.length, 2);
      expect(model.duration, isNotNull);
    });

    test('fromFirestore handles missing optional fields', () {
      final model = SessionModel.fromFirestore({
        'id': 'sess_002',
      });

      expect(model.id, 'sess_002');
      expect(model.mode, AgentMode.general);
      expect(model.turnCount, 0);
      expect(model.summary, '');
      expect(model.topics, isEmpty);
    });
  });
}
