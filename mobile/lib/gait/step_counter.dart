import 'dart:async';

import '../rules/step_detector.dart';
import '../storage/daily_summary_repository.dart';
import '../storage/local_date.dart';
import 'gait_timing.dart';

/// Today's walking steps, both feet together ("ก้าววันนี้", DESIGN-SPEC
/// §8.3), stored in `daily_summary.steps`.
///
/// It counts the steps the alert engine counts (`AlertEngine.steps`: a
/// stance with the walking gate on during it), so the tab and the rules
/// agree. A step belongs to the local day its stance ended on. The stored
/// count is read back at start, so it continues across a restart; it is
/// written at most every [stepsWriteEvery], when the day changes and on
/// [stop].
class StepCounter {
  StepCounter({
    required this.steps,
    required this.summaries,
    required this.dates,
    required this.now,
  });

  final Stream<Step> steps;
  final DailySummaryRepository summaries;
  final LocalDates dates;
  final DateTime Function() now;

  String? _date;
  int _count = 0;
  int _stored = 0;
  bool _loaded = false;
  final _pending = <Step>[];
  StreamSubscription<Step>? _sub;
  Timer? _timer;
  Future<void> _write = Future.value();

  void start() {
    _sub = steps.listen(_onStep);
    _timer = Timer.periodic(stepsWriteEvery, (_) => _flush());
    _load();
  }

  Future<void> _load() async {
    final date = dates.of(now().millisecondsSinceEpoch);
    final row = await summaries.get(date);
    _date = date;
    _count = row?.steps ?? 0;
    _stored = _count;
    _loaded = true;
    // Steps that ended before the stored count was read.
    for (final s in _pending) {
      _onStep(s);
    }
    _pending.clear();
  }

  void _onStep(Step step) {
    if (!_loaded) {
      _pending.add(step);
      return;
    }
    final date = dates.of(step.endMs.round());
    if (date != _date) {
      // A new day: what the old day has is written, and this one starts
      // from what is stored for it (nothing, unless the app restarted).
      _flush();
      _date = date;
      _count = 0;
      _stored = 0;
      _loaded = false;
      _pending.add(step);
      summaries.get(date).then((row) {
        if (_date != date) return;
        _count = row?.steps ?? 0;
        _stored = _count;
        _loaded = true;
        for (final s in _pending) {
          _onStep(s);
        }
        _pending.clear();
      });
      return;
    }
    _count++;
  }

  /// Today's count at [nowMs] (unix ms), or 0 when the counter's day is not
  /// today yet (no step since midnight).
  int todayAt(int nowMs) => _loaded && dates.of(nowMs) == _date ? _count : 0;

  /// Writes the count if it changed since the last write.
  Future<void> flush() => _flush();

  Future<void> _flush() {
    final date = _date;
    if (!_loaded || date == null || _count == _stored) return _write;
    final count = _count;
    _stored = count;
    _write = _write.then(
      (_) => summaries.setActivity(
        date,
        now().millisecondsSinceEpoch,
        steps: count,
      ),
    );
    return _write;
  }

  /// Stops counting and writes the count. The timer and the subscription
  /// end at once (before any await).
  Future<void> stop() {
    final sub = _sub;
    _sub = null;
    _timer?.cancel();
    _timer = null;
    sub?.cancel();
    return _flush();
  }
}
