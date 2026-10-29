import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_protocol.dart';

import 'packet_builder.dart';

/// A scripted insole for [FakeBleCentral]: what it advertises, what its
/// status and calibration say, and what MTU the "phone" negotiates with it.
class FakeInsole {
  FakeInsole({
    required this.id,
    this.name,
    this.footSide = 0,
    this.fsrCount = SensorLayout.fsrCount,
    this.mtu = 247,
    this.advertising = true,
    this.hasService = true,
    this.rssi = -55,
    String? calibrationJson,
  }) : calibrationJson =
           calibrationJson ?? jsonEncode(calibrationBlob(fsrCount));

  final String id;

  /// Advertised name; deliberately allowed to disagree with [footSide]
  /// (OS name caching).
  String? name;
  int footSide;
  int fsrCount;

  /// What `requestMtu` returns.
  int mtu;
  bool advertising;
  bool hasService;
  int rssi;
  String calibrationJson;

  int batteryPct = 100;

  /// The next [failConnects] connect calls throw.
  int failConnects = 0;

  /// The live link, if connected.
  FakeLink? link;

  Uint8List statusBytes({int state = 0}) {
    final d = ByteData(StatusLayout.packetBytes)
      ..setUint8(0, batteryPct)
      ..setUint16(1, 4200, Endian.little)
      ..setUint8(3, footSide)
      ..setUint8(4, 0)
      ..setUint8(5, 1)
      ..setUint8(6, state)
      ..setUint8(7, 0);
    return d.buffer.asUint8List();
  }
}

/// In-memory [BleCentral]. Records every call in [calls] so tests can check
/// the exact connect sequence.
class FakeBleCentral implements BleCentral {
  FakeBleCentral({List<FakeInsole> insoles = const []}) {
    for (final i in insoles) {
      add(i);
    }
  }

  final insoles = <String, FakeInsole>{};
  final calls = <String>[];
  final _adapter = StreamController<AdapterState>.broadcast();
  final _sightings = StreamController<Sighting>.broadcast();
  AdapterState adapterNow = AdapterState.on;
  bool scanning = false;
  int scanStarts = 0;

  /// Called on every write, before it is acknowledged (e.g. to deliver a
  /// notification while START is still in flight).
  void Function(FakeLink link, Uint8List value)? onWrite;

  /// If set, every streaming link sends a packet on this period on its own
  /// (the emulator demo). Tests leave it null and push packets explicitly.
  Duration? autoStreamPeriod;

  void add(FakeInsole insole) => insoles[insole.id] = insole;

  void setAdapter(AdapterState s) {
    adapterNow = s;
    if (s != AdapterState.on) {
      scanning = false;
      _adTimer?.cancel();
      for (final i in insoles.values) {
        i.link?.drop();
      }
    }
    _adapter.add(s);
  }

  /// Emits one advertisement of every advertising insole, if scanning.
  void advertiseAll() {
    if (!scanning) return;
    for (final i in insoles.values) {
      if (i.advertising && i.link == null) _advertise(i);
    }
  }

  void _advertise(FakeInsole i) =>
      _sightings.add(Sighting(deviceId: i.id, name: i.name, rssi: i.rssi));

  @override
  Stream<AdapterState> get adapterState async* {
    yield adapterNow;
    yield* _adapter.stream;
  }

  @override
  Future<void> turnOn() async {
    calls.add('turnOn');
    setAdapter(AdapterState.on);
  }

  @override
  Future<void> startScan({required String serviceUuid}) async {
    calls.add('startScan');
    if (adapterNow != AdapterState.on) throw const BleException('adapter off');
    scanning = true;
    scanStarts++;
    scheduleMicrotask(advertiseAll);
    // A real scan keeps reporting each advertising insole.
    _adTimer?.cancel();
    _adTimer = Timer.periodic(advertisingPeriod, (_) => advertiseAll());
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
    scanning = false;
    _adTimer?.cancel();
  }

  /// How often a scan reports each advertising insole.
  static const advertisingPeriod = Duration(milliseconds: 500);
  Timer? _adTimer;

  @override
  Stream<Sighting> get sightings => _sightings.stream;

  @override
  Future<BleLink> connect(String deviceId, {required Duration timeout}) async {
    calls.add('connect $deviceId');
    final insole = insoles[deviceId];
    if (insole == null || !insole.advertising) {
      throw BleException('connect $deviceId: timed out');
    }
    if (insole.failConnects > 0) {
      insole.failConnects--;
      throw BleException('connect $deviceId: GATT error 133');
    }
    if (adapterNow != AdapterState.on) throw const BleException('adapter off');
    final link = FakeLink(this, insole);
    insole.link = link;
    return link;
  }
}

class FakeLink implements BleLink {
  FakeLink(this.central, this.insole);

  final FakeBleCentral central;
  final FakeInsole insole;
  final _closed = Completer<void>();
  final _notify = <String, StreamController<Uint8List>>{};
  final _mtu = StreamController<int>.broadcast();
  final enabled = <String>{};

  /// Every Control write, in order.
  final writes = <Uint8List>[];
  bool streaming = false;
  int seq = 0;

  /// Device clock, ms since boot.
  int t0 = 100000;
  Timer? _auto;
  bool get isOpen => !_closed.isCompleted;

  void _call(String c) => central.calls.add('${insole.id} $c');

  StreamController<Uint8List> _ctl(String uuid) =>
      _notify.putIfAbsent(uuid, StreamController<Uint8List>.broadcast);

  static String short(String uuid) => switch (uuid) {
    BleUuids.sensorStream => 'sensor',
    BleUuids.temperature => 'temperature',
    BleUuids.deviceStatus => 'status',
    BleUuids.control => 'control',
    BleUuids.calibration => 'calibration',
    _ => uuid,
  };

