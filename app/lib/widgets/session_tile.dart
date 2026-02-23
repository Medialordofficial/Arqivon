import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/session_model.dart';
import 'glassmorphic_card.dart';

/// A beautifully styled session tile for the Archive tab.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.onTap,
    this.onDelete,
  });

  final SessionModel session;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  String _formatDuration(Duration? d) {
    if (d == null) return 'In progress';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, y · h:mm a').format(session.startedAt);

    return GlassmorphicCard(
      blur: 10,
      opacity: 0.1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Left icon – mode-colored
              Hero(
                tag: 'session_icon_${session.id}',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        session.mode.color,
                        session.mode.color.withValues(alpha: 0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(session.mode.icon, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _chip(session.mode.icon, session.mode.label, context,
                            color: session.mode.color),
                        const SizedBox(width: 8),
                        _chip(Icons.mic, '${session.turnCount} turns', context),
                        const SizedBox(width: 8),
                        _chip(Icons.timer_outlined,
                            _formatDuration(session.duration), context),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.7)),
                  onPressed: onDelete,
                  iconSize: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, BuildContext context,
      {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
