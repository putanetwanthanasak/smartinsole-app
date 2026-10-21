import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/clock.dart';
import 'ble_central.dart';
import 'ble_data_source.dart';
import 'ble_event_log.dart';
import 'ble_hub.dart';
import 'fbp_central.dart';
import 'handler_permissions.dart';
import 'packets.dart';

/// The phone's BLE stack. Tests and the emulator run override this with a
/// fake (`test/ble/fake_ble_central.dart`).
final bleCentralProvider = Provider<BleCentral>((ref) {
  final central = FbpCentral();
  ref.onDispose(central.dispose);
  return central;
});

final blePermissionsProvider = Provider<BlePermissions>(
  (ref) => HandlerPermissions(),
);

final bleLogProvider = Provider<BleEventLog>(
  (ref) => BleEventLog(now: ref.watch(clockProvider)),
);

final bleHubProvider = Provider<BleHub>((ref) {
  final hub = BleHub(
    central: ref.watch(bleCentralProvider),
    permissions: ref.watch(blePermissionsProvider),
    now: ref.watch(clockProvider),
    log: ref.watch(bleLogProvider),
  );
  ref.onDispose(hub.dispose);
  return hub;
});

/// One source per foot. Kept alive for the whole app, so leaving the debug
/// screen does not disconnect anything.
final insoleSourceProvider = Provider.family<BleDataSource, FootSide>((
  ref,
  side,
) {
  final source = BleDataSource(
    side: side,
    hub: ref.watch(bleHubProvider),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(source.dispose);
  return source;
});
