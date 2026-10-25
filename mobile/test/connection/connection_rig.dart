import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/ui/routes.dart';

import '../ble/fake_ble_central.dart';
import '../helpers/pump_app.dart';

FakeInsole leftBoard({int mtu = 247, String id = 'L1'}) =>
    FakeInsole(id: id, name: 'SMARTINSOLE-L', footSide: 0, mtu: mtu);

FakeInsole rightBoard({String id = 'R1'}) =>
    FakeInsole(id: id, name: 'SMARTINSOLE-R', footSide: 1);

/// Opens Connection on a [FakeBleCentral] with [insoles], under fake time
/// that moves the wall clock (so staleness and the 10 Hz snapshot work).
/// Streaming insoles send a packet every 160 ms, like a board.
Future<FakeBleCentral> pumpConnection(
  WidgetTester tester, {
  List<FakeInsole> insoles = const [],
  FakePermissions? permissions,
  double textScale = 1.0,
  bool reduceMotion = false,
  Size size = referenceSize,
  SettingsStore? settings,
  List<Override> overrides = const [],
}) async {
  final central = FakeBleCentral(insoles: insoles)
    ..autoStreamPeriod = const Duration(milliseconds: 160);
  await pumpApp(
    tester,
    initialRoute: Routes.connection,
    central: central,
    permissions: permissions,
    now: fakeTimeClock(tester),
    textScale: textScale,
    reduceMotion: reduceMotion,
    size: size,
    settings: settings,
    settle: false,
    overrides: overrides,
  );
  await pumpFor(tester, const Duration(milliseconds: 500));
  return central;
}

/// Lets [d] of fake time pass in 100 ms steps (BLE, the 10 Hz snapshot and
/// the animations interleave as on a phone).
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < d; t += step) {
    await tester.pump(step);
  }
}

Future<void> tapAndRun(WidgetTester tester, String key, Duration d) async {
  await tester.ensureVisible(byKey(key));
  await tester.tap(byKey(key));
  await pumpFor(tester, d);
}

/// Disposes the app (and with it every BLE timer) before the test ends.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
