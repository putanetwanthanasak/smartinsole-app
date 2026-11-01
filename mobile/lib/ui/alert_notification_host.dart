import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notify/alert_notification_service.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

/// Foot alert notifications (S9), for the whole app. Draws nothing.
/// Starts the service; a tapped alert notification, or a launch from one,
/// opens that alert's detail over the "แจ้งเตือน" tab, so Back goes to
/// the Alerts list (user decision 6).
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
  }

  void _openAlert(int alertId) {
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
