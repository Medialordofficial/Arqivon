import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/logger.dart';

/// Firebase Auth service supporting Email, Google, and Apple sign-in.
class AuthService {
  AuthService();

  static final _log = AppLogger('Auth');

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  String get userId => _auth.currentUser?.uid ?? 'anonymous';
  bool get isSignedIn => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Email / Password ─────────────────────────────────────────────

  /// Create a new account with email and password.
  Future<User?> createAccountWithEmail(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _log.info('Account created: ${result.user?.email}');
      return result.user;
    } catch (e) {
      _log.severe('Create account error', e);
      rethrow;
    }
  }

  /// Sign in with email and password.
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _log.info('Signed in: ${result.user?.email}');
      return result.user;
    } catch (e) {
      _log.severe('Email sign-in error', e);
      rethrow;
    }
  }

  /// Send password reset email.
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ── Google Sign-In ────────────────────────────────────────────────

  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      _log.info('Google signed in: ${result.user?.displayName}');
      return result.user;
    } catch (e) {
      _log.severe('Google sign-in error', e);
      rethrow;
    }
  }

  // ── Apple Sign-In ─────────────────────────────────────────────────

  Future<User?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final result = await _auth.signInWithCredential(oauthCredential);

      // Apple only provides the name on first sign-in; persist it.
      if (result.user?.displayName == null &&
          appleCredential.givenName != null) {
        await result.user?.updateDisplayName(
          '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'
              .trim(),
        );
        await result.user?.reload();
      }

      _log.info('Apple signed in: ${result.user?.displayName}');
      return result.user;
    } catch (e) {
      _log.severe('Apple sign-in error', e);
      rethrow;
    }
  }

  /// Whether Apple Sign-In is available on this device.
  bool get isAppleSignInAvailable {
    if (kIsWeb) return true; // Safari / redirects
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _log.info('Signed out');
  }

  // ── Delete Account ────────────────────────────────────────────────

  /// Permanently delete the current user account.
  /// Throws if the user needs to re-authenticate first.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');
    try {
      await user.delete();
      await _googleSignIn.signOut();
      _log.info('Account deleted');
    } catch (e) {
      _log.severe('Delete account error', e);
      rethrow;
    }
  }
}
