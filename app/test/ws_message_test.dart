import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/models/ws_message.dart';

void main() {
  group('WsInbound', () {
    test('toJson includes all non-null fields', () {
      const msg = WsInbound(
        type: 'set_mode',
        mode: 'translator',
        voice: 'Puck',
        sourceLang: 'es',
        targetLang: 'en',
      );

      final json = msg.toJson();

      expect(json['type'], 'set_mode');
      expect(json['mode'], 'translator');
      expect(json['voice'], 'Puck');
      expect(json['source_lang'], 'es');
      expect(json['target_lang'], 'en');
      // timestamp is injected by WebSocketService.send(), not toJson()
      expect(json.containsKey('timestamp'), false);
    });

    test('toJson omits null fields', () {
      const msg = WsInbound(type: 'audio');
      final json = msg.toJson();

      expect(json['type'], 'audio');
      expect(json.containsKey('data'), false);
      expect(json.containsKey('text'), false);
      expect(json.containsKey('mode'), false);
      expect(json.containsKey('voice'), false);
      expect(json.containsKey('source_lang'), false);
      expect(json.containsKey('target_lang'), false);
    });

    test('audio message with data serializes correctly', () {
      const msg = WsInbound(type: 'audio', data: 'base64audiodata');
      final json = msg.toJson();

      expect(json['type'], 'audio');
      expect(json['data'], 'base64audiodata');
    });

    test('text message serializes correctly', () {
      const msg = WsInbound(type: 'text', text: 'Hello world');
      final json = msg.toJson();

      expect(json['type'], 'text');
      expect(json['text'], 'Hello world');
    });
  });

  group('WsOutbound', () {
    test('fromJson parses all fields', () {
      final json = {
        'type': 'ui_action',
        'data': null,
        'text': null,
        'action_type': 'open_url',
        'payload': {'title': 'Visit', 'description': 'https://google.com'},
      };

      final msg = WsOutbound.fromJson(json);

      expect(msg.type, 'ui_action');
      expect(msg.actionType, 'open_url');
      expect(msg.payload?['title'], 'Visit');
      expect(msg.payload?['description'], 'https://google.com');
    });

    test('fromJson handles minimal message', () {
      final json = {'type': 'pong'};
      final msg = WsOutbound.fromJson(json);

      expect(msg.type, 'pong');
      expect(msg.data, isNull);
      expect(msg.text, isNull);
      expect(msg.actionType, isNull);
      expect(msg.payload, isNull);
    });

    test('fromJson parses transcript message', () {
      final json = {'type': 'transcript', 'text': 'Hello, how can I help?'};
      final msg = WsOutbound.fromJson(json);

      expect(msg.type, 'transcript');
      expect(msg.text, 'Hello, how can I help?');
    });

    test('fromJson parses audio message', () {
      final json = {'type': 'audio', 'data': 'base64audiodata'};
      final msg = WsOutbound.fromJson(json);

      expect(msg.type, 'audio');
      expect(msg.data, 'base64audiodata');
    });

    test('fromJson parses translation payload', () {
      final json = {
        'type': 'translation',
        'payload': {
          'source_text': 'Hola',
          'translated_text': 'Hello',
          'source_language': 'es',
          'target_language': 'en',
          'formality': 'neutral',
        },
      };
      final msg = WsOutbound.fromJson(json);

      expect(msg.type, 'translation');
      expect(msg.payload?['source_text'], 'Hola');
      expect(msg.payload?['translated_text'], 'Hello');
    });
  });
}
