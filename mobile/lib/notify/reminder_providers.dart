import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../footcheck/footcheck_providers.dart';
import '../settings/settings_providers.dart';
import '../storage/storage_providers.dart';
import '../ui/clock.dart';
import 'local_reminder_notifier.dart';
import 'reminder_notifier.dart';
import 'reminder_plan.dart';

/// The system notification. Tests and goldens override it with a fake.
final reminderNotifierProvider = Provider<ReminderNotifier>(
  (ref) => LocalReminderNotifier(),
);

/// Whether the phone lets the app post notifications. Refreshed on resume
/// (the user may have changed it in the phone's settings) and after a
/// request.
final notificationsAllowedProvider =
    AsyncNotifierProvider<NotificationsAllowed, bool>(NotificationsAllowed.new);

class NotificationsAllowed extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(reminderNotifierProvider).enabled();

  Future<void> refresh() async {
    final v = await ref.read(reminderNotifierProvider).enabled();
    if (state.value != v) state = AsyncData(v);
  }

  /// Shows the system prompt where allowed; if that still leaves
  /// notifications off, opens the app's notification settings when
  /// [openSettingsIfStillOff].
  Future<bool> request({bool openSettingsIfStillOff = false}) async {
    final n = ref.read(reminderNotifierProvider);
    final ok = await n.request();
    state = AsyncData(ok);
    if (!ok && openSettingsIfStillOff) await n.openSettings();
    return ok;
  }
}

/// Keeps the evening reminders in step with Settings and today's check
/// (user decision 2): rescheduled at start, after a save, and when the
/// switch, time or sound changes. Started by `FootCheckHost`.
final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(ref);
  ref.listen(
    settingsProvider.select(
      (s) => (s.footCheckReminder, s.reminderTime, s.sound),
    ),
    (_, _) => service.sync(),
  );
  ref.listen(todayCheckProvider, (_, _) => service.sync());
  return service;
});

class ReminderService {
  ReminderService(this._ref);

  final Ref _ref;
  var _started = false;
  Future<void> _last = Future.value();

  /// Sets up the notification plugin. [openTab] runs for a tap on a
  /// reminder, or once now when this run was started by one.
  Future<void> start({required void Function() openTab}) async {
    final n = _ref.read(reminderNotifierProvider);
    await n.init(onTap: openTab);
    if (!_ref.mounted) return;
    if (await n.launchedFromReminder()) openTab();
    _started = true;
    await sync();
  }

  /// Recomputes and replaces the pending reminders. Calls run one after
  /// another, so the last one always wins.
  Future<void> sync() {
    if (!_started || !_ref.mounted) return Future.value();
    return _last = _last.then((_) => _sync()).catchError((Object e) {
      debugPrint('reminder: sync failed: $e');
    });
  }

  Future<void> _sync() async {
    // The app (or a test's provider scope) may have gone meanwhile.
    if (!_ref.mounted) return;
    final s = _ref.read(settingsProvider);
    final now = _ref.read(clockProvider)();
    final today = _ref.read(localDatesProvider).of(now.millisecondsSinceEpoch);
    final done =
        await _ref
            .read(footCheckRepositoryProvider)
            .watchLatestOn(today)
            .first !=
        null;
    final n = _ref.read(reminderNotifierProvider);
    await n.replaceAll(
      reminderTimes(
        now: now,
        enabled: s.footCheckReminder,
        hour: s.reminderTime.hour,
        minute: s.reminderTime.minute,
        todayDone: done,
      ),
      sound: s.sound,
    );
    // Also clears a reminder already shown today from the tray.
    if (done) await n.cancelDay(now);
  }
}
