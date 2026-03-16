import 'package:flutter/material.dart';

import '../models/smart_action.dart';
import 'glassmorphic_card.dart';

/// Overlay card rendered when Gemini dispatches a create_ui_action tool call.
class SmartActionCard extends StatelessWidget {
  const SmartActionCard({
    super.key,
    required this.action,
    required this.onDismiss,
    required this.onPrimaryAction,
  });

  final SmartAction action;
  final VoidCallback onDismiss;
  final VoidCallback onPrimaryAction;

  IconData _iconForType(String type) {
    switch (type) {
      case 'add_calendar':
        return Icons.calendar_today_rounded;
      case 'save_contact':
        return Icons.contact_page_rounded;
      case 'translate':
      case 'translation_card':
        return Icons.translate_rounded;
      case 'open_url':
        return Icons.open_in_browser_rounded;
      case 'save_note':
        return Icons.note_add_rounded;
      case 'add_reminder':
        return Icons.alarm_rounded;
      case 'share':
        return Icons.share_rounded;
      case 'escalate_case':
        return Icons.priority_high_rounded;
      case 'log_resolution':
        return Icons.check_circle_outline_rounded;
      case 'support_card':
        return Icons.support_agent_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'add_calendar':
        return const Color(0xFF3B82F6);
      case 'save_contact':
        return const Color(0xFF10B981);
      case 'translate':
      case 'translation_card':
        return const Color(0xFFF59E0B);
      case 'open_url':
        return const Color(0xFF6366F1);
      case 'save_note':
        return const Color(0xFFEC4899);
      case 'add_reminder':
        return const Color(0xFFEF4444);
      case 'share':
        return const Color(0xFF22D3EE);
      case 'escalate_case':
        return const Color(0xFFEF4444);
      case 'log_resolution':
        return const Color(0xFF10B981);
      case 'support_card':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6F4E37);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(action.actionType);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Semantics(
      label: 'Smart action: ${action.title}. ${action.description}',
      child: GlassmorphicCard(
        blur: 25,
        opacity: 0.2,
        borderOpacity: 0.3,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconForType(action.actionType),
                      color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                      if (action.description.isNotEmpty)
                        Text(
                          action.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: onSurface.withValues(alpha: 0.5)),
                  onPressed: onDismiss,
                  iconSize: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: Text(
                    'Dismiss',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onPrimaryAction,
                  icon: Icon(_iconForType(action.actionType), size: 18),
                  label: Text(action.primaryActionLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
