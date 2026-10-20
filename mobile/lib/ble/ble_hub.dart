import 'dart:async';

import 'ble_central.dart';
import 'ble_event_log.dart';
import 'ble_protocol.dart';
import 'link_state.dart';
import 'packets.dart';

/// What both feet share: whether BLE is usable at all ([readiness]), one
/// scan for whoever needs it, the insoles seen so far, which insole each
/// foot has claimed, and a lock so only one connect sequence runs at a time
/// (two concurrent Android connection setups are a common source of GATT
/// errors).
class BleHub {
  BleHub({
    required this.central,
    required this.permissions,
    required this.now,
    required this.log,
  });

  final BleCentral central;
  final BlePermissions permissions;
  final DateTime Function() now;
  final BleEventLog log;

  /// Android blocks an app that starts more than 5 scans in 30 s, silently:
  /// the scan "starts" but reports nothing. Stay one below.
  static const maxScanStarts = 4;
  static const scanStartWindow = Duration(seconds: 30);

  /// A sighting this recent means the insole is advertising right now.
  static const freshSighting = Duration(seconds: 3);

  PermissionStatus? _permission;
  AdapterState _adapter = AdapterState.unknown;
  BleReadiness _readiness = BleReadiness.checking;
  final _readinessChanges = StreamController<BleReadiness>.broadcast();
  StreamSubscription<AdapterState>? _adapterSub;
  late final StreamSubscription<Sighting> _sightingSub;
  bool _started = false;

  final _scanOwners = <Object>{};
  bool _scanning = false;
  bool _scanBusy = false;
  final _scanStarts = <DateTime>[];
  Timer? _scanRetry;

  final _seen = <String, SeenInsole>{};
  final _sightings = StreamController<SeenInsole>.broadcast();
  final _claims = <String, FootSide>{};

  Future<void> _lockTail = Future.value();

  BleReadiness get readiness => _readiness;
  Stream<BleReadiness> get readinessChanges => _readinessChanges.stream;
  bool get scanning => _scanning;

  /// Latest sighting per insole, most recent first.
  List<SeenInsole> get seen =>
      _seen.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  Stream<SeenInsole> get sightings => _sightings.stream;

