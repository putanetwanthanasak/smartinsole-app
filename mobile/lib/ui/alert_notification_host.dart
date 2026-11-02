import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/capture_providers.dart';
import '../ble/packets.dart';
import '../device/device_providers.dart';
import '../device/foot_sample.dart';
import '../notify/alert_notification_service.dart';
import '../notify/reminder_providers.dart';
import '../settings/settings_providers.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

/// Foot alert notifications (S9), for the whole app. Draws nothing.
/// Starts the service; a tapped alert notification, or a launch from one,
/// opens that alert's detail over the "แจ้งเตือน" tab, so Back goes to
/// the Alerts list (user decision 6). Never while a research capture
/// session is open (DESIGN-SPEC §11.9). Asks for notifications once, the
/// first time both insoles stream (BACKLOG 73).
class AlertNotificationHost extends ConsumerStatefulWidget {
  const AlertNotificationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AlertNotificationHost> createState() =>
      _AlertNotificationHostState();
}

class _AlertNotificationHostState extends ConsumerState<AlertNotificationHost> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(alertNotificationServiceProvider).start(openAlert: _openAlert),
    );
    if (!ref.read(settingsStoreProvider).connectPromptShown) {
      _batches = ref.read(deviceManagerProvider).batches.listen(_onBatch);
    }
  }

  @override
  void dispose() {
    _batches?.cancel();
    super.dispose();
  }

  StreamSubscription<FootBatch>? _batches;
  final _lastBatchAt = <FootSide, DateTime>{};
  var _asking = false;

  /// Asks for notifications once, while both insoles stream (user decision
  /// 2026-11-02, BACKLOG 73): foot alerts would otherwise be asked for
  /// only from "ตรวจเท้า" or the reminder switch. Both stream when each
  /// foot's newest batch arrived within `staleAfter` of the other's
  /// (arrival times, rule 3; no timer). Not while a research capture
  /// session is open: it then asks once the session is closed, if both
  /// still stream. Not when notifications already show (as
  /// `FootCheckHost._askOnce`). Never opens the phone's settings.
  void _onBatch(FootBatch b) {
    _lastBatchAt[b.side] = b.receivedAt;
    if (_asking || _lastBatchAt.length < FootSide.values.length) return;
    final staleAfter = ref.read(deviceManagerProvider).staleAfter;
    final (l, r) = (
      _lastBatchAt[FootSide.left]!,
      _lastBatchAt[FootSide.right]!,
    );
    if (l.difference(r).abs() >= staleAfter) return;
    if (ref.read(activeCaptureProvider) != null) return;
    _asking = true;
    unawaited(_askOnConnect());
  }

  Future<void> _askOnConnect() async {
    final store = ref.read(settingsStoreProvider);
    final allowed = ref.read(notificationsAllowedProvider.notifier);
    try {
      if (!store.connectPromptShown &&
          !await ref.read(reminderNotifierProvider).enabled() &&
          mounted &&
          ref.read(activeCaptureProvider) == null) {
        await store.setConnectPromptShown();
        await allowed.request();
      }
    } catch (e) {
      debugPrint('alerts: notification ask failed: $e');
    }
    // Settled for this run (a capture that opened meanwhile: next run).
    await _batches?.cancel();
    _batches = null;
  }

  void _openAlert(int alertId) {
    // A research capture session is open: navigate nowhere. Popping its
    // screen would end a running trial as interrupted (only the 2 s hold
    // buttons may stop one); the alert waits in the Alerts list.
    if (ref.read(activeCaptureProvider) != null) {
      debugPrint('alerts: tap on #$alertId ignored during a capture');
      return;
    }
    ref.read(selectedTabProvider.notifier).select(AppTab.alerts);
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav
      ..popUntil((r) => r.isFirst)
      ..pushNamed(Routes.alertDetail, arguments: alertId);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(alertNotificationServiceProvider);
    return widget.child;
  }
}
