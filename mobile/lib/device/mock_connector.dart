import 'dart:async';

import '../ble/foot_connector.dart';
import '../ble/insole_data_source.dart';
import '../ble/packets.dart';

/// [FootConnector] for the mock insoles (debug runs with
/// `--dart-define=MOCK=<preset>`): there is nothing to search for, so
/// finding is connecting, and the finder is always idle.
class MockConnector implements FootConnector {
  MockConnector(this.source);

  final InsoleDataSource source;

  @override
  FootSide get side => source.side;

  @override
  FinderState get state => const FinderIdle();

  @override
  Stream<FinderState> get states => const Stream.empty();

  @override
  Future<void> find() => source.connect();

  @override
  Future<void> stop() => source.disconnect();

  @override
  Future<void> reconnect() async {
    await source.disconnect();
    await source.connect();
  }

  @override
  Future<void> disconnect() => source.disconnect();
}