  void _checkOpen() {
    if (!isOpen) throw BleException('${insole.id}: not connected');
  }

  @override
  String get deviceId => insole.id;

  @override
  Future<int> requestMtu(int mtu) async {
    _call('requestMtu $mtu');
    _checkOpen();
    return insole.mtu;
  }

  @override
  Future<void> requestHighPriority() async => _call('priority high');

  @override
  Future<void> discover({required String serviceUuid}) async {
    _call('discover');
    _checkOpen();
    if (!insole.hasService) throw const BleServiceMissing('no service');
  }

  @override
  Future<Uint8List> read(String uuid) async {
    _call('read ${short(uuid)}');
    _checkOpen();
    return switch (uuid) {
      BleUuids.deviceStatus => insole.statusBytes(state: streaming ? 1 : 0),
      BleUuids.calibration => Uint8List.fromList(
        utf8.encode(insole.calibrationJson),
      ),
      _ => throw BleException('read ${short(uuid)} not supported'),
    };
  }

  @override
  Future<void> write(String uuid, Uint8List value) async {
    final hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _call(
      'write ${short(uuid)} ${value.length == 1 ? hex : '${hex.substring(0, 2)}+${value.length - 1}'}',
    );
    _checkOpen();
    if (uuid != BleUuids.control) return;
    writes.add(value);
    // Like the simulator, a START takes effect before the write is
    // acknowledged, so [onWrite] can deliver this session's first packet
    // (seq 0) while the write is still in flight (BACKLOG 27).
    if (value.length == 1 && value[0] == BleOpcode.startStream) {
      streaming = true;
      seq = 0;
      _startAuto();
    } else if (value.length == 1 && value[0] == BleOpcode.stopStream) {
      streaming = false;
      _auto?.cancel();
    }
    central.onWrite?.call(this, value);
  }

  @override
  Stream<Uint8List> notifications(String uuid) => _ctl(uuid).stream;

  @override
  Future<void> enableNotify(String uuid) async {
    _call('notify ${short(uuid)}');
    _checkOpen();
    enabled.add(uuid);
  }

  @override
  Stream<int> get mtuChanges => _mtu.stream;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> disconnect() async {
    _call('disconnect');
    drop();
  }

  // --- Test controls ------------------------------------------------------

  /// The link ends (power cycle, out of range, adapter off).
  void drop() {
    if (!isOpen) return;
    streaming = false;
    _auto?.cancel();
    if (identical(insole.link, this)) insole.link = null;
    _closed.complete();
  }

  /// Delivers raw bytes on [uuid] as a notification, ignoring subscription
  /// and streaming state (for rule 9 tests).
  void push(String uuid, Uint8List bytes) {
    if (isOpen) _ctl(uuid).add(bytes);
  }

  /// Delivers [bytes] even after the link has closed: a notification the
  /// stack had queued before the disconnect (rule 9).
  void pushLate(String uuid, Uint8List bytes) => _ctl(uuid).add(bytes);

  /// The next sensor packet: `seq` and `t0` advance as the simulator's do.
  Uint8List nextSensorPacket({int samples = 8, int flags = 0}) {
    final p = buildSensorPacket(
      seq: seq,
      t0Ms: t0,
      flags: flags,
      samples: sampleSpecs(insole.fsrCount, samples),
    );
    seq = (seq + 1) & 0xFFFF;
    t0 = (t0 + samples * SensorLayout.sampleSpacingMs) & 0xFFFFFFFF;
    return p;
  }

  void sendSensor({int samples = 8, int flags = 0}) => push(
    BleUuids.sensorStream,
    nextSensorPacket(samples: samples, flags: flags),
  );

  /// A temperature v2 packet; [raw] is 0.01 °C per site (−32768 = could
  /// not read), [quality] 0–2 per site.
  void sendTemp({
    int? tMs,
    List<int> raw = defaultTempRaw,
    List<int>? quality,
  }) => push(
    BleUuids.temperature,
    buildTempPacket(tMs: tMs ?? t0, raw: raw, quality: quality),
  );

  /// The refused v1 packet (12 bytes, forefoot and heel only).
  void sendLegacyTemp({int? tMs}) {
    final d = ByteData(TempLayout.legacyPacketBytes)
      ..setUint32(2, tMs ?? t0, Endian.little)
      ..setInt16(6, 3180, Endian.little)
      ..setInt16(8, 3120, Endian.little);
    push(BleUuids.temperature, d.buffer.asUint8List());
  }

  void sendStatus({int? footSide}) {
    final saved = insole.footSide;
    if (footSide != null) insole.footSide = footSide;
    push(BleUuids.deviceStatus, insole.statusBytes(state: streaming ? 1 : 0));
    insole.footSide = saved;
  }

  void changeMtu(int mtu) {
    insole.mtu = mtu;
    _mtu.add(mtu);
  }

  void _startAuto() {
    final period = central.autoStreamPeriod;
    if (period == null) return;
    _auto?.cancel();
    var n = 0;
    _auto = Timer.periodic(period, (_) {
      final fit = MtuLayout.samplesPerPacket(insole.mtu, insole.fsrCount);
      if (fit == 0) return;
      sendSensor(samples: fit);
      if (n++ % 190 == 0) sendTemp();
    });
  }
}

/// [BlePermissions] with a settable answer.
class FakePermissions implements BlePermissions {
  FakePermissions([this.status = PermissionStatus.granted]);

  PermissionStatus status;

  /// What the next [request] turns [status] into (the user's answer).
  PermissionStatus? answer;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<PermissionStatus> check() async => status;

  @override
  Future<PermissionStatus> request() async {
    requests++;
    if (answer != null) status = answer!;
    return status;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}
