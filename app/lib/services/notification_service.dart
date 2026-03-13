import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../config/logger.dart';

/// Manages local notifications for reminders.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  static final _log = AppLogger('Notifications');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialise the notification plugin. Call once at app startup.
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notif_reminder');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions on Android 13+
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
    _log.info('Notification service initialized');
  }

  /// Schedule a local notification at a specific [DateTime].
  Future<void> scheduleReminder({
    required int id,
    required String title,
    String body = '',
    required DateTime scheduledAt,
  }) async {
    if (!_initialized) await init();

    final now = tz.TZDateTime.now(tz.local);
    final scheduled = tz.TZDateTime.from(scheduledAt.toLocal(), tz.local);

    // Don't schedule in the past
    if (scheduled.isBefore(now)) {
      _log.warning('Skipping past reminder: $title at $scheduledAt');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'arqivon_reminders',
      'Reminders',
      channelDescription: 'Reminders set via Arqivon AI',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@drawable/ic_notif_reminder',
      color: const Color(0xFF7C74A8),
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );

    _log.info('Scheduled reminder #$id "$title" at $scheduledAt');
  }

  /// Cancel a scheduled reminder.
  Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
    _log.info('Cancelled reminder #$id');
  }

  /// Cancel all scheduled reminders.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Show an immediate notification for a note being saved.
  Future<void> showNoteNotification({
    required int id,
    required String title,
    String body = '',
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'arqivon_notes',
      'Notes',
      channelDescription: 'Notes saved by Arqivon AI',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notif_note',
      color: Color(0xFF7C74A8),
      category: AndroidNotificationCategory.status,
      autoCancel: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
      ),
    );

    await _plugin.show(id, title, body, details);
    _log.info('Showed note notification #$id "$title"');
  }

  /// Show an immediate notification for a todo status change.
  Future<void> showTodoNotification({
    required int id,
    required String title,
    String body = '',
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'arqivon_todos',
      'Todos',
      channelDescription: 'Todo updates from Arqivon AI',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notif_todo',
      color: Color(0xFF7C74A8),
      category: AndroidNotificationCategory.status,
      autoCancel: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
      ),
    );

    await _plugin.show(id, title, body, details);
    _log.info('Showed todo notification #$id "$title"');
  }

  /// Show a session-related notification.
  Future<void> showSessionNotification({
    required int id,
    required String title,
    String body = '',
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'arqivon_sessions',
      'Sessions',
      channelDescription: 'Session updates from Arqivon',
      importance: Importance.low,
      priority: Priority.low,
      icon: '@drawable/ic_notif_session',
      color: Color(0xFF7C74A8),
      category: AndroidNotificationCategory.service,
      autoCancel: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
      ),
    );

    await _plugin.show(id, title, body, details);
    _log.info('Showed session notification #$id "$title"');
  }

  void _onNotificationTap(NotificationResponse response) {
    _log.info('Notification tapped: ${response.id}');
    // Could navigate to Notes tab — handled via app lifecycle in main.dart
  }
}
