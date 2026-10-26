import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_planner.dart';

/// The seam between the planner and the platform. Tests and platforms
/// without scheduled notifications use [NoNotifications].
abstract class NotificationService {
  bool get supported;

  /// Asks the system for permission; true when notifications may be shown.
  Future<bool> requestPermission();

  /// Cancels everything scheduled before and schedules [plan].
  Future<void> replaceAll(List<PlannedNotification> plan);

  /// The route of the notification that launched the app, if any.
  Future<String?> launchRoute();
}

class NoNotifications implements NotificationService {
  const NoNotifications();
  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async {}
  @override
  Future<String?> launchRoute() async => null;
}

/// Android and iOS through flutter_local_notifications. Times are passed
/// as UTC instants, so no time zone database is needed: every plan is a
/// set of one-shot notifications, rebuilt whenever the app runs.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({required this.onTap});

  /// Called with the notification's route when the learner taps it.
  final void Function(String route) onTap;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool?>? _init;

  static bool get platformSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get supported => platformSupported;

  Future<void> _ready() => _init ??= _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked only when the learner turns a reminder on.
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          final route = r.payload;
          if (route != null && route.startsWith('/')) onTap(route);
        },
      );

  @override
  Future<bool> requestPermission() async {
    await _ready();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Hatırlatıcılar',
      channelDescription: 'Kendi açtığın çalışma, tekrar ve haftalık özet hatırlatmaları',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      // Lock screen shows only the app name.
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async {
    await _ready();
    await _plugin.cancelAllPendingNotifications();
    for (final n in plan) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: n.route,
      );
    }
  }

  @override
  Future<String?> launchRoute() => coldStartRoute();

  /// Read in `main` before the router exists.
  static Future<String?> coldStartRoute() async {
    if (!platformSupported) return null;
    final NotificationAppLaunchDetails? d;
    try {
      d = await FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails();
    } catch (_) {
      return null;
    }
    if (d == null || !d.didNotificationLaunchApp) return null;
    final route = d.notificationResponse?.payload;
    return route != null && route.startsWith('/') ? route : null;
  }
}
