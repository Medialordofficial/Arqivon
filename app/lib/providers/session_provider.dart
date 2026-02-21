import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_model.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';

/// Singleton Firestore service.
final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

/// Async list of sessions for the archive.
class SessionListNotifier extends AutoDisposeAsyncNotifier<List<SessionModel>> {
  @override
  Future<List<SessionModel>> build() async {
    final userId = ref.watch(userIdProvider);
    if (userId == 'anonymous') return [];
    final fs = ref.read(firestoreServiceProvider);
    return fs.getSessions(userId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final userId = ref.read(userIdProvider);
      final fs = ref.read(firestoreServiceProvider);
      return fs.getSessions(userId);
    });
  }

  Future<void> deleteSession(String sessionId) async {
    final userId = ref.read(userIdProvider);
    final fs = ref.read(firestoreServiceProvider);
    await fs.deleteSession(userId, sessionId);
    await refresh();
  }
}

final sessionListProvider =
    AutoDisposeAsyncNotifierProvider<SessionListNotifier, List<SessionModel>>(
  SessionListNotifier.new,
);
