import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../ble/packets.dart';
import '../device/device_providers.dart';
import '../ui/clock.dart';
import 'capture_files.dart';
import 'capture_session.dart';
import 'cues.dart';

/// Platform seams of research capture; tests override every one.

/// `<app documents>/research`: app-private, never readable by other apps.
final researchRootProvider = Provider<Future<Directory>>(
  (ref) async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}/'
    '$researchDirName',
  ),
);

/// `<app-specific external>/export`, where an export is staged for
/// `adb pull`. Null where the platform has none.
final exportRootProvider = Provider<Future<Directory?>>((ref) async {
  final ext = await getExternalStorageDirectory();
  return ext == null ? null : Directory('${ext.path}/export');
});

final appVersionProvider = Provider<Future<String>>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

final captureCuesProvider = Provider<CaptureCues>((ref) {
  final cues = DeviceCues();
  ref.onDispose(cues.dispose);
  return cues;
});

/// Keeps the screen on (true) or lets it sleep again (false).
final wakelockProvider = Provider<Future<void> Function(bool on)>(
  (ref) =>
      (on) => WakelockPlus.toggle(enable: on),
);

/// Everything a [CaptureSession] needs from the app.
final captureDepsProvider = FutureProvider<CaptureDeps>((ref) async {
  return CaptureDeps(
    manager: ref.watch(deviceManagerProvider),
    sources: {
      for (final side in FootSide.values)
        side: ref.watch(insoleDataSourceProvider(side)),
    },
    cues: ref.watch(captureCuesProvider),
    now: ref.watch(clockProvider),
    appVersion: await ref
        .watch(appVersionProvider)
        .catchError((Object _) => 'unknown'),
  );
});
