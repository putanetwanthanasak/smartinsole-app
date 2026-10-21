import 'package:permission_handler/permission_handler.dart' as ph;

import 'ble_central.dart';

/// [BlePermissions] on `permission_handler`: Android 12+ `BLUETOOTH_SCAN`
/// (declared `neverForLocation`) and `BLUETOOTH_CONNECT`. On Android 11 and
/// below these report granted, and flutter_blue_plus asks for the location
/// permission that scanning needed there itself (not tested: the study
/// phone is Android 12).
class HandlerPermissions implements BlePermissions {
  static const _needed = [
    ph.Permission.bluetoothScan,
    ph.Permission.bluetoothConnect,
  ];

  @override
  Future<PermissionStatus> check() async =>
      _combine([for (final p in _needed) await p.status]);

  @override
  Future<PermissionStatus> request() async =>
      _combine((await _needed.request()).values);

  @override
  Future<void> openSettings() => ph.openAppSettings();

  static PermissionStatus _combine(Iterable<ph.PermissionStatus> all) {
    if (all.every((s) => s.isGranted)) return PermissionStatus.granted;
    if (all.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return PermissionStatus.permanentlyDenied;
    }
    return PermissionStatus.denied;
  }
}
