import 'packets.dart';

/// What the Connection screen asks of one foot (DESIGN-SPEC §9): find an
/// insole for this foot, stop looking, disconnect, connect again. Over BLE
/// it is `FootFinder`; with the mock (debug emulator runs) it is
/// `MockConnector` in `lib/device/`.
abstract interface class FootConnector {
  FootSide get side;

  FinderState get state;
  Stream<FinderState> get states;

  /// Looks for an insole that reports this foot (rule 8) and connects it
  /// ("เชื่อมต่อเท้าซ้าย", "ค้นหาอีกครั้ง").
  Future<void> find();

  /// "หยุดค้นหา": stops finding, or stops an automatic reconnect search.
  Future<void> stop();

  /// "เชื่อมต่อใหม่": drops the link and finds again.
  Future<void> reconnect();

  /// "ยกเลิกการเชื่อมต่อ": stops streaming and forgets the insole, so the
  /// app no longer reconnects it at start.
  Future<void> disconnect();
}

/// Where finding stands. While [FinderSearching], the foot's own
/// `LinkState` says whether a candidate is being connected right now.
sealed class FinderState {
  const FinderState();
}

/// Not finding: the foot's `LinkState` says everything.
final class FinderIdle extends FinderState {
  const FinderIdle();
}

final class FinderSearching extends FinderState {
  const FinderSearching();
}

/// Only insoles of the other foot answered (rule 8: rejected, no START).
final class FinderWrongSide extends FinderState {
  const FinderWrongSide(this.reportedSide);

  final FootSide reportedSide;
}

/// No insole answered within the search window.
final class FinderNotFound extends FinderState {
  const FinderNotFound();
}
