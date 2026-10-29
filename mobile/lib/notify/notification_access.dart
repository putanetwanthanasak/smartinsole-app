import 'package:flutter/foundation.dart';

/// What the phone reports about this app posting notifications.
@immutable
class NotificationStatus {
  const NotificationStatus({
    required this.sdk,
    required this.enabled,
    required this.permissionGranted,
    required this.appOpAllowed,
  });

  /// Android API level.
  final int sdk;

  /// `NotificationManager.areNotificationsEnabled()`: the app's switch in
  /// the phone's settings (on Android 13+ it also follows the permission).
  final bool enabled;

  /// Android 13+ `POST_NOTIFICATIONS` granted; always true below 13,
  /// which has no such permission.
  final bool permissionGranted;

  /// The `POST_NOTIFICATION` app-op is not ignored. Checked on its own
  /// because a phone can block the app there alone (S8C: the Note 10 on
  /// Android 12 had the op on "ignore" and showed no warning).
  final bool appOpAllowed;

  /// Whether a notification would actually show.
  bool get canPost => enabled && permissionGranted && appOpAllowed;

  /// Whether the Android 13+ prompt can still fix it. Below 13 there is no
  /// prompt; only the app's notification settings can.
  bool get canPrompt => sdk >= 33 && !permissionGranted;

  @override
  String toString() =>
      'sdk=$sdk enabled=$enabled permission=$permissionGranted '
      'appOp=${appOpAllowed ? 'allowed' : 'ignored'}';
}

/// The phone side of [NotificationAccess].
abstract interface class NotificationPlatform {
  Future<NotificationStatus> status();

  /// Shows the Android 13+ prompt (the OS may skip it after two denials).
  Future<void> requestPermission();

  /// Opens the app's notification settings page.
  Future<void> openNotificationSettings();
}

/// Decides whether reminders can be shown, on every API level, from what
/// the phone reports rather than from the runtime permission alone.
class NotificationAccess {
  NotificationAccess(this._platform);

  final NotificationPlatform _platform;

  Future<bool> allowed() async {
    final s = await _platform.status();
    debugPrint(
      'reminder: notifications ${s.canPost ? 'allowed' : 'blocked'}'
      ' ($s)',
    );
    return s.canPost;
  }

  /// Shows the Android 13+ prompt when it can help; returns whether
  /// notifications are allowed afterwards. Below 13 it only re-checks:
  /// the caller then opens the notification settings.
  Future<bool> request() async {
    final s = await _platform.status();
    if (s.canPost) return true;
    if (s.canPrompt) await _platform.requestPermission();
    return allowed();
  }

  Future<void> openSettings() => _platform.openNotificationSettings();
}
