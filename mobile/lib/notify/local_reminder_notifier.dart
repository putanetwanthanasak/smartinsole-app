import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import 'android_resources.dart';
import 'notification_access.dart';
import 'reminder_notifier.dart';
import 'reminder_plan.dart';
import 'time_zone.dart';

/// [ReminderNotifier] on `flutter_local_notifications`: one-shot inexact
/// notifications (`inexactAllowWhileIdle`, no exact-alarm permission; a
/// few minutes late is fine), restored after a reboot by the plugin's boot
/// receiver (manifest). Text has no health details (user decision 2).
class LocalReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  late final _access = NotificationAccess(_PhoneNotifications(this));

  static const payload = 'foot-check-reminder';
  static const title = 'ถึงเวลาดูเท้าประจำวัน';
  static const body = 'ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที';

  // A channel's sound is fixed once created, so the silent reminder has
  // its own channel. Names are what the phone's settings show (draft).
  // Both are created in init(), so the phone's settings list them before
  // the first reminder (the plugin otherwise creates a channel only when
  // it first posts to it).
  static const _soundChannel = AndroidNotificationChannel(
    'foot_check_reminder',
    'เตือนให้ดูเท้า',
    description: 'เตือนตอนเย็นถ้าวันนี้ยังไม่ได้ดูเท้า',
    importance: Importance.high,
  );
  static const _silentChannel = AndroidNotificationChannel(
    'foot_check_reminder_silent',
    'เตือนให้ดูเท้า (ไม่มีเสียง)',
    description: 'เตือนตอนเย็นแบบไม่มีเสียง',
    playSound: false,
    enableVibration: false,
  );

  static AndroidNotificationDetails _detailsOf(AndroidNotificationChannel c) =>
      AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: c.importance == Importance.high
            ? Priority.high
            : Priority.defaultPriority,
        playSound: c.playSound,
        enableVibration: c.enableVibration,
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
    await _android?.createNotificationChannel(_soundChannel);
    await _android?.createNotificationChannel(_silentChannel);
  }

  @override
  Future<bool> launchedFromReminder() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false) &&
        d?.notificationResponse?.payload == payload;
  }

  @override
  Future<bool> enabled() => _access.allowed();

  @override
  Future<bool> request() => _access.request();

  @override
  Future<void> openSettings() => _access.openSettings();

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
      android: _detailsOf(sound ? _soundChannel : _silentChannel),
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

/// [NotificationPlatform] on the phone: the status and the settings page
/// come from MainActivity's "smartinsole/notifications" channel, the
/// Android 13+ prompt from the plugin.
class _PhoneNotifications implements NotificationPlatform {
  _PhoneNotifications(this._notifier);

  final LocalReminderNotifier _notifier;
  static const _channel = MethodChannel('smartinsole/notifications');

  @override
  Future<NotificationStatus> status() async {
    final m = await _channel.invokeMapMethod<String, Object?>('status');
    return NotificationStatus(
      sdk: m?['sdk'] as int? ?? 0,
      enabled: m?['enabled'] as bool? ?? false,
      permissionGranted: m?['permission'] as bool? ?? false,
      appOpAllowed: m?['appOpAllowed'] as bool? ?? false,
    );
  }

  @override
  Future<void> requestPermission() async =>
      _notifier._android?.requestNotificationsPermission();

  @override
  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openSettings');
}
