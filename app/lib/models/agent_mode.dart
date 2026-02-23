import 'package:flutter/material.dart';

/// The four operating modes for the Arqivo agent.
enum AgentMode {
  general,
  translator,
  tutor,
  support;

  String get label {
    switch (this) {
      case AgentMode.general:
        return 'Assistant';
      case AgentMode.translator:
        return 'Translator';
      case AgentMode.tutor:
        return 'Tutor';
      case AgentMode.support:
        return 'Support';
    }
  }

  String get description {
    switch (this) {
      case AgentMode.general:
        return 'Proactive multimodal assistant';
      case AgentMode.translator:
        return 'Real-time multilingual translator';
      case AgentMode.tutor:
        return 'Vision-enabled smart tutor';
      case AgentMode.support:
        return 'Voice-driven customer support';
    }
  }

  IconData get icon {
    switch (this) {
      case AgentMode.general:
        return Icons.auto_awesome_rounded;
      case AgentMode.translator:
        return Icons.translate_rounded;
      case AgentMode.tutor:
        return Icons.school_rounded;
      case AgentMode.support:
        return Icons.support_agent_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AgentMode.general:
        return const Color(0xFF5B5FEF);
      case AgentMode.translator:
        return const Color(0xFF0EA5E9);
      case AgentMode.tutor:
        return const Color(0xFF10B981);
      case AgentMode.support:
        return const Color(0xFF3B82F6);
    }
  }

  /// The name sent over WebSocket to backend.
  String get wsValue => name;
}

/// Tutor step model from the backend's tutor tools.
class TutorStep {
  final String tool;
  final int stepNumber;
  final int totalSteps;
  final double progressPct;
  final String title;
  final String explanation;
  final String? hintText;
  final String? concept;
  final String? feedback;
  final bool? isCorrect;
  final String? correctAnswer;
  final String? nextStepHint;
  final String? subject;
  final String? difficulty;

  // solve_problem fields
  final String? problem;
  final List<String> solutionSteps;
  final String? finalAnswer;

  // explain_concept fields
  final List<String> examples;
  final List<String> relatedTopics;
  final String? difficultyLevel;

  const TutorStep({
    required this.tool,
    this.stepNumber = 0,
    this.totalSteps = 0,
    this.progressPct = 0.0,
    this.title = '',
    this.explanation = '',
    this.hintText,
    this.concept,
    this.feedback,
    this.isCorrect,
    this.correctAnswer,
    this.nextStepHint,
    this.subject,
    this.difficulty,
    this.problem,
    this.solutionSteps = const [],
    this.finalAnswer,
    this.examples = const [],
    this.relatedTopics = const [],
    this.difficultyLevel,
  });

  factory TutorStep.fromPayload(Map<String, dynamic> p) => TutorStep(
        tool: p['tool'] as String? ?? 'unknown',
        stepNumber: (p['step_number'] as num?)?.toInt() ?? 0,
        totalSteps: (p['total_steps'] as num?)?.toInt() ?? 0,
        progressPct: (p['progress_pct'] as num?)?.toDouble() ?? 0.0,
        title: p['title'] as String? ?? '',
        explanation: p['explanation'] as String? ?? '',
        hintText: p['hint_text'] as String?,
        concept: p['concept'] as String?,
        feedback: p['feedback'] as String?,
        isCorrect: p['is_correct'] as bool?,
        correctAnswer: p['correct_answer'] as String?,
        nextStepHint: p['next_step_hint'] as String?,
        subject: p['subject'] as String?,
        difficulty: p['difficulty'] as String?,
        problem: p['problem'] as String?,
        solutionSteps:
            (p['solution_steps'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        finalAnswer: p['final_answer'] as String?,
        examples: (p['examples'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        relatedTopics:
            (p['related_topics'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        difficultyLevel: p['difficulty_level'] as String?,
      );
}

/// Translation overlay model from the backend's translator tools.
class TranslationOverlay {
  final String sourceText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final String formality;
  final DateTime receivedAt;

  const TranslationOverlay({
    required this.sourceText,
    this.translatedText = '',
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'en',
    this.formality = 'neutral',
    required this.receivedAt,
  });

  factory TranslationOverlay.fromPayload(Map<String, dynamic> p) =>
      TranslationOverlay(
        sourceText: p['source_text'] as String? ?? '',
        translatedText: p['translated_text'] as String? ?? '',
        sourceLanguage: p['source_language'] as String? ?? 'auto',
        targetLanguage: p['target_language'] as String? ?? 'en',
        formality: p['formality'] as String? ?? 'neutral',
        receivedAt: DateTime.now(),
      );
}

/// Support topic change from the backend's support tools.
class SupportTopic {
  final String topic;
  final String reason;
  final DateTime changedAt;

  const SupportTopic({
    required this.topic,
    this.reason = '',
    required this.changedAt,
  });

  factory SupportTopic.fromPayload(Map<String, dynamic> p) => SupportTopic(
        topic: p['new_topic'] as String? ?? 'General',
        reason: p['reason'] as String? ?? '',
        changedAt: DateTime.now(),
      );
}

/// Exportable document payload from the backend's export_document tool.
class ExportDocument {
  final String title;
  final String content;
  final String format;
  final List<Map<String, dynamic>> sections;
  final DateTime receivedAt;

  const ExportDocument({
    required this.title,
    required this.content,
    this.format = 'pdf',
    this.sections = const [],
    required this.receivedAt,
  });

  factory ExportDocument.fromPayload(Map<String, dynamic> p) => ExportDocument(
        title: p['title'] as String? ?? 'Export',
        content: p['content'] as String? ?? '',
        format: p['format'] as String? ?? 'pdf',
        sections: (p['sections'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        receivedAt: DateTime.now(),
      );
}
