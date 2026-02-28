import 'package:cloud_firestore/cloud_firestore.dart';

/// A user note or to-do item saved by the AI during conversation.
class NoteModel {
  final String id;
  final String title;
  final String content;
  final bool isTodo;
  final bool isDone;
  final String priority; // low, normal, high, urgent
  final DateTime createdAt;

  const NoteModel({
    required this.id,
    required this.title,
    this.content = '',
    this.isTodo = false,
    this.isDone = false,
    this.priority = 'normal',
    required this.createdAt,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return NoteModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      isTodo: data['isTodo'] as bool? ?? false,
      isDone: data['isDone'] as bool? ?? false,
      priority: data['priority'] as String? ?? 'normal',
      createdAt: _parseDate(data['createdAt']),
    );
  }

  factory NoteModel.fromPayload(Map<String, dynamic> payload) {
    return NoteModel(
      id: payload['noteId'] as String? ?? '',
      title: payload['title'] as String? ?? '',
      content: payload['content'] as String? ?? '',
      isTodo: payload['isTodo'] as bool? ?? false,
      isDone: false,
      priority: payload['priority'] as String? ?? 'normal',
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'content': content,
        'isTodo': isTodo,
        'isDone': isDone,
        'priority': priority,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  NoteModel copyWith({bool? isDone}) => NoteModel(
        id: id,
        title: title,
        content: content,
        isTodo: isTodo,
        isDone: isDone ?? this.isDone,
        priority: priority,
        createdAt: createdAt,
      );

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
