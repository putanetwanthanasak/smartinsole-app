import 'dart:typed_data';

import 'ble_protocol.dart';

/// Byte encodings of the Control characteristic writes used by the connect
/// sequence (contract §3.4). Each is exactly its opcode's length.

Uint8List startStreamCommand() => Uint8List.fromList([BleOpcode.startStream]);

Uint8List stopStreamCommand() => Uint8List.fromList([BleOpcode.stopStream]);

/// `SYNC_TIME`: opcode, then [unixMs] as little-endian uint64.
Uint8List syncTimeCommand(int unixMs) {
  final data = ByteData(BleOpcode.syncTimeBytes)
    ..setUint8(0, BleOpcode.syncTime)
    ..setUint64(1, unixMs, Endian.little);
  return data.buffer.asUint8List();
}

/// `TARE` (contract §3.4): zero the FSR baseline. Acts on the whole insole.
Uint8List tareCommand() => Uint8List.fromList([BleOpcode.tare]);

/// `REBOOT` (contract §3.4): restart the insole. Acts on the whole insole.
Uint8List rebootCommand() => Uint8List.fromList([BleOpcode.reboot]);
