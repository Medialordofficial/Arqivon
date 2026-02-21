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
        return const Color(0xFF3E1F0D);
      case AgentMode.translator:
        return const Color(0xFFF59E0B);
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
      );
}

/// Translation overlay model from the backend's translator tools.
class TranslationOverlay {
  final String sourceText;
  final String sourceLanguage;
  final String targetLanguage;
  final String formality;
  final DateTime receivedAt;

  const TranslationOverlay({
    required this.sourceText,
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'en',
    this.formality = 'neutral',
    required this.receivedAt,
  });

  factory TranslationOverlay.fromPayload(Map<String, dynamic> p) =>
      TranslationOverlay(
        sourceText: p['source_text'] as String? ?? '',
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
