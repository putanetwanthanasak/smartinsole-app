/// The evening reminder as the system notification it becomes. Only
/// `local_reminder_notifier.dart` imports the notification plugin; tests
/// use a fake.
abstract interface class ReminderNotifier {
  /// Sets up the plugin and its channels. [onTap] runs when the user taps
  /// a reminder while the app is running.
  Future<void> init({required void Function() onTap});

  /// Whether this run was started by tapping a reminder.
  Future<bool> launchedFromReminder();

  /// Whether the phone lets the app post notifications (Android 13+
  /// permission, or the app's switch in the phone's settings).
  Future<bool> enabled();

  /// Shows the Android 13+ prompt where the OS still allows it; returns
  /// whether notifications are allowed afterwards.
  Future<bool> request();

  /// Opens the app's notification settings page.
  Future<void> openSettings();

  /// Replaces every pending reminder with one at each of [localTimes]
  /// (wall-clock times in the phone's zone). [sound] false = the silent
  /// channel (Settings "เสียงแจ้งเตือน" off; user decision 2).
  Future<void> replaceAll(List<DateTime> localTimes, {required bool sound});

  /// Cancels the reminder of [localDay], also clearing it from the tray.
  Future<void> cancelDay(DateTime localDay);
}
