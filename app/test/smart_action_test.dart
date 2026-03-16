import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/models/smart_action.dart';

void main() {
  group('SmartAction', () {
    test('constructor sets required fields', () {
      final action = SmartAction(
        actionType: 'open_url',
        title: 'Visit Google',
      );
      expect(action.actionType, 'open_url');
      expect(action.title, 'Visit Google');
      expect(action.description, '');
      expect(action.icon, 'auto_awesome');
      expect(action.primaryActionLabel, 'OK');
      expect(action.receivedAt, isNotNull);
    });

    test('constructor uses custom values', () {
      final action = SmartAction(
        actionType: 'call',
        title: 'Call Mom',
        description: '+1-555-1234',
        icon: 'phone',
        primaryActionLabel: 'Call',
      );
      expect(action.actionType, 'call');
      expect(action.title, 'Call Mom');
      expect(action.description, '+1-555-1234');
      expect(action.icon, 'phone');
      expect(action.primaryActionLabel, 'Call');
    });

    test('fromPayload parses complete payload', () {
      final action = SmartAction.fromPayload('open_url', {
        'title': 'Visit Site',
        'description': 'https://example.com',
        'icon': 'link',
        'primary_action_label': 'Open',
      });

      expect(action.actionType, 'open_url');
      expect(action.title, 'Visit Site');
      expect(action.description, 'https://example.com');
      expect(action.icon, 'link');
      expect(action.primaryActionLabel, 'Open');
    });

    test('fromPayload handles empty payload', () {
      final action = SmartAction.fromPayload('generic', {});

      expect(action.actionType, 'generic');
      expect(action.title, 'generic');
      expect(action.description, '');
      expect(action.icon, 'auto_awesome');
      expect(action.primaryActionLabel, 'OK');
    });

    test('fromPayload handles partial payload', () {
      final action = SmartAction.fromPayload('save_contact', {
        'title': 'Save Contact',
      });

      expect(action.actionType, 'save_contact');
      expect(action.title, 'Save Contact');
      expect(action.description, '');
      expect(action.icon, 'auto_awesome');
    });

    test('receivedAt is set to current time', () {
      final before = DateTime.now();
      final action = SmartAction(actionType: 'test', title: 'Test');
      final after = DateTime.now();

      expect(action.receivedAt.isAfter(before) || action.receivedAt == before,
          true);
      expect(action.receivedAt.isBefore(after) || action.receivedAt == after,
          true);
    });

    test('custom receivedAt is preserved', () {
      final customTime = DateTime(2024, 1, 1, 12, 0);
      final action = SmartAction(
        actionType: 'test',
        title: 'Test',
        receivedAt: customTime,
      );
      expect(action.receivedAt, customTime);
    });
  });
}
