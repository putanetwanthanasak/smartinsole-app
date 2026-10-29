import 'package:smartinsole/notify/reminder_notifier.dart';

/// In-memory [ReminderNotifier]: records what would be scheduled.
class FakeReminderNotifier implements ReminderNotifier {
  FakeReminderNotifier({this.allowed = true, this.grantOnRequest = true});

  bool allowed;
  bool grantOnRequest;
  bool launched = false;
  var requests = 0;
  var settingsOpened = 0;
  void Function()? onTap;

  /// Pending reminders: local time → with sound.
  final pending = <DateTime, bool>{};
  final cancelledDays = <DateTime>[];

  @override
  Future<void> init({required void Function() onTap}) async =>
      this.onTap = onTap;

  @override
  Future<bool> launchedFromReminder() async => launched;

  @override
  Future<bool> enabled() async => allowed;

  @override
  Future<bool> request() async {
    requests++;
    if (grantOnRequest) allowed = true;
    return allowed;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> replaceAll(
    List<DateTime> localTimes, {
    required bool sound,
  }) async {
    pending
      ..clear()
      ..addAll({for (final t in localTimes) t: sound});
  }

  @override
  Future<void> cancelDay(DateTime localDay) async {
    cancelledDays.add(localDay);
    pending.removeWhere(
      (t, _) =>
          t.year == localDay.year &&
          t.month == localDay.month &&
          t.day == localDay.day,
    );
  }
}
