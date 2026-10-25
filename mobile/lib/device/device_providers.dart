import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ble/ble_providers.dart';
import '../ble/foot_connector.dart';
import '../ble/foot_finder.dart';
import '../ble/insole_data_source.dart';
import '../ble/packets.dart';
import '../settings/settings_providers.dart';
import '../ui/clock.dart';
import 'device_manager.dart';
import 'display_snapshot.dart';
import 'mock_connector.dart';
import 'mock_data_source.dart';
import 'timing_check.dart';

/// `--dart-define=MOCK=<preset>`; ignored in release builds.
const _mockDefine = String.fromEnvironment('MOCK');

/// The mock preset the app starts with, or null for real BLE. Tests and
/// the driver entrypoint override this.
final mockPresetProvider = Provider<MockPreset?>(
  (ref) => mockPresetFor(_mockDefine, debugBuild: kDebugMode),
);

/// Both mock insoles when a mock preset is active, else null.
final mockInsolesProvider = Provider<MockInsoles?>((ref) {
  final preset = ref.watch(mockPresetProvider);
  if (preset == null) return null;
  final mock = MockInsoles(preset, now: ref.watch(clockProvider));
  ref.onDispose(mock.dispose);
  return mock;
});

/// The data source of one foot: the mock in a mock-preset debug run, the
/// real BLE source otherwise.
final insoleDataSourceProvider = Provider.family<InsoleDataSource, FootSide>((
  ref,
  side,
) {
  final mock = ref.watch(mockInsolesProvider);
  if (mock != null) return mock.source(side);
  return ref.watch(insoleSourceProvider(side));
});

/// One foot's finder over BLE (S8B). Kept alive for the whole app, like
/// the source, so a search or the reconnect record survives leaving the
/// Connection screen. Remembers the insole in the settings store.
final footFinderProvider = Provider.family<FootFinder, FootSide>((ref, side) {
  final store = ref.watch(settingsStoreProvider);
  final finder = FootFinder(
    source: ref.watch(insoleSourceProvider(side)),
    hub: ref.watch(bleHubProvider),
    now: ref.watch(clockProvider),
    recall: () => store.boundInsole(side),
    remember: (id) => store.setBoundInsole(side, id),
  );
  ref.onDispose(finder.dispose);
  return finder;
});

/// What the Connection screen drives for one foot: the mock in a
/// mock-preset debug run, the BLE finder otherwise.
final footConnectorProvider = Provider.family<FootConnector, FootSide>((
  ref,
  side,
) {
  final mock = ref.watch(mockInsolesProvider);
  if (mock != null) return MockConnector(mock.source(side));
  return ref.watch(footFinderProvider(side));
});

/// At app start: reconnect the insoles remembered from last time (user
/// decision 2A, S8B). BLE only; the mock connects both feet on its own.
final autoConnectProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    if (ref.read(mockInsolesProvider) != null) return;
    for (final side in FootSide.values) {
      await ref.read(footFinderProvider(side)).autoConnect();
    }
  },
);

/// The one DeviceManager, alive for the whole app. With the mock, both feet
/// connect at once; with BLE, connecting is the user's action.
final deviceManagerProvider = Provider<DeviceManager>((ref) {
  final manager = DeviceManager(
    left: ref.watch(insoleDataSourceProvider(FootSide.left)),
    right: ref.watch(insoleDataSourceProvider(FootSide.right)),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(manager.dispose);
  if (ref.watch(mockInsolesProvider) != null) manager.connectAll();
  return manager;
});

/// The 10 Hz display path. Auto-disposed, so the ticker stops when no
/// screen watches it.
final displaySnapshotProvider = StreamProvider.autoDispose<DisplaySnapshot>(
  (ref) => ref.watch(deviceManagerProvider).snapshots,
);

/// The debug screen's timing check (S4 checkpoint). It logs the BLE
/// sources' `SYNC_TIME` writes, so it is meaningless with the mock.
final timingCheckProvider = Provider<TimingCheck>((ref) {
  final check = TimingCheck(
    manager: ref.watch(deviceManagerProvider),
    sources: {
      for (final side in FootSide.values)
        side: ref.watch(insoleSourceProvider(side)),
    },
    now: ref.watch(clockProvider),
    directory: getApplicationDocumentsDirectory,
  );
  ref.onDispose(check.stop);
  return check;
});
