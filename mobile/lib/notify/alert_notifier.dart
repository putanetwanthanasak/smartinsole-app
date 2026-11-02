/// One foot alert as the system notification it becomes (S9).
class AlertNotice {
  const AlertNotice({
    required this.alertId,
    required this.title,
    required this.body,
  });

  /// The alert's row id: the notification id and its tap payload.
  final int alertId;

  /// The alert's title and its "ควรทำ" line (`alert_copy.dart`, draft).
  final String title;
  final String body;
}

/// Foot alerts as system notifications (S9, user decisions 4–8). Only
/// `local_alert_notifier.dart` imports the notification plugin; tests use
/// a fake.
abstract interface class AlertNotifier {
  /// Sets up the plugin (shared with the reminder) and creates both alert
  /// channels. [onTap] gets the alert id when the user taps an alert
  /// notification while the app is running.
  Future<void> init({required void Function(int alertId) onTap});

  /// The alert id when this run was started by tapping an alert
  /// notification.
  Future<int?> launchAlertId();

  /// Posts [notice]. [sound] false = the silent channel (Settings
  /// "เสียงแจ้งเตือน" off).
  Future<void> show(AlertNotice notice, {required bool sound});

  /// Removes alert [alertId]'s notification from the tray, if it is there
  /// (the launcher badge counts what is in the tray).
  Future<void> cancel(int alertId);
}

/// The payload of alert [id]'s notification, and back.
String alertPayloadOf(int id) => 'alert:$id';

int? alertIdOfPayload(String? payload) {
  const prefix = 'alert:';
  if (payload == null || !payload.startsWith(prefix)) return null;
  return int.tryParse(payload.substring(prefix.length));
}
