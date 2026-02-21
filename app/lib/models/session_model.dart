import 'agent_mode.dart';

/// Session record model for the Archive tab.
class SessionModel {
  final String id;
  final String userId;
  final String title;
  final String summary;
  final AgentMode mode;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int turnCount;
  final List<String> tags;
  final List<String> topics;
  final String? thumbnailUrl;

  const SessionModel({
    required this.id,
    required this.userId,
    this.title = 'Untitled Session',
    this.summary = '',
    this.mode = AgentMode.general,
    required this.startedAt,
    this.endedAt,
    this.turnCount = 0,
    this.tags = const [],
    this.topics = const [],
    this.thumbnailUrl,
  });

  factory SessionModel.fromFirestore(Map<String, dynamic> data) {
    final modeStr = data['mode'] as String? ?? 'general';
    return SessionModel(
      id: data['session_id'] as String? ?? data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      title: data['title'] as String? ?? 'Untitled Session',
      summary: data['summary'] as String? ?? '',
      mode: AgentMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AgentMode.general,
      ),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        ((data['started_at'] as num?) ?? 0).toInt() * 1000,
      ),
      endedAt: data['ended_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((data['ended_at'] as num)).toInt() * 1000,
            )
          : null,
      turnCount: (data['turn_count'] as num?)?.toInt() ?? 0,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      topics: (data['topics'] as List<dynamic>?)?.cast<String>() ?? [],
      thumbnailUrl: data['thumbnail_url'] as String?,
    );
  }

  Duration? get duration =>
      endedAt?.difference(startedAt);
}
