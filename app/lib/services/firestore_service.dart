import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/logger.dart';
import '../models/note_model.dart';
import '../models/reminder_model.dart';
import '../models/session_model.dart';

/// Firestore operations for sessions and user memories.
class FirestoreService {
  FirestoreService();

  static final _log = AppLogger('Firestore');

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Sessions ─────────────────────────────────────────────────────────

  /// Fetch all sessions for a user, ordered by most recent.
  Future<List<SessionModel>> getSessions(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('sessions')
          .orderBy('started_at', descending: true)
          .limit(50)
          .get();

      return snap.docs
          .map((d) => SessionModel.fromFirestore({...d.data(), 'id': d.id}))
          .toList();
    } catch (e, st) {
      _log.severe('getSessions error', e, st);
      rethrow;
    }
  }

  /// Delete a session.
  Future<void> deleteSession(String userId, String sessionId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .doc(sessionId)
        .delete();
  }

  // ── Memories ─────────────────────────────────────────────────────────

  /// Fetch all stored memories for a user.
  Future<List<Map<String, dynamic>>> getMemories(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('memories')
          .get();
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e, st) {
      _log.severe('getMemories error', e, st);
      rethrow;
    }
  }

  /// Save user settings to Firestore.
  Future<void> saveUserSettings(
    String userId, {
    required Map<String, dynamic> settings,
  }) async {
    await _db.collection('users').doc(userId).set({
      'settings': settings,
    }, SetOptions(merge: true));
  }

  /// Load user settings.
  Future<Map<String, dynamic>> loadUserSettings(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return (doc.data()?['settings'] as Map<String, dynamic>?) ?? {};
    } catch (e, st) {
      _log.severe('loadUserSettings error', e, st);
      return {};
    }
  }

  // ── Notes ──────────────────────────────────────────────────────────

  /// Fetch all notes for a user, newest first.
  Future<List<NoteModel>> getNotes(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('notes')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      return snap.docs.map((d) => NoteModel.fromFirestore(d)).toList();
    } catch (e, st) {
      _log.severe('getNotes error', e, st);
      rethrow;
    }
  }

  /// Stream notes in real-time.
  Stream<List<NoteModel>> notesStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notes')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => NoteModel.fromFirestore(d)).toList());
  }

  /// Toggle a to-do's done state.
  Future<void> toggleNoteDone(String userId, String noteId, bool isDone) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId)
        .update({'isDone': isDone});
  }

  /// Delete a note.
  Future<void> deleteNote(String userId, String noteId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId)
        .delete();
  }

  // ── Reminders ──────────────────────────────────────────────────────

  /// Fetch all reminders for a user, soonest first.
  Future<List<ReminderModel>> getReminders(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('reminders')
          .orderBy('remindAt', descending: false)
          .limit(100)
          .get();
      return snap.docs.map((d) => ReminderModel.fromFirestore(d)).toList();
    } catch (e, st) {
      _log.severe('getReminders error', e, st);
      rethrow;
    }
  }

  /// Stream reminders in real-time.
  Stream<List<ReminderModel>> remindersStream(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .orderBy('remindAt', descending: false)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ReminderModel.fromFirestore(d)).toList());
  }

  /// Mark a reminder as fired.
  Future<void> markReminderFired(String userId, String reminderId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(reminderId)
        .update({'isFired': true});
  }

  /// Delete a reminder.
  Future<void> deleteReminder(String userId, String reminderId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('reminders')
        .doc(reminderId)
        .delete();
  }
}
