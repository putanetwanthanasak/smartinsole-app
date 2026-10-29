import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:timezone/timezone.dart' as tz;

import 'android_resources.dart';
import 'reminder_notifier.dart';
import 'reminder_plan.dart';
import 'time_zone.dart';

/// [ReminderNotifier] on `flutter_local_notifications`: one-shot inexact
/// notifications (`inexactAllowWhileIdle`, no exact-alarm permission; a
/// few minutes late is fine), restored after a reboot by the plugin's boot
/// receiver (manifest). Text has no health details (user decision 2).
class LocalReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const payload = 'foot-check-reminder';
  static const title = 'ถึงเวลาดูเท้าประจำวัน';
  static const body = 'ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที';

  // A channel's sound is fixed once created, so the silent reminder has
  // its own channel. Names are what the phone's settings show (draft).
  static const _soundChannel = AndroidNotificationDetails(
    'foot_check_reminder',
    'เตือนให้ดูเท้า',
    channelDescription: 'เตือนตอนเย็นถ้าวันนี้ยังไม่ได้ดูเท้า',
    importance: Importance.high,
    priority: Priority.high,
    icon: AndroidResources.reminderIcon,
  );
  static const _silentChannel = AndroidNotificationDetails(
    'foot_check_reminder_silent',
    'เตือนให้ดูเท้า (ไม่มีเสียง)',
    channelDescription: 'เตือนตอนเย็นแบบไม่มีเสียง',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: false,
    enableVibration: false,
    icon: AndroidResources.reminderIcon,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init({required void Function() onTap}) async {
    final zone = await initLocalTimeZone(
      zoneName: () async =>
          (await FlutterTimezone.getLocalTimezone()).identifier,
      offset: DateTime.now().timeZoneOffset,
    );
    debugPrint('reminder: local time zone ${zone.name}');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(AndroidResources.reminderIcon),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == payload) onTap();
      },
    );
  }

  @override
  Future<bool> launchedFromReminder() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false) &&
        d?.notificationResponse?.payload == payload;
  }

  @override
  Future<bool> enabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> request() async {
    await _android?.requestNotificationsPermission();
    return enabled();
  }

  @override
  Future<void> openSettings() => ph.openAppSettings();

  @override
  Future<void> replaceAll(
    List<DateTime> localTimes, {
    required bool sound,
  }) async {
    final keep = {for (final t in localTimes) reminderIdOf(t)};
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.payload == payload && !keep.contains(p.id)) {
        await _plugin.cancel(id: p.id);
      }
    }
    final details = NotificationDetails(
      android: sound ? _soundChannel : _silentChannel,
    );
    for (final t in localTimes) {
      await _plugin.zonedSchedule(
        id: reminderIdOf(t),
        title: title,
        body: body,
        scheduledDate: zonedTimeOf(t, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  @override
  Future<void> cancelDay(DateTime localDay) =>
      _plugin.cancel(id: reminderIdOf(localDay));
}
