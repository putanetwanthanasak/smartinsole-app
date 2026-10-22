import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart';
import '../ble/insole_data_source.dart';
import '../ble/packets.dart';
import '../ui/clock.dart';
import 'device_manager.dart';
import 'display_snapshot.dart';
import 'mock_data_source.dart';

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
