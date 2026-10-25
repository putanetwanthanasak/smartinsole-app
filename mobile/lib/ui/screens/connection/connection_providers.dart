import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/ble_providers.dart';
import '../../../ble/foot_connector.dart';
import '../../../ble/link_state.dart';
import '../../../ble/packets.dart';
import '../../../config/thresholds.dart';
import '../../../device/device_providers.dart';
import '../../../device/display_snapshot.dart';
import 'connection_model.dart';

/// [current] now, then every value on [changes]. Subscribes before reading
/// [current], so a change in between is never lost (an `async*` that yields
/// first and subscribes after can miss it).
Stream<T> _currentThen<T>(Ref ref, T Function() current, Stream<T> changes) {
  final out = StreamController<T>();
  final sub = changes.listen(out.add);
  out.add(current());
  ref.onDispose(() {
    sub.cancel();
    out.close();
  });
  return out.stream;
}

/// Whether the phone can do BLE: always ready with the mock.
final bleReadinessProvider = StreamProvider.autoDispose<BleReadiness>((ref) {
  if (ref.watch(mockInsolesProvider) != null) {
    return Stream.value(BleReadiness.ready);
  }
  final hub = ref.watch(bleHubProvider);
  return _currentThen(ref, () => hub.readiness, hub.readinessChanges);
});

final linkStateProvider = StreamProvider.autoDispose
    .family<LinkState, FootSide>((ref, side) {
      final source = ref.watch(insoleDataSourceProvider(side));
      return _currentThen(ref, () => source.state, source.states);
    });

final finderStateProvider = StreamProvider.autoDispose
    .family<FinderState, FootSide>((ref, side) {
      final connector = ref.watch(footConnectorProvider(side));
      return _currentThen(ref, () => connector.state, connector.states);
    });

/// One foot card (DESIGN-SPEC §9), recomputed from the 10 Hz snapshot so
/// a stale stream turns into "connected, no data" without a timer
/// (rule 2).
final footCardProvider = Provider.autoDispose.family<FootCardState, FootSide>((
  ref,
  side,
) {
  final readiness =
      ref.watch(bleReadinessProvider).value ?? BleReadiness.checking;
  final source = ref.watch(insoleDataSourceProvider(side));
  final connector = ref.watch(footConnectorProvider(side));
  final view =
      ref.watch(displaySnapshotProvider).value?.of(side) ??
      FootView(side: side, connection: FootConnection.notConnected);
  return cardStateOf(
    side: side,
    readiness: readiness,
    finder: ref.watch(finderStateProvider(side)).value ?? connector.state,
    link: ref.watch(linkStateProvider(side)).value ?? source.state,
    view: view,
    batteryLowPct: ref.watch(thresholdsProvider).batteryLowPct,
  );
});

final phonePanelProvider = Provider.autoDispose<PhonePanel>(
  (ref) =>
      panelOf(ref.watch(bleReadinessProvider).value ?? BleReadiness.checking),
);
