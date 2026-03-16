import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the already-initialised Firebase app.
/// Firebase.initializeApp() is called in main() before runApp(), so this
/// provider completes synchronously on the first build — no loading state.
final firebaseInitProvider = FutureProvider<FirebaseApp>((ref) async {
  return Firebase.app(); // returns the default app, already initialised
});
