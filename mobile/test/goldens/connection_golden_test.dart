@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/settings_store.dart';

import '../ble/fake_ble_central.dart';
import '../connection/connection_rig.dart';
import '../helpers/pump_app.dart';

/// Connection (DESIGN-SPEC §9), every card state, reached through the real
/// finder on a fake BLE stack. Boards: ConnectD (searching), ConnectDDone,
/// ConnectDWrong, ConnectDBtOff, ConnectDNotFound (not found + connected
/// without data). Regenerate:
///   flutter test --update-goldens test/goldens/connection_golden_test.dart
void main() {
  Future<void> expectScreen(String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
  );

  /// 100 %, 200 %, and the Note 10's 1.3 with "ใหญ่มาก" (≈ 1.88).
  final scales = [
    (suffix: '100', scale: 1.0, size: TextSizeOption.normal, h: 1100.0),
    (suffix: '200', scale: 2.0, size: TextSizeOption.normal, h: 2600.0),
    (suffix: '130xl', scale: 1.3, size: TextSizeOption.extraLarge, h: 2500.0),
  ];

  testWidgets('connect_not_connected_100', (tester) async {
    await pumpConnection(tester, size: const Size(390, 1100));
    await expectScreen('connect_not_connected_100');
    await unmount(tester);
  });

  for (final reduced in [false, true]) {
    final name = 'connect_searching${reduced ? '_reduced' : ''}_100';
    testWidgets(name, (tester) async {
      await pumpConnection(
        tester,
        reduceMotion: reduced,
        size: const Size(390, 1100),
      );
      await tapAndRun(
        tester,
        'connect-action-left',
        const Duration(milliseconds: 700),
      );
      await expectScreen(name);
      await unmount(tester);
    });
  }

  testWidgets('connect_connecting_100', (tester) async {
    // The mock spends 600 ms connecting, so the bar is reachable.
    await pumpConnection(
      tester,
      size: const Size(390, 1100),
      overrides: [mockPresetProvider.overrideWithValue(MockPreset.safe)],
    );
    await pumpFor(tester, const Duration(seconds: 2));
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 1));
    await tester.tap(byKey('connect-action-left'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await expectScreen('connect_connecting_100');
    await unmount(tester);
  });

  for (final s in scales) {
    testWidgets('connect_done_${s.suffix}', (tester) async {
      await pumpConnection(
        tester,
        insoles: [leftBoard(), rightBoard()],
        textScale: s.scale,
        size: Size(390, s.h),
        settings: MemorySettingsStore(
          settings: AppSettings(textSize: s.size),
        ),
      );
      await tapAndRun(
        tester,
        'connect-action-left',
        const Duration(seconds: 2),
      );
      await tapAndRun(
        tester,
        'connect-action-right',
        const Duration(seconds: 2),
      );
      await expectScreen('connect_done_${s.suffix}');
      await unmount(tester);
    });

    testWidgets('connect_not_found_${s.suffix}', (tester) async {
      final board = leftBoard(mtu: 23)..advertising = false;
      await pumpConnection(
        tester,
        insoles: [board],
        textScale: s.scale,
        size: Size(390, s.h),
        settings: MemorySettingsStore(
          settings: AppSettings(textSize: s.size),
        ),
      );
      await tapAndRun(
        tester,
        'connect-action-right',
        const Duration(seconds: 21),
      );
      board.advertising = true;
      await tapAndRun(
        tester,
        'connect-action-left',
        const Duration(seconds: 2),
      );
      await expectScreen('connect_not_found_${s.suffix}');
      await unmount(tester);
    });
  }

  testWidgets('connect_wrong_100', (tester) async {
    // Two right insoles: the right foot takes one, the left finds the other.
    await pumpConnection(
      tester,
      insoles: [rightBoard(), rightBoard(id: 'R2')],
      size: const Size(390, 1100),
    );
    await tapAndRun(tester, 'connect-action-right', const Duration(seconds: 2));
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 5));
    await expectScreen('connect_wrong_100');
    await unmount(tester);
  });

  testWidgets('connect_bt_off_100', (tester) async {
    final central = await pumpConnection(tester, size: const Size(390, 1100));
    central.setAdapter(AdapterState.off);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await expectScreen('connect_bt_off_100');
    await unmount(tester);
  });

  testWidgets('connect_permission_100', (tester) async {
    await pumpConnection(
      tester,
      permissions: FakePermissions(PermissionStatus.denied),
      size: const Size(390, 1100),
    );
    await expectScreen('connect_permission_100');
    await unmount(tester);
  });

  testWidgets('connect_low_battery_100', (tester) async {
    await pumpConnection(
      tester,
      insoles: [leftBoard()..batteryPct = 12, rightBoard()],
      size: const Size(390, 1100),
    );
    await tapAndRun(tester, 'connect-action-left', const Duration(seconds: 2));
    await expectScreen('connect_low_battery_100');
    await unmount(tester);
  });
}
