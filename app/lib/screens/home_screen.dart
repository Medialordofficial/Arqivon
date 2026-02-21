import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_mode.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/glassmorphic_card.dart';
import '../widgets/session_tile.dart';

/// Provider tracking the active mode filter (null = show all).
final modeFilterProvider = StateProvider<AgentMode?>((ref) => null);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionListProvider);
    final isAuthed = ref.watch(isAuthenticatedProvider);
    final filterMode = ref.watch(modeFilterProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('ARCHIVE'),
        actions: [
          IconButton(
            onPressed: () => ref.read(sessionListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: !isAuthed
            ? _buildSignInPrompt(context, ref)
            : sessionsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text('Failed to load sessions: $e',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () =>
                              ref.read(sessionListProvider.notifier).refresh(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (allSessions) {
                  if (allSessions.isEmpty) {
                    return _buildEmpty(context);
                  }

                  final sessions = filterMode == null
                      ? allSessions
                      : allSessions.where((s) => s.mode == filterMode).toList();

                  return Column(
                    children: [
                      // ── Mode filter chips ──────────────────────────
                      _ModeFilterBar(
                        sessionCounts: {
                          for (final m in AgentMode.values)
                            m: allSessions.where((s) => s.mode == m).length,
                        },
                        totalCount: allSessions.length,
                        selected: filterMode,
                        onSelected: (m) =>
                            ref.read(modeFilterProvider.notifier).state = m,
                      ),

                      // ── Session count & list ───────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),

                      if (sessions.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              'No ${filterMode?.label.toLowerCase() ?? ""} sessions yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            physics: const BouncingScrollPhysics(),
                            itemCount: sessions.length,
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return SessionTile(
                                session: session,
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Reloading context: ${session.title}'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                onDelete: () => ref
                                    .read(sessionListProvider.notifier)
                                    .deleteSession(session.id),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSignInPrompt(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: GlassmorphicCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 48, color: Color(0xFF6F4E37)),
              const SizedBox(height: 16),
              const Text(
                'Sign in to view your archive',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your multimodal sessions are securely stored and only accessible to you.',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(authServiceProvider).signInWithGoogle();
                },
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3E1F0D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined,
                size: 64,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a Live session and it will appear here.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode filter bar ─────────────────────────────────────────────────────────
class _ModeFilterBar extends StatelessWidget {
  const _ModeFilterBar({
    required this.sessionCounts,
    required this.totalCount,
    required this.selected,
    required this.onSelected,
  });

  final Map<AgentMode, int> sessionCounts;
  final int totalCount;
  final AgentMode? selected;
  final ValueChanged<AgentMode?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            icon: Icons.grid_view_rounded,
            count: totalCount,
            color: const Color(0xFF6F4E37),
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...AgentMode.values.map(
            (mode) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: mode.label,
                icon: mode.icon,
                count: sessionCounts[mode] ?? 0,
                color: mode.color,
                isSelected: selected == mode,
                onTap: () => onSelected(selected == mode ? null : mode),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: isSelected ? color : color.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : color.withOpacity(0.6),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
