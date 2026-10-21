import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'packets.dart';

/// The last [capacity] BLE events of both feet, for the debug screen's
/// event log and "Copy log". Every line is also printed with `debugPrint`,
/// so `flutter run` shows it live.
class BleEventLog {
  BleEventLog({required this.now, this.capacity = 200});

  final DateTime Function() now;
  final int capacity;
  final _entries = ListQueue<BleLogEntry>();

  List<BleLogEntry> get entries => List.unmodifiable(_entries);

  void add(String message, {FootSide? side}) {
    final entry = BleLogEntry(now(), side, message);
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    debugPrint('[ble] $entry');
  }

  /// Every entry, oldest first, one per line.
  String text() => _entries.join('\n');
}

class BleLogEntry {
  const BleLogEntry(this.at, this.side, this.message);

  final DateTime at;
  final FootSide? side;
  final String message;

  @override
  String toString() {
    final t = at.toIso8601String().substring(11, 23);
    final tag = switch (side) {
      FootSide.left => 'L',
      FootSide.right => 'R',
      null => '-',
    };
    return '$t $tag $message';
  }
}
