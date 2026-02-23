import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/models/agent_mode.dart';

void main() {
  group('AgentMode', () {
    test('all modes have labels', () {
      for (final mode in AgentMode.values) {
        expect(mode.label.isNotEmpty, true);
      }
    });

    test('all modes have icons', () {
      for (final mode in AgentMode.values) {
        expect(mode.icon, isNotNull);
      }
    });

    test('all modes have colors', () {
      for (final mode in AgentMode.values) {
        expect(mode.color, isNotNull);
      }
    });

    test('wsValue returns name', () {
      expect(AgentMode.general.wsValue, 'general');
      expect(AgentMode.translator.wsValue, 'translator');
      expect(AgentMode.tutor.wsValue, 'tutor');
      expect(AgentMode.support.wsValue, 'support');
    });

    test('labels are descriptive', () {
      expect(AgentMode.general.label, 'Assistant');
      expect(AgentMode.translator.label, 'Translator');
      expect(AgentMode.tutor.label, 'Tutor');
      expect(AgentMode.support.label, 'Support');
    });

    test('descriptions are meaningful', () {
      for (final mode in AgentMode.values) {
        expect(mode.description.length > 10, true,
            reason: '${mode.name} should have a meaningful description');
      }
    });
  });

  group('TutorStep', () {
    test('fromPayload parses basic fields', () {
      final step = TutorStep.fromPayload({
        'tool': 'provide_hint',
        'step_number': 2,
        'total_steps': 5,
        'progress_pct': 0.4,
        'title': 'Step 2',
        'explanation': 'Use the quadratic formula',
        'hint_text': 'Remember b² - 4ac',
      });

      expect(step.tool, 'provide_hint');
      expect(step.stepNumber, 2);
      expect(step.totalSteps, 5);
      expect(step.progressPct, 0.4);
      expect(step.title, 'Step 2');
      expect(step.explanation, 'Use the quadratic formula');
      expect(step.hintText, 'Remember b² - 4ac');
    });

    test('fromPayload handles solve_problem fields', () {
      final step = TutorStep.fromPayload({
        'tool': 'solve_problem',
        'subject': 'math',
        'problem': 'x² + 5x + 6 = 0',
        'solution_steps': ['Factor', 'Set each = 0', 'Solve'],
        'final_answer': 'x = -2, x = -3',
        'explanation': 'Factoring a quadratic',
      });

      expect(step.tool, 'solve_problem');
      expect(step.subject, 'math');
      expect(step.problem, 'x² + 5x + 6 = 0');
      expect(step.solutionSteps.length, 3);
      expect(step.finalAnswer, 'x = -2, x = -3');
    });

    test('fromPayload handles explain_concept fields', () {
      final step = TutorStep.fromPayload({
        'tool': 'explain_concept',
        'concept': 'Pythagorean Theorem',
        'subject': 'geometry',
        'explanation': 'a² + b² = c²',
        'examples': ['3-4-5 triangle', '5-12-13 triangle'],
        'related_topics': ['Trigonometry', 'Distance formula'],
        'difficulty_level': 'intermediate',
      });

      expect(step.concept, 'Pythagorean Theorem');
      expect(step.examples.length, 2);
      expect(step.relatedTopics.length, 2);
      expect(step.difficultyLevel, 'intermediate');
    });

    test('fromPayload handles missing fields gracefully', () {
      final step = TutorStep.fromPayload({});

      expect(step.tool, 'unknown');
      expect(step.stepNumber, 0);
      expect(step.totalSteps, 0);
      expect(step.progressPct, 0.0);
      expect(step.title, '');
      expect(step.explanation, '');
      expect(step.solutionSteps, isEmpty);
      expect(step.examples, isEmpty);
      expect(step.relatedTopics, isEmpty);
    });

    test('fromPayload handles grade_step', () {
      final step = TutorStep.fromPayload({
        'tool': 'grade_step',
        'step_number': 1,
        'is_correct': false,
        'feedback': 'Check your algebra',
        'correct_answer': '42',
        'next_step_hint': 'Try factoring',
      });

      expect(step.isCorrect, false);
      expect(step.feedback, 'Check your algebra');
      expect(step.correctAnswer, '42');
      expect(step.nextStepHint, 'Try factoring');
    });
  });

  group('TranslationOverlay', () {
    test('fromPayload parses all fields', () {
      final overlay = TranslationOverlay.fromPayload({
        'source_text': 'Bonjour',
        'translated_text': 'Hello',
        'source_language': 'fr',
        'target_language': 'en',
        'formality': 'formal',
      });

      expect(overlay.sourceText, 'Bonjour');
      expect(overlay.translatedText, 'Hello');
      expect(overlay.sourceLanguage, 'fr');
      expect(overlay.targetLanguage, 'en');
      expect(overlay.formality, 'formal');
      expect(overlay.receivedAt, isNotNull);
    });

    test('fromPayload handles defaults', () {
      final overlay = TranslationOverlay.fromPayload({});

      expect(overlay.sourceText, '');
      expect(overlay.translatedText, '');
      expect(overlay.sourceLanguage, 'auto');
      expect(overlay.targetLanguage, 'en');
      expect(overlay.formality, 'neutral');
    });
  });

  group('SupportTopic', () {
    test('fromPayload parses fields', () {
      final topic = SupportTopic.fromPayload({
        'new_topic': 'Billing Issue',
        'reason': 'Customer asked about charges',
      });

      expect(topic.topic, 'Billing Issue');
      expect(topic.reason, 'Customer asked about charges');
      expect(topic.changedAt, isNotNull);
    });

    test('fromPayload handles missing fields', () {
      final topic = SupportTopic.fromPayload({});

      expect(topic.topic, 'General');
      expect(topic.reason, '');
    });
  });

  group('ExportDocument', () {
    test('fromPayload parses all fields', () {
      final doc = ExportDocument.fromPayload({
        'title': 'My Report',
        'content': 'Report content here',
        'format': 'pdf',
        'sections': [
          {'heading': 'Intro', 'body': 'Introduction text'},
        ],
      });

      expect(doc.title, 'My Report');
      expect(doc.content, 'Report content here');
      expect(doc.format, 'pdf');
      expect(doc.sections.length, 1);
      expect(doc.receivedAt, isNotNull);
    });

    test('fromPayload handles defaults', () {
      final doc = ExportDocument.fromPayload({});

      expect(doc.title, 'Export');
      expect(doc.content, '');
      expect(doc.format, 'pdf');
      expect(doc.sections, isEmpty);
    });
  });
}
