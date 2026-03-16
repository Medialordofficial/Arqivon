import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

/// Singleton AuthService.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Stream of auth state changes.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Current user ID (non-null convenience).
final userIdProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  return user?.uid ?? 'anonymous';
});

/// Whether user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});
