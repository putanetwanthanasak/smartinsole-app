@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/debug_ble_screen.dart';

import '../ble/fake_ble_central.dart';
import '../helpers/pump_app.dart';

/// One golden per BLE debug screen state (S3A). Taller than the reference
/// screen so every card is in the picture. Regenerate with:
///   flutter test --update-goldens test/goldens
const _size = Size(390, 2000);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeBleCentral central, {
  FakePermissions? permissions,
}) async {
  await pumpApp(
    tester,
    initialRoute: Routes.bleDebug,
    central: central,
    permissions: permissions,
    size: _size,
    settle: false,
  );
  await _pump(tester);
  return ProviderScope.containerOf(tester.element(find.byType(DebugBleScreen)));
}

Future<void> _connect(
  WidgetTester tester,
  ProviderContainer c,
  FootSide side,
  String id,
) async {
  c.read(insoleSourceProvider(side)).connectTo(id, name: 'SMARTINSOLE-?');
  await _pump(tester);
}

Future<void> _expect(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('screens/ble_debug_$name.png'),
);

void main() {
  testWidgets('streaming', (tester) async {
    final central = FakeBleCentral(
      insoles: [
        FakeInsole(id: '88:57:21:B7:74:9E', name: 'SMARTINSOLE-L'),
        FakeInsole(id: '38:18:2B:8A:26:D6', name: 'SMARTINSOLE-R', footSide: 1),
      ],
    );
    final c = await _open(tester, central);
    await _connect(tester, c, FootSide.left, '88:57:21:B7:74:9E');
    await _connect(tester, c, FootSide.right, '38:18:2B:8A:26:D6');
    for (final insole in central.insoles.values) {
      for (var i = 0; i < 3; i++) {
        insole.link!.sendSensor();
      }
      insole.link!.sendTemp();
    }
    await _pump(tester);
    await _expect('streaming');
  });

  testWidgets('problems', (tester) async {
    final central = FakeBleCentral(
      insoles: [
        FakeInsole(id: 'R1', name: 'SMARTINSOLE-L', footSide: 1),
        FakeInsole(id: 'R2', name: 'SMARTINSOLE-R', footSide: 1, mtu: 23),
      ],
    );
    final c = await _open(tester, central);
    await _connect(tester, c, FootSide.left, 'R1');
    await _connect(tester, c, FootSide.right, 'R2');
    await _expect('problems');
  });

  testWidgets('retry and searching', (tester) async {
    final central = FakeBleCentral(
      insoles: [
        FakeInsole(id: 'L1')..failConnects = 99,
        FakeInsole(id: 'R1', footSide: 1, advertising: false),
      ],
    );
    final c = await _open(tester, central);
    await _connect(tester, c, FootSide.left, 'L1');
    await _connect(tester, c, FootSide.right, 'R1');
    await _expect('retry');
  });

  testWidgets('needs permission', (tester) async {
    await _open(
      tester,
      FakeBleCentral(),
      permissions: FakePermissions(PermissionStatus.denied),
    );
    await _expect('permission');
  });

  testWidgets('Bluetooth off', (tester) async {
    final central = FakeBleCentral()..adapterNow = AdapterState.off;
    final c = await _open(tester, central);
    central.add(FakeInsole(id: 'L1'));
    await _connect(tester, c, FootSide.left, 'L1');
    await _expect('bluetooth_off');
  });
}
