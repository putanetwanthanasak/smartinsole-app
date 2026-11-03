import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/capture_providers.dart';
import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../rules/alert_code.dart';
import '../rules/alert_copy.dart';
import '../rules/alert_engine.dart';
import '../rules/alert_providers.dart';
import '../settings/settings_providers.dart';
import '../storage/storage_providers.dart';
import 'alert_notifier.dart';
import 'local_alert_notifier.dart';
import 'quiet_window.dart';

/// The codes that become a system notification (user decision 4,
/// 2026-11-01): the foot alerts a patient should act on. The others stay
/// in the app only.
const notifiedCodes = {
  AlertCode.tempDelta,
  AlertCode.pressurePeak,
  AlertCode.pressurePti,
  AlertCode.loadConcentration,
};

/// The notification for [r], or null when it gets none: a code outside
/// [notifiedCodes], or raised during a research capture (its capture
/// stamp, or [capturing] now; user decision 5: the alert is still stored,
/// tagged and shown on the session screen). The text is the alert's own
/// title and "ควรทำ" line (`alert_copy.dart`, draft), so the notification
/// says what the Alerts list says.
AlertNotice? noticeFor(RaisedAlert r, {required bool capturing}) {
  final a = r.alert;
  final code = a.kind.code;
  if (code == null || !notifiedCodes.contains(code)) return null;
  if (capturing || a.captureStamp != null) return null;
  final side = a.side;
  if (side == null) return null;
  final zone = a.zone;
  final i = zone == null
      ? -1
      : footLayout.zones.indexWhere((z) => z.id == zone);
  final copy = alertCopyFor(
    code,
    side: side,
    channel: i < 0 ? null : i,
    value: a.measuredValue,
    threshold: a.threshold,
  );
  return AlertNotice(alertId: r.id, title: copy.title, body: copy.todo);
}

/// Each new alert once stored (`AlertEngine.raised`); tests feed their own.
final raisedAlertsProvider = Provider<Stream<RaisedAlert>>(
  (ref) => ref.watch(alertEngineProvider).raised,
);

/// The system notification. Tests and goldens override it with a fake.
final alertNotifierProvider = Provider<AlertNotifier>(
  (ref) => LocalAlertNotifier(),
);

/// Posts a notification for each new foot alert ([noticeFor]), on the
/// sound or silent channel by Settings "เสียงแจ้งเตือน" (user decision 7),
/// also while the app is on screen (decision 8). With sound on, one within
/// `alerts.quietNotifyMin` of the last sounded one for the same foot goes
/// on the silent channel ([NotificationQuietWindow], BACKLOG 76). Started
/// by `AlertNotificationHost`.
final alertNotificationServiceProvider = Provider<AlertNotificationService>((
  ref,
) {
  final service = AlertNotificationService(ref);
  ref.onDispose(service.stop);
  return service;
});

class AlertNotificationService {
  AlertNotificationService(this._ref)
    : _quiet = NotificationQuietWindow(
        Duration(minutes: _ref.read(thresholdsProvider).quietNotifyMin),
      );

  final Ref _ref;
  final NotificationQuietWindow _quiet;
  StreamSubscription<RaisedAlert>? _sub;

  /// Sets up the notifications and starts posting. [openAlert] runs for a
  /// tap on an alert notification, or once now when this run was started
  /// by one.
  Future<void> start({required void Function(int alertId) openAlert}) async {
    // Listen first: an alert raised while the plugin sets up still posts
    // (show waits for init below).
    _sub ??= _ref.read(raisedAlertsProvider).listen(_post);
    final n = _ref.read(alertNotifierProvider);
    await (_ready = n.init(onTap: openAlert));
    if (!_ref.mounted) return;
    final launched = await n.launchAlertId();
    if (launched != null) openAlert(launched);
  }

  Future<void>? _ready;

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Marks alert [alertId] read at [atMs] and takes its notification out
  /// of the tray, so the launcher badge and the in-app bell agree (S9-2
  /// checkpoint item 8: Android keeps a notification until it is tapped or
  /// cancelled). Every place that marks an alert read goes through here.
  Future<void> markRead(int alertId, int atMs) async {
    await _ref.read(alertRepositoryProvider).markRead(alertId, atMs);
    if (!_ref.mounted) return;
    try {
      await _ready;
      if (!_ref.mounted) return;
      await _ref.read(alertNotifierProvider).cancel(alertId);
    } catch (e) {
      debugPrint('alerts: cancel #$alertId failed: $e');
    }
  }

  Future<void> _post(RaisedAlert r) async {
    if (!_ref.mounted) return;
    final notice = noticeFor(
      r,
      capturing: _ref.read(activeCaptureProvider) != null,
    );
    if (notice == null) return;
    // Decided before any await, so alerts arriving together are judged in
    // the order they were raised. noticeFor only returns a notice for an
    // alert with a side.
    final sound =
        _ref.read(settingsProvider).sound &&
        _quiet.claimSound(r.alert.side!, r.alert.atMs);
    try {
      await _ready;
      if (!_ref.mounted) return;
      await _ref.read(alertNotifierProvider).show(notice, sound: sound);
      debugPrint(
        'alerts: notified ${r.alert.kind.code?.name} #${r.id} '
        '(${sound ? 'sound' : 'silent'})',
      );
    } catch (e) {
      // Nothing sounded, so the next alert for this foot may (§11.9).
      if (sound) _quiet.release(r.alert.side!, r.alert.atMs);
      debugPrint('alerts: notification failed: $e');
    }
  }
}
