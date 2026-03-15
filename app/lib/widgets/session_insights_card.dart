import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/live_session_provider.dart';
import 'glassmorphic_card.dart';

/// Beautiful post-session recap card shown after the user stops a session.
class SessionInsightsCard extends StatefulWidget {
  const SessionInsightsCard({
    super.key,
    required this.insights,
    required this.onDismiss,
    this.onViewDetails,
  });

  final SessionInsights insights;
  final VoidCallback onDismiss;
  final VoidCallback? onViewDetails;

  @override
  State<SessionInsightsCard> createState() => _SessionInsightsCardState();
}

class _SessionInsightsCardState extends State<SessionInsightsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final modeColor = widget.insights.mode.color;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slideAnim.value),
        child: Opacity(
          opacity: _fadeAnim.value,
          child: child,
        ),
      ),
      child: GlassmorphicCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header gradient ───────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    modeColor,
                    modeColor.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.insights.title.isNotEmpty
                          ? widget.insights.title
                          : 'Session Complete',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),

            // ── Metrics row ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _Metric(
                    icon: Icons.mic_rounded,
                    value: '${widget.insights.turnCount}',
                    label: 'Turns',
                    color: modeColor,
                  ),
                  const SizedBox(width: 14),
                  if (widget.insights.notesSaved > 0) ...[
                    _Metric(
                      icon: Icons.note_add_rounded,
                      value: '${widget.insights.notesSaved}',
                      label: 'Saved',
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 14),
                  ],
                  _Metric(
                    icon: Icons.tag_rounded,
                    value: '${widget.insights.topics.length}',
                    label: 'Topics',
                    color: cs.tertiary,
                  ),
                ],
              ),
            ),

            // ── Summary ──────────────────────────────────────────
            if (widget.insights.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  widget.insights.summary,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // ── Topics chips ───────────────────────────────────
            if (widget.insights.topics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.insights.topics.take(5).map((topic) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: modeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: modeColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        topic,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: modeColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // ── View Details button ──────────────────────────────
            if (widget.onViewDetails != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onViewDetails!();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: modeColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: modeColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_rounded, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'View Session Details',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
