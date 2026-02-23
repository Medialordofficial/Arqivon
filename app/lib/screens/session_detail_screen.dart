import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/session_model.dart';
import '../config/theme.dart';

/// Full session detail / replay screen accessible from the Archive.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});

  final SessionModel session;

  String _formatDuration(Duration? d) {
    if (d == null) return 'In progress';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMM d, y').format(session.startedAt);
    final timeStr = DateFormat('h:mm a').format(session.startedAt);
    final endTimeStr = session.endedAt != null
        ? DateFormat('h:mm a').format(session.endedAt!)
        : 'Ongoing';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? ArqivonTheme.darkBg : ArqivonTheme.background,
      appBar: AppBar(
        title: const Text('Session Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    session.mode.color,
                    session.mode.color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: session.mode.color.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: 'session_icon_${session.id}',
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            session.mode.icon,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                session.mode.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Stats row
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.calendar_today_rounded,
                        label: dateStr,
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        icon: Icons.access_time_rounded,
                        label: '$timeStr – $endTimeStr',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Metrics row ──────────────────────────────────────
            Row(
              children: [
                _MetricCard(
                  icon: Icons.mic_rounded,
                  value: '${session.turnCount}',
                  label: 'Turns',
                  color: ArqivonTheme.primary,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _MetricCard(
                  icon: Icons.timer_outlined,
                  value: _formatDuration(session.duration),
                  label: 'Duration',
                  color: ArqivonTheme.accent,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                _MetricCard(
                  icon: Icons.tag_rounded,
                  value: '${session.topics.length}',
                  label: 'Topics',
                  color: ArqivonTheme.successGreen,
                  isDark: isDark,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Summary ───────────────────────────────────────────
            if (session.summary.isNotEmpty) ...[
              _SectionHeader(title: 'Summary', isDark: isDark),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? ArqivonTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2A2A3E)
                        : ArqivonTheme.borderColor,
                  ),
                ),
                child: Text(
                  session.summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark
                        ? ArqivonTheme.darkText
                        : ArqivonTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Topics ─────────────────────────────────────────────
            if (session.topics.isNotEmpty) ...[
              _SectionHeader(title: 'Topics Covered', isDark: isDark),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: session.topics.map((topic) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: session.mode.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: session.mode.color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      topic,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: session.mode.color,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // ── Tags ───────────────────────────────────────────────
            if (session.tags.isNotEmpty) ...[
              _SectionHeader(title: 'Tags', isDark: isDark),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: session.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? ArqivonTheme.darkSurface
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label_outline_rounded,
                            size: 14,
                            color: isDark
                                ? ArqivonTheme.darkSubtext
                                : ArqivonTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? ArqivonTheme.darkSubtext
                                : ArqivonTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // ── Session info card ──────────────────────────────────
            _SectionHeader(title: 'Session Info', isDark: isDark),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? ArqivonTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A2A3E)
                      : ArqivonTheme.borderColor,
                ),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    label: 'Session ID',
                    value: session.id.length > 12
                        ? '${session.id.substring(0, 12)}…'
                        : session.id,
                    isDark: isDark,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Mode',
                    value: session.mode.label,
                    isDark: isDark,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Started',
                    value: DateFormat('h:mm:ss a').format(session.startedAt),
                    isDark: isDark,
                  ),
                  if (session.endedAt != null) ...[
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'Ended',
                      value: DateFormat('h:mm:ss a').format(session.endedAt!),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? ArqivonTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A3E) : ArqivonTheme.borderColor,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color:
                    isDark ? ArqivonTheme.darkText : ArqivonTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? ArqivonTheme.darkSubtext
                    : ArqivonTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: isDark ? ArqivonTheme.darkSubtext : ArqivonTheme.textSecondary,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color:
                isDark ? ArqivonTheme.darkSubtext : ArqivonTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? ArqivonTheme.darkText : ArqivonTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