  /// Checks permissions (asking once if never asked) and starts following
  /// the adapter. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sightingSub = central.sightings.listen(_onSighting);
    var status = await permissions.check();
    if (status == PermissionStatus.denied) status = await permissions.request();
    _setPermission(status);
  }

  /// The system permission prompt, from a button.
  Future<void> requestPermission() async =>
      _setPermission(await permissions.request());

  /// Re-reads permissions, e.g. after the user returns from system settings.
  Future<void> recheckPermission() async {
    if (!_started) return;
    _setPermission(await permissions.check());
  }

  Future<void> openSettings() => permissions.openSettings();

  Future<void> turnOnBluetooth() async {
    try {
      await central.turnOn();
    } on BleException catch (e) {
      log.add('turn on Bluetooth failed: ${e.message}');
    }
  }

  void _setPermission(PermissionStatus status) {
    if (status != _permission) log.add('permission: ${status.name}');
    _permission = status;
    // The adapter is only followed once permitted, so reading it never
    // triggers a permission prompt of its own.
    if (status == PermissionStatus.granted) {
      _adapterSub ??= central.adapterState.listen((s) {
        if (s != _adapter) log.add('adapter: ${s.name}');
        _adapter = s;
        _update();
      });
    }
    _update();
  }

  void _update() {
    final next = switch ((_permission, _adapter)) {
      (null, _) => BleReadiness.checking,
      (PermissionStatus.denied, _) => BleReadiness.needsPermission,
      (PermissionStatus.permanentlyDenied, _) => BleReadiness.permissionDenied,
      (_, AdapterState.on) => BleReadiness.ready,
      (_, AdapterState.off) => BleReadiness.bluetoothOff,
      (_, AdapterState.unavailable) => BleReadiness.unavailable,
      (_, AdapterState.unauthorized) => BleReadiness.needsPermission,
      (_, AdapterState.unknown) => BleReadiness.checking,
    };
    if (next == _readiness) return;
    _readiness = next;
    if (next != BleReadiness.ready) _scanning = false;
    _readinessChanges.add(next);
    _syncScan();
  }

  // --- Scan --------------------------------------------------------------

  /// [owner] needs the scan running (a foot searching, or the debug list).
  void acquireScan(Object owner) {
    if (_scanOwners.add(owner)) _syncScan();
  }

  void releaseScan(Object owner) {
    if (_scanOwners.remove(owner)) _syncScan();
  }

  bool holdsScan(Object owner) => _scanOwners.contains(owner);

  Future<void> _syncScan() async {
    if (_scanBusy) return;
    final want = _scanOwners.isNotEmpty && _readiness == BleReadiness.ready;
    if (want == _scanning) return;
    _scanBusy = true;
    try {
      if (want) {
        final wait = _scanStartDelay();
        if (wait > Duration.zero) {
          _scheduleScanRetry(wait, 'scan start limit');
          return;
        }
        _scanStarts.add(now());
        await central.startScan(serviceUuid: BleUuids.service);
        _scanning = true;
        log.add('scan started');
      } else {
        await central.stopScan();
        _scanning = false;
        log.add('scan stopped');
      }
    } on BleException catch (e) {
      log.add('scan ${want ? 'start' : 'stop'} failed: ${e.message}');
      if (want) _scheduleScanRetry(const Duration(seconds: 2), 'retry');
    } finally {
      _scanBusy = false;
    }
    // Owners may have changed while the plugin call was in flight.
    unawaited(_syncScan());
  }

  Duration _scanStartDelay() {
    final t = now();
    _scanStarts.removeWhere((s) => t.difference(s) >= scanStartWindow);
    if (_scanStarts.length < maxScanStarts) return Duration.zero;
    return _scanStarts.first.add(scanStartWindow).difference(t) +
        const Duration(milliseconds: 100);
  }

  void _scheduleScanRetry(Duration wait, String why) {
    if (_scanRetry?.isActive ?? false) return;
    log.add('scan start in ${wait.inMilliseconds} ms ($why)');
    _scanRetry = Timer(wait, () => unawaited(_syncScan()));
  }

  void _onSighting(Sighting s) {
    final seen = SeenInsole(s, now());
    final isNew = !_seen.containsKey(s.deviceId);
    _seen[s.deviceId] = seen;
    if (isNew) {
      log.add(
        'found ${s.deviceId} (advertised name "${s.name ?? ''}", '
        'rssi ${s.rssi})',
      );
    }
    _sightings.add(seen);
  }

  /// True if [deviceId] advertised within [freshSighting].
  bool seenRecently(String deviceId) {
    final s = _seen[deviceId];
    return s != null && now().difference(s.at) < freshSighting;
  }

  // --- Claims ------------------------------------------------------------

  /// Claims [deviceId] for [side]. Fails if the other foot holds it: a
  /// second connect to the same insole shares one Android GATT link, so
  /// rejecting it there would also cut the other foot.
  bool claim(String deviceId, FootSide side) {
    final holder = _claims[deviceId];
    if (holder != null && holder != side) return false;
    _claims.removeWhere((id, s) => s == side && id != deviceId);
    _claims[deviceId] = side;
    return true;
  }

  void release(String deviceId, FootSide side) {
    if (_claims[deviceId] == side) _claims.remove(deviceId);
  }

  FootSide? claimedBy(String deviceId) => _claims[deviceId];

  // --- Setup lock --------------------------------------------------------

  /// Runs [body] after every earlier [setupLock] body has finished.
  Future<T> setupLock<T>(Future<T> Function() body) {
    final result = _lockTail.then((_) => body());
    _lockTail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void dispose() {
    _scanRetry?.cancel();
    if (_scanning) unawaited(central.stopScan().then((_) {}, onError: (_) {}));
    _adapterSub?.cancel();
    if (_started) _sightingSub.cancel();
    _readinessChanges.close();
    _sightings.close();
  }
}

/// The latest advertisement of one insole, and when the phone saw it.
class SeenInsole {
  const SeenInsole(this.sighting, this.at);

  final Sighting sighting;
  final DateTime at;

  String get deviceId => sighting.deviceId;
}
