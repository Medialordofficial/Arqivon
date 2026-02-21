import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';

/// Initialises Firebase once and exposes the result.
/// The app renders immediately; auth gate waits on this future.
final firebaseInitProvider = FutureProvider<FirebaseApp>((ref) async {
  return Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
});
