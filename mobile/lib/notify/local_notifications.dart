import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'android_resources.dart';

/// The one `FlutterLocalNotificationsPlugin` (the plugin is a singleton,
/// and `initialize` keeps only the last tap callback). The reminder and
/// the alert notifications (S9) each register a tap handler by name; the
/// plugin is initialized once and every tap goes to the handler that
/// claims its payload.
class LocalNotifications {
  LocalNotifications._();

  static final instance = LocalNotifications._();

  final plugin = FlutterLocalNotificationsPlugin();
  final _handlers = <String, bool Function(String? payload)>{};
  Future<void>? _initialized;

  AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Registers (or replaces) the tap handler [name] and initializes the
  /// plugin once. A handler returns whether it took the payload.
  Future<void> init(String name, bool Function(String? payload) onTap) {
    _handlers[name] = onTap;
    return _initialized ??= plugin
        .initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings(
              AndroidResources.reminderIcon,
            ),
          ),
          onDidReceiveNotificationResponse: (r) {
            for (final h in _handlers.values) {
              if (h(r.payload)) return;
            }
          },
        )
        .then((_) {});
  }

  /// The payload of the notification whose tap started this run, if one
  /// did.
  Future<String?> launchPayload() async {
    final d = await plugin.getNotificationAppLaunchDetails();
    if (!(d?.didNotificationLaunchApp ?? false)) return null;
    return d?.notificationResponse?.payload;
  }
}
