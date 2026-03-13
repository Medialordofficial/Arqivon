import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/note_model.dart';
import '../models/reminder_model.dart';
import '../providers/notes_provider.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
                top: topPad + 12, left: 20, right: 20, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes & Reminders',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved by Arqivon during conversations',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 12),
                // Tab bar
                Container(
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabCtrl,
                    indicator: BoxDecoration(
                      color: const Color(0xFFC98B4E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerHeight: 0,
                    labelColor: Colors.white,
                    unselectedLabelColor: cs.onSurface.withValues(alpha: 0.6),
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    tabs: const [
                      Tab(text: 'Notes & Todos'),
                      Tab(text: 'Reminders'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tab views ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: const [
                _NotesTab(),
                _RemindersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Notes & Todos Tab
// ═══════════════════════════════════════════════════════════════════════════════

class _NotesTab extends ConsumerWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesStreamProvider);
    final cs = Theme.of(context).colorScheme;

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error loading notes', style: TextStyle(color: cs.error)),
      ),
      data: (notes) {
        if (notes.isEmpty) return _buildEmptyState(cs, isNotes: true);

        // Separate todos from plain notes
        final todos = notes.where((n) => n.isTodo).toList();
        final plainNotes = notes.where((n) => !n.isTodo).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (todos.isNotEmpty) ...[
              _SectionHeader(
                title: 'To-Do',
                count: todos.length,
                doneCount: todos.where((t) => t.isDone).length,
              ),
              const SizedBox(height: 8),
              ...todos.map((t) => _TodoTile(note: t)),
              const SizedBox(height: 20),
            ],
            if (plainNotes.isNotEmpty) ...[
              _SectionHeader(title: 'Notes', count: plainNotes.length),
              const SizedBox(height: 8),
              ...plainNotes.map((n) => _NoteTile(note: n)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme cs, {required bool isNotes}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNotes ? Icons.note_alt_outlined : Icons.alarm_off_rounded,
            size: 64,
            color: cs.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            isNotes ? 'No notes yet' : 'No reminders',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 260,
            child: Text(
              isNotes
                  ? 'Say "Hey Arqivon, note that down" or\n"Add to my to-do list" during a conversation'
                  : 'Say "Set a reminder for 2 hours" during\na conversation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.35),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Reminders Tab
// ═══════════════════════════════════════════════════════════════════════════════

class _RemindersTab extends ConsumerWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersStreamProvider);
    final cs = Theme.of(context).colorScheme;

    return remindersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child:
            Text('Error loading reminders', style: TextStyle(color: cs.error)),
      ),
      data: (reminders) {
        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.alarm_off_rounded,
                    size: 64, color: cs.onSurface.withValues(alpha: 0.15)),
                const SizedBox(height: 16),
                Text(
                  'No reminders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 260,
                  child: Text(
                    'Say "Set a reminder for 2 hours"\nduring a conversation',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.35),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final upcoming =
            reminders.where((r) => !r.isFired && !r.isPast).toList();
        final past = reminders.where((r) => r.isFired || r.isPast).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (upcoming.isNotEmpty) ...[
              _SectionHeader(title: 'Upcoming', count: upcoming.length),
              const SizedBox(height: 8),
              ...upcoming.map((r) => _ReminderTile(reminder: r)),
              const SizedBox(height: 20),
            ],
            if (past.isNotEmpty) ...[
              _SectionHeader(title: 'Past', count: past.length),
              const SizedBox(height: 8),
              ...past.map((r) => _ReminderTile(reminder: r, isPast: true)),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final int? doneCount;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.doneCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFC98B4E).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            doneCount != null ? '$doneCount/$count' : '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC98B4E),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodoTile extends ConsumerWidget {
  final NoteModel note;
  const _TodoTile({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final ctrl = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Todo deleted'),
            action: SnackBarAction(label: 'UNDO', onPressed: () {}),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        final reason = await ctrl.closed;
        return reason != SnackBarClosedReason.action;
      },
      onDismissed: (_) => ref.read(deleteNoteProvider)(note.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Checkbox(
            value: note.isDone,
            onChanged: (val) =>
                ref.read(toggleNoteDoneProvider)(note.id, val ?? false),
            activeColor: const Color(0xFFC98B4E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          title: Text(
            note.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              decoration: note.isDone ? TextDecoration.lineThrough : null,
              color: note.isDone
                  ? cs.onSurface.withValues(alpha: 0.4)
                  : cs.onSurface,
            ),
          ),
          subtitle: note.content.isNotEmpty
              ? Text(
                  note.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                )
              : null,
          trailing: _priorityBadge(note.priority),
        ),
      ),
    );
  }

  Widget? _priorityBadge(String priority) {
    if (priority == 'normal' || priority == 'low') return null;
    final color = priority == 'urgent'
        ? Colors.red
        : priority == 'high'
            ? Colors.orange
            : null;
    if (color == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority.toUpperCase(),
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _NoteTile extends ConsumerWidget {
  final NoteModel note;
  const _NoteTile({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat.MMMd().add_jm().format(note.createdAt.toLocal());

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final ctrl = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Note deleted'),
            action: SnackBarAction(label: 'UNDO', onPressed: () {}),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        final reason = await ctrl.closed;
        return reason != SnackBarClosedReason.action;
      },
      onDismissed: (_) => ref.read(deleteNoteProvider)(note.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note_rounded,
                    size: 18,
                    color: const Color(0xFFC98B4E).withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            if (note.content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  final ReminderModel reminder;
  final bool isPast;

  const _ReminderTile({required this.reminder, this.isPast = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr =
        DateFormat.MMMd().add_jm().format(reminder.remindAt.toLocal());

    final remaining = reminder.timeRemaining;
    String countdownStr = '';
    if (!isPast && !remaining.isNegative) {
      if (remaining.inDays > 0) {
        countdownStr = 'in ${remaining.inDays}d ${remaining.inHours % 24}h';
      } else if (remaining.inHours > 0) {
        countdownStr = 'in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
      } else if (remaining.inMinutes > 0) {
        countdownStr = 'in ${remaining.inMinutes}m';
      } else {
        countdownStr = 'any moment';
      }
    }

    return Dismissible(
      key: ValueKey(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final ctrl = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reminder deleted'),
            action: SnackBarAction(label: 'UNDO', onPressed: () {}),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        final reason = await ctrl.closed;
        return reason != SnackBarClosedReason.action;
      },
      onDismissed: (_) => ref.read(deleteReminderProvider)(reminder.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPast
                ? cs.onSurface.withValues(alpha: 0.05)
                : const Color(0xFFC98B4E).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isPast
                    ? cs.onSurface.withValues(alpha: 0.06)
                    : const Color(0xFFC98B4E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isPast ? Icons.alarm_off_rounded : Icons.alarm_rounded,
                color: isPast
                    ? cs.onSurface.withValues(alpha: 0.3)
                    : const Color(0xFFC98B4E),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isPast
                          ? cs.onSurface.withValues(alpha: 0.4)
                          : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  if (reminder.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      reminder.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (countdownStr.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFC98B4E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  countdownStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC98B4E),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
