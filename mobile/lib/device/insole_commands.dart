import 'dart:async';

import '../ble/insole_control.dart';
import '../ble/packets.dart';
import 'foot_sample.dart';

/// Refused before anything was sent.
class CommandRefused implements Exception {
  const CommandRefused(this.reason);

  final CommandRefusal reason;

  @override
  String toString() => 'CommandRefused(${reason.name})';
}

enum CommandRefusal {
  /// BACKLOG 21: TARE would flag (and shift) the recorded pressure, and
  /// REBOOT would cut the recording.
  captureOpen,

  /// No foot is streaming, so there is nothing to send to.
  notConnected,
}

enum TareOutcome {
  /// The insole flagged calibrating packets and then cleared the flag.
  done,

  /// No calibrating window seen within [InsoleCommands.tareTimeout].
  noResponse,
}

/// TARE and REBOOT for the Researcher screen (DESIGN-SPEC §10.2, S8B). The
/// only way the app sends them: both are refused while a research capture
/// session is open (BACKLOG 21), on top of the screen disabling its rows.
/// Each goes to every foot that is streaming.
class InsoleCommands {
  InsoleCommands({
    required this.controls,
    required this.batches,
    required this.captureOpen,
    this.tareTimeout = defaultTareTimeout,
  });

  /// The simulator's TARE takes one stride (≈ 1.1 s); a real board's
  /// window is not specified, so allow plenty.
  static const defaultTareTimeout = Duration(seconds: 10);

  final Map<FootSide, InsoleControl> controls;

  /// The 50 Hz path (`DeviceManager.batches`), where the calibrating flag
  /// shows.
  final Stream<FootBatch> batches;
  final bool Function() captureOpen;
  final Duration tareTimeout;

  /// The feet a command would go to now.
  List<FootSide> get ready => [
    for (final s in FootSide.values)
      if (controls[s]!.canCommand) s,
  ];

  /// Why a command would be refused now, or null.
  CommandRefusal? get refusal {
    if (captureOpen()) return CommandRefusal.captureOpen;
    if (ready.isEmpty) return CommandRefusal.notConnected;
    return null;
  }

  void _guard() {
    final r = refusal;
    if (r != null) throw CommandRefused(r);
  }

  /// Sends TARE to every streaming foot and waits for each one's
  /// calibrating window to open and close.
  Future<Map<FootSide, TareOutcome>> tare() async {
    _guard();
    final sides = ready;
    // Listen before sending, so the first calibrating packet is not missed.
    final outcomes = {for (final s in sides) s: _tareWindow(s)};
    for (final s in sides) {
      await controls[s]!.sendTare();
    }
    return {for (final s in sides) s: await outcomes[s]!};
  }

  Future<TareOutcome> _tareWindow(FootSide side) {
    final done = Completer<TareOutcome>();
    var seen = false;
    late final StreamSubscription<FootBatch> sub;
    final timer = Timer(tareTimeout, () {
      if (!done.isCompleted) done.complete(TareOutcome.noResponse);
    });
    sub = batches.where((b) => b.side == side).listen((b) {
      if (b.calibrating) {
        seen = true;
      } else if (seen && !done.isCompleted) {
        done.complete(TareOutcome.done);
      }
    });
    return done.future.whenComplete(() {
      timer.cancel();
      sub.cancel();
    });
  }

  /// Sends REBOOT to every streaming foot; returns which. Each link drops
  /// and reconnects on its own (logged as an auto-reconnect).
  Future<List<FootSide>> reboot() async {
    _guard();
    final sides = ready;
    for (final s in sides) {
      await controls[s]!.sendReboot();
    }
    return sides;
  }
}
