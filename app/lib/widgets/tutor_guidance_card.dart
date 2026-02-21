import 'package:flutter/material.dart';

import '../models/agent_mode.dart';
import 'glassmorphic_card.dart';

/// Step-by-step tutor guidance card shown during Tutor mode.
class TutorGuidanceCard extends StatelessWidget {
  const TutorGuidanceCard({
    super.key,
    required this.step,
    this.onDismiss,
    this.onRequestHint,
  });

  final TutorStep step;
  final VoidCallback? onDismiss;
  final VoidCallback? onRequestHint;

  Color get _toolColor {
    switch (step.tool) {
      case 'grade_step':
        return step.isCorrect == true
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444);
      case 'provide_hint':
        return const Color(0xFFF59E0B);
      case 'analyze_homework':
        return const Color(0xFF6366F1);
      default:
        return AgentMode.tutor.color;
    }
  }

  IconData get _toolIcon {
    switch (step.tool) {
      case 'grade_step':
        return step.isCorrect == true
            ? Icons.check_circle_rounded
            : Icons.cancel_rounded;
      case 'provide_hint':
        return Icons.lightbulb_rounded;
      case 'analyze_homework':
        return Icons.document_scanner_rounded;
      case 'tutor_card':
        return Icons.menu_book_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  String get _headerLabel {
    switch (step.tool) {
      case 'grade_step':
        return step.isCorrect == true ? 'CORRECT' : 'TRY AGAIN';
      case 'provide_hint':
        return 'HINT';
      case 'analyze_homework':
        return 'ANALYSIS';
      case 'tutor_card':
        return 'GUIDE';
      default:
        return 'TUTOR';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _toolColor;
    final hasProgress = step.totalSteps > 0 && step.progressPct > 0;

    return GlassmorphicCard(
      blur: 25,
      opacity: 0.22,
      borderOpacity: 0.35,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_toolIcon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _headerLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: color,
                  ),
                ),
              ),
              if (step.subject != null) ...[
                const SizedBox(width: 8),
                Text(
                  step.subject!,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
              const Spacer(),
              if (step.stepNumber > 0)
                Text(
                  'Step ${step.stepNumber}${step.totalSteps > 0 ? '/${step.totalSteps}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              if (onDismiss != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    onTap: onDismiss,
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white38),
                  ),
                ),
            ],
          ),

          // Progress bar
          if (hasProgress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: step.progressPct.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.1),
                color: color,
                minHeight: 4,
              ),
            ),
          ],

          // Title
          if (step.title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              step.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],

          // Main content (explanation / hint / feedback)
          if (step.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              step.explanation,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.8),
                height: 1.4,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (step.hintText != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.hintText!,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (step.feedback != null) ...[
            const SizedBox(height: 6),
            Text(
              step.feedback!,
              style: TextStyle(
                fontSize: 13,
                color: step.isCorrect == true
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
          if (step.correctAnswer != null && step.isCorrect == false) ...[
            const SizedBox(height: 4),
            Text(
              'Correct: ${step.correctAnswer}',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontStyle: FontStyle.italic),
            ),
          ],
          if (step.nextStepHint != null) ...[
            const SizedBox(height: 4),
            Text(
              'Next: ${step.nextStepHint}',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
          if (step.concept != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Concept: ${step.concept}',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          ],

          // Action buttons
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onRequestHint != null)
                TextButton.icon(
                  onPressed: onRequestHint,
                  icon: const Icon(Icons.lightbulb_outline, size: 16),
                  label: const Text('Need a hint'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                  ),
                ),
              if (onDismiss != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDismiss,
                  child: Text('Got it', style: TextStyle(color: color)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
