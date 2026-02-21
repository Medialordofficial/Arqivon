import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/session_model.dart';

/// Firestore operations for sessions and user memories.
class FirestoreService {
  FirestoreService();

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
    } catch (e) {
      debugPrint('[Firestore] getSessions error: $e');
      return [];
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
    } catch (e) {
      debugPrint('[Firestore] getMemories error: $e');
      return [];
    }
  }

  /// Save user settings to Firestore.
  Future<void> saveUserSettings(
    String userId, {
    required Map<String, dynamic> settings,
  }) async {
    await _db.collection('users').doc(userId).set(
      {'settings': settings},
      SetOptions(merge: true),
    );
  }

  /// Load user settings.
  Future<Map<String, dynamic>> loadUserSettings(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return (doc.data()?['settings'] as Map<String, dynamic>?) ?? {};
    } catch (e) {
      return {};
    }
  }
}
