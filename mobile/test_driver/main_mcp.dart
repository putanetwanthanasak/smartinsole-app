// Debug entrypoint for UI checks through the Dart MCP server: enables the
// Flutter Driver extension so the agent can tap and take screenshots.
// Lives outside lib/ so flutter_driver stays a dev dependency.
//
//   flutter run -d <emulator-id> -t test_driver/main_mcp.dart --print-dtd
//
// With --dart-define=BLE_FAKE=true the BLE stack is a scripted fake (the
// emulator has no usable Bluetooth): two insoles that stream at 6.25 Hz and
// one whose MTU is too small, so every BLE debug screen state can be shown.
import 'package:flutter_driver/driver_extension.dart';
import 'package:smartinsole/ble/ble_providers.dart';
import 'package:smartinsole/main.dart' as app;
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/storage_providers.dart';

import '../test/ble/fake_ble_central.dart';

const _bleFake = bool.fromEnvironment('BLE_FAKE');

void main() {
  enableFlutterDriverExtension();
  if (!_bleFake) {
    app.main();
    return;
  }
  final central = FakeBleCentral(
    insoles: [
      FakeInsole(id: '88:57:21:B7:74:9E', name: 'SMARTINSOLE-L'),
      FakeInsole(id: '38:18:2B:8A:26:D6', name: 'SMARTINSOLE-R', footSide: 1),
      FakeInsole(id: 'AA:BB:CC:00:00:23', name: 'SMARTINSOLE-L', mtu: 23),
    ],
  )..autoStreamPeriod = const Duration(milliseconds: 160);
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
