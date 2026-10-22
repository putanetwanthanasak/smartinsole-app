import 'dart:io';

import 'package:intl/intl.dart';

import '../ble/ble_data_source.dart';
import '../ble/packets.dart';
import 'device_manager.dart';
import 'timing_log.dart';

/// Runs a [TimingLog] into a file in the app's private storage, for the
/// Note 10 checkpoint (debug screen). Pull it with
/// `adb exec-out run-as th.ac.kmutt.smartinsole cat app_flutter/timing/<name>`
/// (debug builds only). Each line is written and flushed at once, so a
/// crash or a killed app loses nothing already logged.
class TimingCheck {
  TimingCheck({
    required this.manager,
    required this.sources,
    required this.now,
    required this.directory,
  });

  final DeviceManager manager;
  final Map<FootSide, BleDataSource> sources;
  final DateTime Function() now;

  /// The app's documents directory (`path_provider`, or a temp dir in
  /// tests).
  final Future<Directory> Function() directory;

  TimingLog? _log;
  RandomAccessFile? _file;
  String? path;
  DateTime? startedAt;

  bool get running => _log?.running ?? false;
  int get lines => _log?.lines ?? 0;

  Future<void> start() async {
    if (running) return;
    final dir = Directory('${(await directory()).path}/timing');
    await dir.create(recursive: true);
    final name = 'timing-${DateFormat('yyyyMMdd-HHmmss').format(now())}.log';
    final file = File('${dir.path}/$name');
    _file = file.openSync(mode: FileMode.append);
    path = file.path;
    startedAt = now();
    _log = TimingLog(
      manager: manager,
      sources: sources,
      now: now,
      write: (line) => _file
        ?..writeStringSync('$line\n')
        ..flushSync(),
    )..start();
  }

  void stop() {
    _log?.stop();
    _file?.closeSync();
    _file = null;
  }
}
