import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_model.dart';
import '../models/reminder_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// Singleton FirestoreService (reuses the one in session_provider if exists).
final _firestoreProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

// ── Notes ────────────────────────────────────────────────────────────────────

/// Real-time stream of user notes from Firestore.
final notesStreamProvider = StreamProvider<List<NoteModel>>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == 'anonymous') return const Stream.empty();
  return ref.read(_firestoreProvider).notesStream(userId);
});

/// Toggle a to-do note's done state.
final toggleNoteDoneProvider =
    Provider<Future<void> Function(String noteId, bool isDone)>((ref) {
  final userId = ref.read(userIdProvider);
  final fs = ref.read(_firestoreProvider);
  return (noteId, isDone) => fs.toggleNoteDone(userId, noteId, isDone);
});

/// Delete a note.
final deleteNoteProvider =
    Provider<Future<void> Function(String noteId)>((ref) {
  final userId = ref.read(userIdProvider);
  final fs = ref.read(_firestoreProvider);
  return (noteId) => fs.deleteNote(userId, noteId);
});

// ── Reminders ────────────────────────────────────────────────────────────────

/// Real-time stream of user reminders from Firestore.
final remindersStreamProvider = StreamProvider<List<ReminderModel>>((ref) {
  final userId = ref.watch(userIdProvider);
  if (userId == 'anonymous') return const Stream.empty();
  return ref.read(_firestoreProvider).remindersStream(userId);
});

/// Delete a reminder and cancel its notification.
final deleteReminderProvider =
    Provider<Future<void> Function(String reminderId)>((ref) {
  final userId = ref.read(userIdProvider);
  final fs = ref.read(_firestoreProvider);
  return (reminderId) async {
    await NotificationService.instance.cancelReminder(reminderId.hashCode);
    await fs.deleteReminder(userId, reminderId);
  };
});

/// Schedule a local notification for a reminder.
Future<void> scheduleReminderNotification(ReminderModel reminder) async {
  await NotificationService.instance.scheduleReminder(
    id: reminder.id.hashCode,
    title: 'Reminder: ${reminder.title}',
    body: reminder.description,
    scheduledAt: reminder.remindAt,
  );
}
