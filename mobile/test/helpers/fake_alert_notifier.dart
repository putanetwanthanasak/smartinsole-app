import 'package:smartinsole/notify/alert_notifier.dart';

/// In-memory [AlertNotifier]: records what would be posted.
class FakeAlertNotifier implements AlertNotifier {
  /// The alert id this run was "launched" from, if any.
  int? launchedFrom;
  void Function(int alertId)? onTap;

  /// Posted notices, oldest first, with whether they used the sound channel.
  final shown = <(AlertNotice, bool)>[];

  @override
  Future<void> init({required void Function(int alertId) onTap}) async =>
      this.onTap = onTap;

  @override
  Future<int?> launchAlertId() async => launchedFrom;

  @override
  Future<void> show(AlertNotice notice, {required bool sound}) async =>
      shown.add((notice, sound));

  /// Cancelled alert ids, oldest first.
  final cancelled = <int>[];

  @override
  Future<void> cancel(int alertId) async => cancelled.add(alertId);
}
