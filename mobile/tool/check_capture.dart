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

  // Connect sequence order (FLUTTER-PLAN §5): MTU, status (rule 8),
  // calibration (N), then notifications.
  final connected = events.where((e) => e['kind'] == 'connected').firstOrNull;
  final mtu = connected?['mtu'] as int?;
  final minMtu = MtuLayout.minUsableMtu(SensorLayout.fsrCount);
  if (mtu == null || mtu < minMtu) {
    refused.add('MTU $mtu < $minMtu (MTU too small)');
  }

  Calibration? cal;
  final calRead = events
      .where((e) => e['kind'] == 'read' && e['char'] == 'calibration')
      .firstOrNull;
  if (calRead == null) {
    refused.add('no calibration read');
  } else {
    final text = utf8.decode(
      _bytes(calRead['hex'] as String),
      allowMalformed: true,
    );
    switch (parseCalibration(text)) {
      case Parsed(:final value):
        cal = value;
        ok('calibration');
        if (value.fsrCount != SensorLayout.fsrCount) {
          reject('calibration', RejectReason.calibrationFsrCount);
          refused.add(
            'calibration rejected: N ${value.fsrCount} '
            '(needs ${SensorLayout.fsrCount})',
          );
        }
      case Rejected(:final reason, :final detail):
        reject('calibration', reason);
        refused.add('calibration rejected: ${reason.name} ($detail)');
    }
  }

  final statusStates = <String>[];
  for (final e in events) {
    final kind = e['kind'];
    final char = e['char'];
    if (char == null || (kind != 'read' && kind != 'notify')) continue;
    if (char == 'calibration' || e['phase'] == 'dis') continue;
    final bytes = _bytes(e['hex'] as String);
    switch (char) {
      case 'status':
        switch (parseStatusPacket(bytes)) {
          case Parsed(:final value):
            ok('status');
            statusStates.add(
              '${e['phase'] ?? 'notify'}: ${value.state.name}, '
              'battery ${value.batteryPct} %, fw ${value.fwMajor}.'
              '${value.fwMinor}, error ${value.errorCode}',
            );
            if (value.footSide != wantSide &&
                !refused.any((r) => r.startsWith('foot_side'))) {
              refused.add(
                'foot_side ${value.footSide.name}, expected '
                '${wantSide.name} (rule 8)',
              );
            }
          case Rejected(:final reason):
            reject('status', reason);
        }
      case 'sensor':
        // At the contract's N: an insole whose calibration says otherwise
        // is refused before anything streams, so its N is never used here.
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
  stdout.writeln('  MTU $mtu (needs >= $minMtu)');
  if (cal != null) {
    stdout.writeln(
      '  calibration: device_id ${cal.deviceId}, N ${cal.fsrCount}',
    );
  }
  for (final s in statusStates) {
    stdout.writeln('  status $s');
  }
  stdout.writeln('  parsed: $parsed');
  stdout.writeln('  rejected: ${rejects.isEmpty ? 0 : rejects}');
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
  exit(refused.isEmpty && rejectTotal == 0 ? 0 : 1);
}
