import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/gait/gait_timing.dart';
import 'package:smartinsole/gait/step_counter.dart';
import 'package:smartinsole/rules/step_detector.dart';

import '../storage/storage_rig.dart';
import 'gait_rig.dart';

/// "ก้าววันนี้": today's walking steps of both feet, in
/// `daily_summary.steps`, carried over a restart.
void main() {
  test('counts both feet, writes at most every stepsWriteEvery', () async {
    final rig = StorageRig();
    final steps = StreamController<Step>.broadcast(sync: true);
    var nowMs = bkk(2026, 10, 25, 10);
    final counter = StepCounter(
      steps: steps.stream,
      summaries: rig.summaries,
      dates: bangkok,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    )..start();
    await pumpEventQueue();
    for (var i = 0; i < 5; i++) {
      steps.add(step(FootSide.left, endMs: nowMs + i * 1000.0));
      steps.add(step(FootSide.right, endMs: nowMs + i * 1000.0 + 500));
    }
    expect(counter.todayAt(nowMs), 10);
    expect((await rig.summaries.get('2026-10-25'))?.steps, isNull);
    await counter.flush();
    expect((await rig.summaries.get('2026-10-25'))!.steps, 10);
    await counter.stop();
    await steps.close();
  });

  test('a restart continues from the stored count', () async {
    final rig = StorageRig();
    final at = bkk(2026, 10, 25, 12);
    await rig.summaries.setActivity('2026-10-25', at, steps: 2340);
    final steps = StreamController<Step>.broadcast(sync: true);
    final counter = StepCounter(
      steps: steps.stream,
      summaries: rig.summaries,
      dates: bangkok,
      now: () => DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    )..start();
    // A step that ends while the stored count is still being read.
    steps.add(step(FootSide.left, endMs: at + 100.0));
    await pumpEventQueue();
    steps.add(step(FootSide.right, endMs: at + 600.0));
    expect(counter.todayAt(at), 2342);
    await counter.stop();
    expect((await rig.summaries.get('2026-10-25'))!.steps, 2342);
    await steps.close();
  });

  test('midnight: the old day is written, the new one starts at 0', () async {
    final rig = StorageRig();
    final steps = StreamController<Step>.broadcast(sync: true);
    final before = bkk(2026, 10, 25, 23, 59, 50);
    final after = bkk(2026, 10, 26, 0, 0, 10);
    var nowMs = before;
    final counter = StepCounter(
      steps: steps.stream,
      summaries: rig.summaries,
      dates: bangkok,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    )..start();
    await pumpEventQueue();
    steps.add(step(FootSide.left, endMs: before + 1000.0));
    steps.add(step(FootSide.right, endMs: before + 2000.0));
    expect(counter.todayAt(before), 2);
    nowMs = after;
    // Before the first step after midnight, today is 0.
    expect(counter.todayAt(after), 0);
    steps.add(step(FootSide.left, endMs: after.toDouble()));
    await pumpEventQueue();
    expect(counter.todayAt(after), 1);
    expect((await rig.summaries.get('2026-10-25'))!.steps, 2);
    await counter.stop();
    expect((await rig.summaries.get('2026-10-26'))!.steps, 1);
    await steps.close();
  });

  test('the periodic write', () {
    fakeAsync((async) {
      final rig = StorageRig();
      final steps = StreamController<Step>.broadcast(sync: true);
      final at = bkk(2026, 10, 25, 9);
      final counter = StepCounter(
        steps: steps.stream,
        summaries: rig.summaries,
        dates: bangkok,
        now: () => DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      )..start();
      async.flushMicrotasks();
      steps.add(step(FootSide.left, endMs: at + 500.0));
      int? stored;
      rig.summaries.get('2026-10-25').then((r) => stored = r?.steps);
      async.flushMicrotasks();
      expect(stored, isNull);
      async.elapse(stepsWriteEvery);
      rig.summaries.get('2026-10-25').then((r) => stored = r?.steps);
      async.flushMicrotasks();
      expect(stored, 1);
      counter.stop();
      async.flushMicrotasks();
    });
  });
}
