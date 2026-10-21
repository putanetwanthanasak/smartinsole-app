import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'ble_central.dart';

/// [BleCentral] on `flutter_blue_plus`. A translation layer only: the connect
/// sequence, MTU checks, side checks and reconnects all live in
/// `BleDataSource`, which never sees a plugin type.
///
/// Licence: flutter_blue_plus 2.x is under the FlutterBluePlus License, free
/// for accredited educational institutions, nonprofits and organisations
/// under 50 employees; this KMUTT thesis app connects as
/// [fbp.License.nonprofit] (report 024). Swapping plugins means a new
/// implementation of [BleCentral], nothing else.
class FbpCentral implements BleCentral {
  FbpCentral() {
    // oneByOne + continuousUpdates: every advertisement arrives as its own
    // single-item list, so a board coming back after a power cycle is seen
    // again even though it was seen before.
    _scanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final last = _lastSeen[id];
        if (last != null && !r.timeStamp.isAfter(last)) continue;
        _lastSeen[id] = r.timeStamp;
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        _sightings.add(
          Sighting(
            deviceId: id,
            name: name.isEmpty ? null : name,
            rssi: r.rssi,
          ),
        );
      }
    });
  }

  final _sightings = StreamController<Sighting>.broadcast();
  final _lastSeen = <String, DateTime>{};
  late final StreamSubscription<List<fbp.ScanResult>> _scanSub;

  @override
  Stream<AdapterState> get adapterState =>
      fbp.FlutterBluePlus.adapterState.map(_adapterState);

  static AdapterState _adapterState(fbp.BluetoothAdapterState s) => switch (s) {
    fbp.BluetoothAdapterState.on => AdapterState.on,
    fbp.BluetoothAdapterState.off ||
    fbp.BluetoothAdapterState.turningOff ||
    fbp.BluetoothAdapterState.turningOn => AdapterState.off,
    fbp.BluetoothAdapterState.unavailable => AdapterState.unavailable,
    fbp.BluetoothAdapterState.unauthorized => AdapterState.unauthorized,
    fbp.BluetoothAdapterState.unknown => AdapterState.unknown,
  };

  @override
  Future<void> turnOn() => _wrap('turnOn', fbp.FlutterBluePlus.turnOn);

  @override
  Future<void> startScan({required String serviceUuid}) => _wrap(
    'startScan',
    () => fbp.FlutterBluePlus.startScan(
      withServices: [fbp.Guid(serviceUuid)],
      continuousUpdates: true,
      oneByOne: true,
    ),
  );

  @override
  Future<void> stopScan() => _wrap('stopScan', fbp.FlutterBluePlus.stopScan);

  @override
  Stream<Sighting> get sightings => _sightings.stream;

  @override
  Future<BleLink> connect(String deviceId, {required Duration timeout}) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    await _wrap(
      'connect',
      () => device.connect(
        license: fbp.License.nonprofit,
        timeout: timeout,
        // The MTU is requested explicitly by the connect sequence, on every
        // connect and reconnect; FBP's own automatic request is turned off.
        mtu: null,
        autoConnect: false,
      ),
    );
    return _FbpLink(device);
  }

  void dispose() {
    _scanSub.cancel();
    _sightings.close();
  }
}

class _FbpLink implements BleLink {
  _FbpLink(this._device) {
    // connectionState replays the current state first: skip it, and close on
    // the first real disconnect.
    _stateSub = _device.connectionState.listen((s) {
      if (s == fbp.BluetoothConnectionState.disconnected) _close();
    });
  }

  final fbp.BluetoothDevice _device;
  final _closed = Completer<void>();
  late final StreamSubscription<fbp.BluetoothConnectionState> _stateSub;
  final _chars = <String, fbp.BluetoothCharacteristic>{};

  void _close() {
    if (_closed.isCompleted) return;
    _stateSub.cancel();
    _closed.complete();
  }

  @override
  String get deviceId => _device.remoteId.str;

  @override
  Future<int> requestMtu(int mtu) =>
      _wrap('requestMtu', () => _device.requestMtu(mtu));

  @override
  Future<void> requestHighPriority() => _wrap(
    'requestConnectionPriority',
    () => _device.requestConnectionPriority(
      connectionPriorityRequest: fbp.ConnectionPriority.high,
    ),
  );

  @override
  Future<void> discover({required String serviceUuid}) async {
    final services = await _wrap('discoverServices', _device.discoverServices);
    final want = fbp.Guid(serviceUuid);
    final service = services.where((s) => s.uuid == want).firstOrNull;
    if (service == null) {
      throw BleServiceMissing('service $serviceUuid not found on $deviceId');
    }
    _chars
      ..clear()
      ..addEntries(
        service.characteristics.map((c) => MapEntry(c.uuid.str128, c)),
      );
  }

  fbp.BluetoothCharacteristic _char(String uuid) {
    final c = _chars[fbp.Guid(uuid).str128];
    if (c == null) throw BleException('characteristic $uuid not found');
    return c;
  }

  @override
  Future<Uint8List> read(String characteristicUuid) async => Uint8List.fromList(
    await _wrap('read', () => _char(characteristicUuid).read()),
  );

  @override
  Future<void> write(String characteristicUuid, Uint8List value) => _wrap(
    'write',
    () => _char(characteristicUuid).write(value, withoutResponse: false),
  );

  @override
  Stream<Uint8List> notifications(String characteristicUuid) =>
      _char(characteristicUuid).onValueReceived.map(Uint8List.fromList);

  @override
  Future<void> enableNotify(String characteristicUuid) => _wrap(
    'setNotifyValue',
    () => _char(characteristicUuid).setNotifyValue(true),
  );

  @override
  Stream<int> get mtuChanges => _device.mtu.skip(1);

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> disconnect() async {
    try {
      await _wrap('disconnect', _device.disconnect);
    } finally {
      _close();
    }
  }
}

/// Rethrows any plugin error as a [BleException] with the operation name.
Future<T> _wrap<T>(String op, Future<T> Function() call) async {
  try {
    return await call();
  } on BleException {
    rethrow;
  } on fbp.FlutterBluePlusException catch (e) {
    throw BleException('$op: ${e.description ?? e.code} (code ${e.code})');
  } on TimeoutException {
    throw BleException('$op: timed out');
  } catch (e) {
    throw BleException('$op: $e');
  }
}
