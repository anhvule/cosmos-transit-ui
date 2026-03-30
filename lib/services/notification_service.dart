import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const initSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(initSettings);
  }

  static Future<void> scheduleDailyNotification() async {
    // Request permission on iOS
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Cancel existing scheduled notifications
    await _plugin.cancelAll();

    // Schedule daily at 7 AM
    await _plugin.periodicallyShow(
      0,
      'Your cosmic transit is ready',
      'Discover what the stars have in store for you today',
      RepeatInterval.daily,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    debugPrint('Daily notification scheduled');
  }
}
