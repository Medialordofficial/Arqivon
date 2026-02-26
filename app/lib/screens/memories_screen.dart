import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/glassmorphic_card.dart';

/// Displays all AI memories stored for the current user.
///
/// Memories are stored in Firestore at `users/{uid}/memories/{key}` and are
/// created by the AI assistant via the `upsert_firestore_memory` tool during
/// conversations. This screen lets users see what the AI remembers about them,
/// copy individual memories, or delete them.
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(userIdProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY MEMORIES'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About Memories',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('memories')
            .orderBy('updated_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load memories',
                      style: TextStyle(fontSize: 16, color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 64, color: cs.primary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(
                      'No memories yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'As you talk with Arqivon, it will remember '
                      'important details about you — preferences, names, '
                      'topics, and more.',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final key = data['key'] as String? ?? doc.id;
              final value = data['value'] as String? ?? '';
              final updatedAt = data['updated_at'] as Timestamp?;
              final timeStr =
                  updatedAt != null ? _formatTimestamp(updatedAt) : 'Unknown';

              return GlassmorphicCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _iconForKey(key),
                          size: 20,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _humanizeKey(key),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                value,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: cs.onSurface.withValues(alpha: 0.4),
                            size: 20,
                          ),
                          onSelected: (action) {
                            if (action == 'copy') {
                              Clipboard.setData(
                                ClipboardData(text: '$key: $value'),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Memory copied'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else if (action == 'delete') {
                              _confirmDelete(context, doc.reference, key);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(Icons.copy_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Copy'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology_rounded, size: 24),
            SizedBox(width: 8),
            Text('About Memories'),
          ],
        ),
        content: const Text(
          'Memories are facts the AI learns about you during conversations. '
          'It automatically saves things like your name, preferences, '
          'interests, and frequently discussed topics.\n\n'
          'These memories help Arqivon personalize future conversations. '
          'You can delete any memory at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    DocumentReference ref,
    String key,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory'),
        content: Text('Remove "$key" from your memories?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              ref.delete();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Memory deleted'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp ts) {
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _humanizeKey(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  IconData _iconForKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('name')) return Icons.person_rounded;
    if (k.contains('lang')) return Icons.translate_rounded;
    if (k.contains('prefer')) return Icons.tune_rounded;
    if (k.contains('location') || k.contains('city')) {
      return Icons.location_on_rounded;
    }
    if (k.contains('work') || k.contains('job')) {
      return Icons.work_rounded;
    }
    if (k.contains('hobby') || k.contains('interest')) {
      return Icons.interests_rounded;
    }
    return Icons.memory_rounded;
  }
}
