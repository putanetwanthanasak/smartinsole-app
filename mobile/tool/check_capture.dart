// Runs the app's own BLE parsers over a laptop capture of a real insole
// (tools/board_check/board_capture.py), to show what the app would accept
// and what Researcher › Diagnostics would count, before the app ever
// connects to the board. Pure Dart: only lib/ble/ files that import nothing
// from Flutter.
//
//   cd mobile && dart run tool/check_capture.dart \
//       ~/smartinsole-data/board-checks/<run>/capture.jsonl
//
// Prints counts per characteristic and per reject reason; exits 1 if the
// app would refuse the insole or reject any packet.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/packet_parser.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/check_capture.dart <capture.jsonl>');
    exit(2);
  }
  final events = [
    for (final line in File(args.single).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final meta = events.firstWhere((e) => e['kind'] == 'meta');
  final wantSide = meta['side'] == 'L' ? FootSide.left : FootSide.right;
  final refused = <String>[];
  final rejects = <String, int>{};
  final parsed = <String, int>{};

  void reject(String char, RejectReason r) {
    final key = '$char ${r.name}';
    rejects[key] = (rejects[key] ?? 0) + 1;
  }

  void ok(String char) => parsed[char] = (parsed[char] ?? 0) + 1;

  // Connect sequence order (FLUTTER-PLAN §5, ble_data_source.dart): MTU,
  // status (rule 8), calibration (N); only then subscribe and START.
  final connected = events.where((e) => e['kind'] == 'connected').firstOrNull;
  final mtu = connected?['mtu'] as int?;
  final mtuMeasured = connected?['mtu_acquired'] != false;
  final minMtu = MtuLayout.minUsableMtu(SensorLayout.fsrCount);
  if (connected == null) {
    refused.add('no connection');
  } else if (!mtuMeasured) {
    // bleak could not acquire the MTU, so 23 is its default, not the board's.
  } else if (mtu == null || mtu < minMtu) {
    refused.add('MTU $mtu < $minMtu (MTU too small)');
  }

  final statusRead = events
      .where((e) => e['kind'] == 'read' && e['char'] == 'status')
      .firstOrNull;
  final statusStates = <String>[];
  void showStatus(String phase, StatusPacket v) => statusStates.add(
    '$phase: ${v.state.name}, battery ${v.batteryPct} %, fw ${v.fwMajor}.'
    '${v.fwMinor}, error ${v.errorCode}',
  );
  if (statusRead == null) {
    refused.add('no status read (the app stops at the status step)');
  } else {
    switch (parseStatusPacket(_bytes(statusRead['hex'] as String))) {
      case Parsed(:final value):
        ok('status');
        showStatus('${statusRead['phase']}', value);
        if (value.footSide != wantSide) {
          refused.add(
            'foot_side ${value.footSide.name}, expected '
            '${wantSide.name} (rule 8)',
          );
        }
      case Rejected(:final reason, :final detail):
        reject('status', reason);
        refused.add('status rejected: ${reason.name} ($detail)');
    }
  }

  // After a refused status the app stops: the calibration is still shown,
  // but not counted as a Diagnostics reject.
  final reached = refused.isEmpty;
  void rejectCal(RejectReason r) {
    if (reached) reject('calibration', r);
  }

  Calibration? cal;
  final calRead = events
      .where((e) => e['kind'] == 'read' && e['char'] == 'calibration')
      .firstOrNull;
  if (calRead == null) {
    if (reached) refused.add('no calibration read');
  } else {
    // Strict, as the app decodes it: bad UTF-8 is calibrationNotJson.
    ParseResult<Calibration> result;
    try {
      result = parseCalibration(utf8.decode(_bytes(calRead['hex'] as String)));
    } on FormatException catch (e) {
      result = Rejected(RejectReason.calibrationNotJson, 'not UTF-8: $e');
    }
    switch (result) {
      case Parsed(:final value):
        cal = value;
        ok('calibration');
        if (value.fsrCount != SensorLayout.fsrCount) {
          rejectCal(RejectReason.calibrationFsrCount);
          refused.add(
            '${reached ? '' : '(not reached by the app) '}calibration rejected: N ${value.fsrCount} '
            '(needs ${SensorLayout.fsrCount})',
          );
        }
      case Rejected(:final reason, :final detail):
        rejectCal(reason);
        refused.add(
          '${reached ? '' : '(not reached by the app) '}calibration rejected: '
          '${reason.name} ($detail)',
        );
    }
  }

  // A refused insole is never subscribed to, so its stream is not counted.
  // Rule 9: sensor and temperature packets before the START write are
  // dropped (Diagnostics "dropped before START"), not rejected.
  var startSent = false;
  var droppedBeforeStart = 0;
  for (final e in refused.isEmpty ? events : const <Map<String, dynamic>>[]) {
    final kind = e['kind'];
    final char = e['char'];
    if (kind == 'write' &&
        e['label'] == 'START_STREAM' &&
        e['phase'] == 'sent') {
      startSent = true;
    }
    if (kind != 'notify') continue;
    final bytes = _bytes(e['hex'] as String);
    switch (char) {
      case 'status':
        switch (parseStatusPacket(bytes)) {
          case Parsed(:final value):
            ok('status');
            showStatus('notify', value);
          case Rejected(:final reason):
            reject('status', reason);
        }
      case 'sensor' || 'temperature' when !startSent:
        droppedBeforeStart++;
      case 'sensor':
        // At the contract's N: an insole whose calibration says otherwise
        // was refused above.
        switch (parseSensorPacket(bytes, fsrCount: SensorLayout.fsrCount)) {
          case Parsed():
            ok('sensor');
          case Rejected(:final reason):
            reject('sensor', reason);
        }
      case 'temperature':
        switch (parseTempPacket(bytes)) {
          case Parsed():
            ok('temperature');
          case Rejected(:final reason):
            reject('temperature', reason);
        }
    }
  }

  stdout.writeln(
    'app parsers on ${args.single.split('/').reversed.skip(1).first}:',
  );
  stdout.writeln(
    mtuMeasured
        ? '  MTU $mtu (needs >= $minMtu)'
        : '  MTU not measured (bleak could not acquire it; not judged)',
  );
  if (cal != null) {
    stdout.writeln(
      '  calibration: device_id ${cal.deviceId}, N ${cal.fsrCount}',
    );
  }
  for (final s in statusStates) {
    stdout.writeln('  status $s');
  }
  if (refused.isNotEmpty) {
    stdout.writeln(
      '  sensor and temperature not parsed: the app never subscribes to a '
      'refused insole',
    );
  }
  stdout.writeln('  parsed: $parsed');
  stdout.writeln('  rejected: ${rejects.isEmpty ? 0 : rejects}');
  if (droppedBeforeStart > 0) {
    stdout.writeln('  dropped before START (rule 9): $droppedBeforeStart');
  }
  final rejectTotal = rejects.values.fold(0, (a, b) => a + b);
  final tempOk = (parsed['temperature'] ?? 0) > 0;
  final format = cal == null
      ? 'no calibration'
      : cal.fsrCount == SensorLayout.fsrCount
      ? 'N ${cal.fsrCount}'
      : 'N ${cal.fsrCount} (needs ${SensorLayout.fsrCount})';
  stdout.writeln(
    '  Diagnostics would show: format $format'
    '${tempOk ? ' · temperature v2, ${TempLayout.siteCount} sites' : ' · no temperature packet'}'
    ' · rejects $rejectTotal',
  );
  if (refused.isNotEmpty) {
    stdout.writeln('  the app would REFUSE this insole: ${refused.join('; ')}');
  } else {
    stdout.writeln('  the app would accept this insole');
  }
  exit(refused.isEmpty && rejectTotal == 0 && droppedBeforeStart == 0 ? 0 : 1);
}
