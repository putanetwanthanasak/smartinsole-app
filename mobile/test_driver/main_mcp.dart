// Debug entrypoint for UI checks through the Dart MCP server: enables the
// Flutter Driver extension so the agent can tap and take screenshots.
// Lives outside lib/ so flutter_driver stays a dev dependency.
//
//   flutter run -d <emulator-id> -t test_driver/main_mcp.dart --print-dtd
//
// With --dart-define=BLE_FAKE=true the BLE stack is a scripted fake (the
// emulator has no usable Bluetooth): two insoles that stream at 6.25 Hz and
// one whose MTU is too small, so every Diagnostics state can be shown.
//
// S8B: --dart-define=BLE_SCENARIO=<name> picks the insoles for the
// Connection screen (§9) instead:
//   both       one left and one right insole
//   rightOnly  two right insoles: the left foot sees only the wrong side
//   none       nothing advertises: not found after 20 s
//   mtu23      a left insole with MTU 23 (connected, no data) + a right one
// The driver's request_data then changes the fake while the app runs:
//   bt-off / bt-on       the phone's Bluetooth
//   unplug-left / plug-left   the left insole stops / starts advertising
import 'package:flutter_driver/driver_extension.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/main.dart' as app;
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/storage_providers.dart';

import '../test/ble/fake_ble_central.dart';

const _bleFake = bool.fromEnvironment('BLE_FAKE');
const _scenario = String.fromEnvironment('BLE_SCENARIO');

const _left = '88:57:21:B7:74:9E';
const _right = '38:18:2B:8A:26:D6';

List<FakeInsole> _insoles() => switch (_scenario) {
  'both' => [
    FakeInsole(id: _left, name: 'SMARTINSOLE-L'),
    FakeInsole(id: _right, name: 'SMARTINSOLE-R', footSide: 1),
  ],
  'rightOnly' => [
    FakeInsole(id: _right, name: 'SMARTINSOLE-R', footSide: 1),
    FakeInsole(id: 'AA:BB:CC:00:00:02', name: 'SMARTINSOLE-R', footSide: 1),
  ],
  'none' => [],
  'mtu23' => [
    FakeInsole(id: _left, name: 'SMARTINSOLE-L', mtu: 23),
    FakeInsole(id: _right, name: 'SMARTINSOLE-R', footSide: 1),
  ],
  _ => [
    FakeInsole(id: _left, name: 'SMARTINSOLE-L'),
    FakeInsole(id: _right, name: 'SMARTINSOLE-R', footSide: 1),
    FakeInsole(id: 'AA:BB:CC:00:00:23', name: 'SMARTINSOLE-L', mtu: 23),
  ],
};

void main() {
  if (!_bleFake) {
    enableFlutterDriverExtension();
    app.main();
    return;
  }
  final central = FakeBleCentral(insoles: _insoles())
    ..autoStreamPeriod = const Duration(milliseconds: 160);
  enableFlutterDriverExtension(
    handler: (message) async {
      switch (message) {
        case 'bt-off':
          central.setAdapter(AdapterState.off);
        case 'bt-on':
          central.setAdapter(AdapterState.on);
        case 'unplug-left' || 'plug-left':
          final i = central.insoles[_left];
          if (i == null) return 'no left insole';
          i.advertising = message == 'plug-left';
          // Unplugged: a connected link drops too, like a board losing power.
          if (!i.advertising) i.link?.drop();
        default:
          return 'unknown: $message';
      }
      return 'ok';
    },
  );
  app.runSmartInsole(
    overrides: [
      bleCentralProvider.overrideWithValue(central),
      blePermissionsProvider.overrideWithValue(FakePermissions()),
      // Fake insoles' readings never go into the emulator's real file.
      databaseProvider.overrideWith((ref) {
        final db = AppDatabase.memory();
        ref.onDispose(db.close);
        return db;
      }),
    ],
  );
}
