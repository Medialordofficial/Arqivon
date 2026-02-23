import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/models/agent_mode.dart';
import 'package:arqivon/models/smart_action.dart';
import 'package:arqivon/providers/live_session_provider.dart';
import 'package:arqivon/services/websocket_service.dart';

void main() {
  group('LiveSessionState', () {
    test('default state has correct values', () {
      const s = LiveSessionState();
      expect(s.connectionState, WsConnectionState.disconnected);
      expect(s.isStreaming, false);
      expect(s.isResponding, false);
      expect(s.mode, AgentMode.general);
      expect(s.transcript, isNull);
      expect(s.userTranscript, isNull);
      expect(s.currentAction, isNull);
      expect(s.actionHistory, isEmpty);
      expect(s.currentTranslation, isNull);
      expect(s.translationHistory, isEmpty);
      expect(s.sourceLang, 'auto');
      expect(s.targetLang, 'en');
      expect(s.currentTutorStep, isNull);
      expect(s.tutorSteps, isEmpty);
      expect(s.currentSupportTopic, isNull);
      expect(s.supportTopics, isEmpty);
      expect(s.pendingExport, isNull);
    });

    test('copyWith preserves all unchanged fields', () {
      const s = LiveSessionState(
        connectionState: WsConnectionState.connected,
        isStreaming: true,
        isResponding: true,
        mode: AgentMode.translator,
        sourceLang: 'fr',
        targetLang: 'de',
      );
      final s2 = s.copyWith(isResponding: false);

      expect(s2.connectionState, WsConnectionState.connected);
      expect(s2.isStreaming, true);
      expect(s2.isResponding, false);
      expect(s2.mode, AgentMode.translator);
      expect(s2.sourceLang, 'fr');
      expect(s2.targetLang, 'de');
    });

    test('copyWith clearTranscript clears transcript', () {
      const s = LiveSessionState();
      final s2 = s.copyWith(transcript: 'Hello there');
      expect(s2.transcript, 'Hello there');
      final s3 = s2.copyWith(clearTranscript: true);
      expect(s3.transcript, isNull);
    });

    test('copyWith clearUserTranscript clears userTranscript', () {
      const s = LiveSessionState();
      final s2 = s.copyWith(userTranscript: 'User said something');
      expect(s2.userTranscript, 'User said something');
      final s3 = s2.copyWith(clearUserTranscript: true);
      expect(s3.userTranscript, isNull);
    });

    test('copyWith clearAction clears currentAction', () {
      final action = SmartAction(actionType: 'test', title: 'Test');
      const s = LiveSessionState();
      final s2 = s.copyWith(currentAction: action);
      expect(s2.currentAction, isNotNull);
      final s3 = s2.copyWith(clearAction: true);
      expect(s3.currentAction, isNull);
    });

    test('actionHistory accumulates actions', () {
      const s = LiveSessionState();
      final a1 = SmartAction(actionType: 'url', title: 'URL 1');
      final a2 = SmartAction(actionType: 'call', title: 'Call');
      final s2 = s.copyWith(actionHistory: [a1]);
      expect(s2.actionHistory.length, 1);
      final s3 = s2.copyWith(actionHistory: [...s2.actionHistory, a2]);
      expect(s3.actionHistory.length, 2);
      expect(s3.actionHistory[0].actionType, 'url');
      expect(s3.actionHistory[1].actionType, 'call');
    });

    test('copyWith clearTranslation clears currentTranslation', () {
      final overlay = TranslationOverlay.fromPayload({
        'source_text': 'Hola',
        'translated_text': 'Hello',
        'source_language': 'es',
        'target_language': 'en',
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(currentTranslation: overlay);
      expect(s2.currentTranslation, isNotNull);
      final s3 = s2.copyWith(clearTranslation: true);
      expect(s3.currentTranslation, isNull);
    });

    test('translationHistory accumulates overlays', () {
      final o1 = TranslationOverlay.fromPayload({
        'source_text': 'Bonjour',
        'translated_text': 'Hello',
      });
      final o2 = TranslationOverlay.fromPayload({
        'source_text': 'Merci',
        'translated_text': 'Thank you',
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(translationHistory: [o1, o2]);
      expect(s2.translationHistory.length, 2);
    });

    test('copyWith clearTutorStep clears currentTutorStep', () {
      final step = TutorStep.fromPayload({
        'tool': 'provide_hint',
        'title': 'Hint',
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(currentTutorStep: step);
      expect(s2.currentTutorStep, isNotNull);
      final s3 = s2.copyWith(clearTutorStep: true);
      expect(s3.currentTutorStep, isNull);
    });

    test('copyWith clearExport clears pendingExport', () {
      final doc = ExportDocument.fromPayload({
        'title': 'Report',
        'content': 'Content',
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(pendingExport: doc);
      expect(s2.pendingExport, isNotNull);
      final s3 = s2.copyWith(clearExport: true);
      expect(s3.pendingExport, isNull);
    });

    test('language settings update correctly', () {
      const s = LiveSessionState();
      final s2 = s.copyWith(sourceLang: 'ja', targetLang: 'ko');
      expect(s2.sourceLang, 'ja');
      expect(s2.targetLang, 'ko');
    });

    test('mode can be set to every AgentMode', () {
      for (final mode in AgentMode.values) {
        const s = LiveSessionState();
        final s2 = s.copyWith(mode: mode);
        expect(s2.mode, mode);
      }
    });

    test('connection state transitions', () {
      const s = LiveSessionState();
      expect(s.connectionState, WsConnectionState.disconnected);

      final s2 = s.copyWith(connectionState: WsConnectionState.connecting);
      expect(s2.connectionState, WsConnectionState.connecting);

      final s3 = s2.copyWith(connectionState: WsConnectionState.connected);
      expect(s3.connectionState, WsConnectionState.connected);

      final s4 = s3.copyWith(connectionState: WsConnectionState.reconnecting);
      expect(s4.connectionState, WsConnectionState.reconnecting);
    });

    test('supportTopics accumulate', () {
      final t1 = SupportTopic.fromPayload({
        'new_topic': 'Billing',
        'reason': 'Asked about charges',
      });
      final t2 = SupportTopic.fromPayload({
        'new_topic': 'Returns',
        'reason': 'Wants to return item',
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(supportTopics: [t1, t2]);
      expect(s2.supportTopics.length, 2);
      expect(s2.supportTopics[0].topic, 'Billing');
      expect(s2.supportTopics[1].topic, 'Returns');
    });

    test('tutorSteps accumulate', () {
      final step1 = TutorStep.fromPayload({
        'tool': 'provide_hint',
        'step_number': 1,
      });
      final step2 = TutorStep.fromPayload({
        'tool': 'grade_step',
        'step_number': 2,
      });
      const s = LiveSessionState();
      final s2 = s.copyWith(tutorSteps: [step1, step2]);
      expect(s2.tutorSteps.length, 2);
    });
  });

  group('WsConnectionState', () {
    test('has exactly 4 states', () {
      expect(WsConnectionState.values.length, 4);
    });

    test('states are named correctly', () {
      expect(WsConnectionState.disconnected.name, 'disconnected');
      expect(WsConnectionState.connecting.name, 'connecting');
      expect(WsConnectionState.connected.name, 'connected');
      expect(WsConnectionState.reconnecting.name, 'reconnecting');
    });
  });
}
