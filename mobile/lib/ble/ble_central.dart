import 'dart:async';
import 'dart:typed_data';

/// The app's own thin view of the phone's BLE stack. `BleDataSource` only
/// talks to this, so the connect sequence can be unit-tested against a fake,
/// and the plugin behind it (`flutter_blue_plus` today, see
/// `fbp_central.dart`) can be swapped without touching the sequence.
abstract interface class BleCentral {
  /// Current adapter state first, then every change.
  Stream<AdapterState> get adapterState;

  /// Asks the OS to turn Bluetooth on (Android shows a system prompt).
  Future<void> turnOn();

  /// Starts scanning for advertisements that carry [serviceUuid]. Results
  /// arrive on [sightings] until [stopScan]. Advertised names are reported
  /// for display only: the OS caches them, so they never decide anything.
  Future<void> startScan({required String serviceUuid});

  Future<void> stopScan();

  /// One event per advertisement seen while scanning.
  Stream<Sighting> get sightings;

  /// Opens a GATT connection to [deviceId]. Does not negotiate the MTU; the
  /// caller does that explicitly on every connect.
  Future<BleLink> connect(String deviceId, {required Duration timeout});
}

/// One open GATT connection.
abstract interface class BleLink {
  String get deviceId;

  /// Returns the MTU actually negotiated.
  Future<int> requestMtu(int mtu);

  /// Android `requestConnectionPriority(HIGH)` (11.25–15 ms interval).
  Future<void> requestHighPriority();

  /// Discovers services; throws [BleServiceMissing] if [serviceUuid] is
  /// missing.
  Future<void> discover({required String serviceUuid});

  /// Full value (GATT long read when longer than one ATT payload).
  Future<Uint8List> read(String characteristicUuid);

  /// Write with response: completes when the device acknowledged it.
  Future<void> write(String characteristicUuid, Uint8List value);

  /// Notifications of [characteristicUuid]. Listen before [enableNotify] so
  /// the first value is not missed.
  Stream<Uint8List> notifications(String characteristicUuid);

  Future<void> enableNotify(String characteristicUuid);

  /// MTU changes after [requestMtu] (the peripheral or OS may renegotiate).
  Stream<int> get mtuChanges;

  /// Completes once when this connection ends, for any reason.
  Future<void> get closed;

  Future<void> disconnect();
}

enum AdapterState {
  unknown,

  /// No Bluetooth hardware (e.g. the Android emulator).
  unavailable,

  /// The app lacks the runtime permission to see the adapter.
  unauthorized,
  off,
  on,
}

/// An advertisement carrying the SmartInsole service UUID.
class Sighting {
  const Sighting({
    required this.deviceId,
    required this.name,
    required this.rssi,
  });

  final String deviceId;

  /// As advertised or as cached by the OS. Display only (contract §2.1).
  final String? name;
  final int rssi;
}

/// Wraps whatever the plugin threw, with a readable message for the log.
class BleException implements Exception {
  const BleException(this.message);
  final String message;

  @override
  String toString() => 'BleException: $message';
}

/// The device has no SmartInsole GATT service: not an insole, so connecting
/// again would not help.
class BleServiceMissing extends BleException {
  const BleServiceMissing(super.message);
}

/// Runtime Bluetooth permissions (Android 12+: SCAN and CONNECT).
abstract interface class BlePermissions {
  Future<PermissionStatus> check();

  /// Shows the system prompt when the OS still allows it.
  Future<PermissionStatus> request();

  /// Opens the app's system settings page (after a permanent denial).
  Future<void> openSettings();
}

enum PermissionStatus { granted, denied, permanentlyDenied }
