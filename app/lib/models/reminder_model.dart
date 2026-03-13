import 'package:cloud_firestore/cloud_firestore.dart';

/// A timed reminder that fires as a local notification.
class ReminderModel {
  final String id;
  final String title;
  final String description;
  final DateTime remindAt;
  final int remindInMinutes;
  final DateTime createdAt;
  final bool isFired;

  const ReminderModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.remindAt,
    this.remindInMinutes = 60,
    required this.createdAt,
    this.isFired = false,
  });

  factory ReminderModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ReminderModel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      remindAt: _parseTimestamp(data['remindAt']),
      remindInMinutes: data['remindInMinutes'] as int? ?? 60,
      createdAt: _parseDate(data['createdAt']),
      isFired: data['isFired'] as bool? ?? false,
    );
  }

  factory ReminderModel.fromPayload(Map<String, dynamic> payload) {
    final remindInMin = payload['remindInMinutes'] as int? ?? 60;
    final remindAtEpoch = payload['remindAt'] as num?;
    final remindAt = remindAtEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (remindAtEpoch * 1000).toInt(),
            isUtc: true,
          )
        : DateTime.now().toUtc().add(Duration(minutes: remindInMin));

    return ReminderModel(
      id: payload['reminderId'] as String? ?? '',
      title: payload['title'] as String? ?? '',
      description: payload['description'] as String? ?? '',
      remindAt: remindAt,
      remindInMinutes: remindInMin,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'remindAt': remindAt.millisecondsSinceEpoch / 1000,
        'remindInMinutes': remindInMinutes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isFired': isFired,
      };

  ReminderModel copyWith({bool? isFired}) => ReminderModel(
        id: id,
        title: title,
        description: description,
        remindAt: remindAt,
        remindInMinutes: remindInMinutes,
        createdAt: createdAt,
        isFired: isFired ?? this.isFired,
      );

  /// Time remaining until the reminder fires.
  Duration get timeRemaining => remindAt.difference(DateTime.now().toUtc());

  /// Whether the reminder is in the past.
  bool get isPast => remindAt.isBefore(DateTime.now().toUtc());

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).toInt(),
        isUtc: true,
      );
    }
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
