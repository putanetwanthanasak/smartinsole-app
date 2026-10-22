import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ble_data_source.dart';
import '../ble/packets.dart';
import 'device_manager.dart';

/// The S4 timing check (debug screen): a text log of both feet's clock and
/// continuity figures, for `firmware/simulator/tools/timing_check.py`.
///
/// **How L/R ±10 ms is measured.** Each `SYNC_TIME` the app writes carries
/// the phone time `U`; the simulator logs the device time `D` it handled it
/// at (`[ctl] … SYNC_TIME unix U ms at device D ms`), and both boards'
/// serial logs are stamped by one laptop clock. `timing_check.py` puts both
/// boards' clocks on that laptop clock and compares them with each foot's
/// offset `A` (unix − device) logged here; `U` joins the logs. The
/// write-latency bound `B = A − (U − D)` is printed as a secondary figure
/// only: it can't go below the write's latency, which on the Note 10 was
/// tens of ms (report 026). While running, `SYNC_TIME` goes out every
/// [probeInterval] instead of every 5 minutes; the simulator only logs it.
///
/// Lines are `KIND key=value …`, one event per line:
/// - `SYNC t= side= session= U= A= target=` — a `SYNC_TIME` written
/// - `FOOT t= side= state= session= pkts= lost= seq= …` — every [lineEvery]
class TimingLog {
  TimingLog({
    required this.manager,
    required this.sources,
    required this.now,
    required this.write,
  });

  /// Both feet's BLE sources: their `SYNC_TIME` writes and drop counters.
  final Map<FootSide, BleDataSource> sources;
  final DeviceManager manager;
  final DateTime Function() now;

  /// Receives every line (the file sink, and `debugPrint`).
  final void Function(String line) write;

  static const lineEvery = Duration(seconds: 10);
  static const probeInterval = Duration(seconds: 10);

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;
  int lines = 0;

  bool get running => _timer != null;

  void start() {
    if (running) return;
    _line('# smartinsole timing log v1');
    _line(
      'START t=${_t()} probe_s=${probeInterval.inSeconds} '
      'line_s=${lineEvery.inSeconds}',
    );
    for (final s in sources.values) {
      s.syncInterval = probeInterval;
      _subs.add(s.syncs.listen(_onSync));
    }
    _timer = Timer.periodic(lineEvery, (_) => _feet());
  }

  void stop() {
    if (!running) return;
    _timer?.cancel();
    _timer = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final s in sources.values) {
      s.syncInterval = BleDataSource.defaultSyncInterval;
    }
    _feet();
    _line('STOP t=${_t()}');
  }

  void _onSync(SyncSent s) {
    final t = manager.timing(s.side, takeSteps: false);
    _line(
      'SYNC t=${_t()} side=${_side(s.side)} session=${s.session} '
      'U=${s.unixMs} A=${_ms(t.offsetMs)} target=${_ms(t.targetMs)} '
      'clock_session=${t.session ?? 'na'}',
    );
  }

  void _feet() {
    final snap = manager.snapshot();
    for (final side in FootSide.values) {
      final t = manager.timing(side);
      final st = sources[side]!.stats;
      _line(
        'FOOT t=${_t()} side=${_side(side)} '
        'state=${snap.of(side).connection.name} session=${t.session ?? 'na'} '
        'pkts=${t.packets} lost=${t.lost} seq=${t.lastSeq ?? 'na'} '
        'missingAtStart=${st.missingAtStart} gaps=${st.seqGaps} '
        'gapMissing=${st.seqMissing} beforeStart=${st.droppedBeforeStart} '
        'admittedBeforeAck=${st.admittedBeforeAck} '
        'oldConn=${st.droppedOldConnection} notForward=${st.droppedNotForward} '
        'rejects=${st.totalRejects} A=${_ms(t.offsetMs)} '
        'target=${_ms(t.targetMs)} excess=${_ms(t.lastExcessMs)} '
        'stepMin=${_ms(t.stepMinMs)} stepMax=${_ms(t.stepMaxMs)} '
        'clamps=${t.clamps} sessions=${st.sessions} '
        'linkLosses=${st.linkLosses}',
      );
    }
  }

  void _line(String s) {
    lines++;
    write(s);
    debugPrint('[timing] $s');
  }

  int _t() => now().millisecondsSinceEpoch;
  static String _side(FootSide s) => s == FootSide.left ? 'L' : 'R';
  static String _ms(double? v) => v == null ? 'na' : v.toStringAsFixed(3);
}
