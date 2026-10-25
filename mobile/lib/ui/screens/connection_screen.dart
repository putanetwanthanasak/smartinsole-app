import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/ble_hub.dart';
import '../../ble/ble_providers.dart';
import '../../ble/packets.dart';
import '../../device/device_providers.dart';
import '../shell/app_shell.dart';
import '../theme/dimens.dart';
import '../widgets/back_link.dart';
import '../widgets/info_box.dart';
import '../widgets/page_title.dart';
import 'connection/connection_model.dart';
import 'connection/connection_providers.dart';
import 'connection/connection_widgets.dart';

/// Connection (DESIGN-SPEC §9): one card per foot, each connected on its
/// own (S8B). A patient connects both insoles here, with no scan list:
/// "เชื่อมต่อเท้าซ้าย" finds the insole that reports the left foot
/// (`FootFinder`, rule 8).
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  late final AppLifecycleListener _lifecycle;

  /// False on the first frame, so a foot already connected when the
  /// screen opens shows its end state instead of popping (§12: once per
  /// real event).
  bool _live = false;

  @override
  void initState() {
    super.initState();
    final mock = ref.read(mockInsolesProvider) != null;
    if (!mock) {
      // Reads the permission and the adapter, so the Bluetooth panel shows
      // at once. Asks for the permission if it was never asked.
      unawaited(ref.read(bleHubProvider).start());
    }
    // Back from the system settings page: the permission may have changed.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!mock) unawaited(ref.read(bleHubProvider).recheckPermission());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _live = true);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(phonePanelProvider);
    final left = ref.watch(footCardProvider(FootSide.left));
    final right = ref.watch(footCardProvider(FootSide.right));
    final done = bothConnected(left, right);
    // Only read in callbacks: the mock never shows a panel, and must not
    // create the real BLE stack.
    BleHub hub() => ref.read(bleHubProvider);

    Widget card(FootCardState c) {
      final connector = ref.read(footConnectorProvider(c.side));
      return FootConnectionCard(
        card: c,
        onFind: () => unawaited(connector.find()),
        onStop: () => unawaited(connector.stop()),
        onDisconnect: () => unawaited(connector.disconnect()),
        onReconnect: () => unawaited(connector.reconnect()),
      );
    }

    final sections = <Widget>[
      const PageTitle(ConnectionCopy.title, subtitle: ConnectionCopy.subtitle),
      if (panel == PhonePanel.bluetoothOff)
        PhonePanelView(
          key: const ValueKey('bt-off-panel'),
          title: ConnectionCopy.btOffTitle,
          line: ConnectionCopy.btOffLine,
          button: ConnectionCopy.btOffButton,
          buttonIcon: LucideIcons.bluetooth,
          onPressed: () => unawaited(hub().turnOnBluetooth()),
        )
      else if (panel == PhonePanel.permission ||
          panel == PhonePanel.permissionSettings)
        PhonePanelView(
          key: const ValueKey('permission-panel'),
          title: ConnectionCopy.permissionTitle,
          line: ConnectionCopy.permissionLine,
          button: panel == PhonePanel.permission
              ? ConnectionCopy.permissionButton
              : ConnectionCopy.permissionSettingsButton,
          buttonIcon: null,
          onPressed: () => unawaited(
            panel == PhonePanel.permission
                ? hub().requestPermission()
                : hub().openSettings(),
          ),
        ),
      if (showInfoBox(panel, left, right))
        const InfoBox(key: ValueKey('connect-info'), text: ConnectionCopy.info),
      card(left),
      card(right),
      if (done)
        DoneButton(
          onPressed: () {
            ref.read(selectedTabProvider.notifier).select(AppTab.today);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: ConnectedEntrance(
          animate: _live,
          child: ListView(
            key: const ValueKey('connection-scroll'),
            padding: const EdgeInsets.fromLTRB(
              Dimens.pagePadding,
              Dimens.pageTopPushed,
              Dimens.pagePadding,
              Dimens.pageBottomPushed,
            ),
            children: [
              const BackLink(),
              const SizedBox(height: Dimens.tightGap),
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const SizedBox(height: Dimens.cardGap),
                sections[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
