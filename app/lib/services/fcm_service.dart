import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/logger.dart';

/// Handles Firebase Cloud Messaging (FCM) setup, permissions, and token
/// lifecycle.  Saves the device token to the user's Firestore document so
/// the backend can send push notifications (e.g. session summary ready).
class FcmService {
  static final _log = AppLogger('FcmService');
  static bool _initialised = false;

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS requires explicit ask; Android 13+ optional).
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    _log.info(
      'FCM permission: ${settings.authorizationStatus}',
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _log.warning('User denied notification permissions');
      return;
    }

    // Get and save FCM token.
    try {
      final token = await messaging.getToken();
      if (token != null) {
        _log.info('FCM token obtained (${token.substring(0, 12)}…)');
        await _saveToken(token);
      }
    } catch (e) {
      _log.warning('Failed to get FCM token: $e');
    }

    // Listen for token refreshes.
    messaging.onTokenRefresh.listen((newToken) {
      _log.info('FCM token refreshed');
      _saveToken(newToken);
    });

    // Handle foreground messages.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _log.info(
        'Foreground FCM: ${message.notification?.title ?? message.data.toString()}',
      );
      // Notifications are shown automatically by the system when the app
      // is in the background.  In the foreground we just log — a future
      // enhancement could show a SnackBar or in-app banner.
    });

    // Handle notification taps when the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _log.info('Notification tap opened app: ${message.data}');
      // Could navigate to archive / session detail in the future.
    });
  }

  /// Persist the FCM token under the current user's Firestore doc so the
  /// backend can target notifications via `firebase-admin` messaging.
  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: true));
      _log.info('FCM token saved to Firestore for ${user.uid}');
    } catch (e) {
      _log.warning('Failed to save FCM token: $e');
    }
  }

  /// Re-save the FCM token when the user signs in (uid may have changed).
  static Future<void> onUserSignIn() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _saveToken(token);
      }
    } catch (e) {
      _log.fine('FCM onUserSignIn: $e');
    }
  }
}
