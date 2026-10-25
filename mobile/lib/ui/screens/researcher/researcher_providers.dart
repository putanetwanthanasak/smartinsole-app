import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../capture/capture_protocol.dart';
import '../../../capture/capture_providers.dart';
import '../../../capture/capture_session.dart';
import '../../../device/device_providers.dart';
import '../../../device/insole_commands.dart';
import '../../../device/sample_rate_meter.dart';
import '../../clock.dart';

/// TARE / REBOOT, refused while a research capture session is open
/// (`activeCaptureProvider`, BACKLOG 21).
final insoleCommandsProvider = Provider<InsoleCommands>((ref) {
  return InsoleCommands(
    controls: {
      for (final side in FootSide.values)
        side: ref.watch(insoleControlProvider(side)),
    },
    batches: ref.watch(deviceManagerProvider).batches,
    captureOpen: () => ref.read(activeCaptureProvider) != null,
  );
});

/// Samples per second per foot over the last 10 s, from the 50 Hz path
/// (works with BLE and the mock). Alive while the Researcher screen is.
final sampleRateMeterProvider = Provider.autoDispose<SampleRateMeter>((ref) {
  final meter = SampleRateMeter(
    batches: ref.watch(deviceManagerProvider).batches,
    now: ref.watch(clockProvider),
    window: CaptureTimings.sampleRateWindow,
  );
  ref.onDispose(meter.dispose);
  return meter;
});

/// The research sessions on the phone, newest first (the export row).
final researchSessionsProvider =
    FutureProvider.autoDispose<List<SessionListing>>((ref) async {
      final Directory root = await ref.watch(researchRootProvider);
      return listSessions(root);
    });
