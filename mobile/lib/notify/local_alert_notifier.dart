import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_notifier.dart';
import '../ui/theme/colors.dart';
import 'android_resources.dart';
import 'local_notifications.dart';

/// [AlertNotifier] on `flutter_local_notifications`, sharing the plugin
/// with the reminder ([LocalNotifications]). Posted at once, high
/// importance; the lock screen hides the text (`private`).
class LocalAlertNotifier implements AlertNotifier {
  final _shared = LocalNotifications.instance;

  // A channel's sound is fixed once created, so the silent alerts have
  // their own channel (as the reminder's). Names are what the phone's
  // settings show (draft). Both are created in init().
  static const _soundChannel = AndroidNotificationChannel(
    'foot_alert',
    'แจ้งเตือนเรื่องเท้า',
    description: 'เมื่อแอปพบสิ่งที่ควรดูแลเรื่องเท้า',
    importance: Importance.high,
  );
  static const _silentChannel = AndroidNotificationChannel(
    'foot_alert_silent',
    'แจ้งเตือนเรื่องเท้า (ไม่มีเสียง)',
    description: 'เมื่อแอปพบสิ่งที่ควรดูแลเรื่องเท้า แบบไม่มีเสียง',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );

  static NotificationDetails _detailsOf(
    AndroidNotificationChannel c,
    String body,
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      c.id,
      c.name,
      channelDescription: c.description,
      importance: c.importance,
      priority: Priority.high,
      playSound: c.playSound,
      enableVibration: c.enableVibration,
      icon: AndroidResources.alertIcon,
      color: AppColors.primary,
      visibility: NotificationVisibility.private,
      styleInformation: BigTextStyleInformation(body),
    ),
  );

  @override
  Future<void> init({required void Function(int alertId) onTap}) async {
    await _shared.init('alerts', (p) {
      final id = alertIdOfPayload(p);
      if (id == null) return false;
      onTap(id);
      return true;
    });
    await _shared.android?.createNotificationChannel(_soundChannel);
    await _shared.android?.createNotificationChannel(_silentChannel);
  }

  @override
  Future<int?> launchAlertId() async =>
      alertIdOfPayload(await _shared.launchPayload());

  @override
  Future<void> show(AlertNotice notice, {required bool sound}) =>
      _shared.plugin.show(
        id: notice.alertId,
        title: notice.title,
        body: notice.body,
        notificationDetails: _detailsOf(
          sound ? _soundChannel : _silentChannel,
          notice.body,
        ),
        payload: alertPayloadOf(notice.alertId),
      );

  @override
  Future<void> cancel(int alertId) => _shared.plugin.cancel(id: alertId);
}
