import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/config/thresholds.dart';

import '../helpers/pump_app.dart';
import 'rules_rig.dart';

/// BACKLOG 51 (S9): the merge reports each step up to `steps.mergeGapMs`
/// late, but a step's times are still its stance's. So at the end of a
/// walk "กำลังเดิน" (`walkingNow`) and the step-based rules end exactly as
/// they did without the merge.
void main() {
  final t = testThresholds;
  final noMerge = Thresholds.parse(
    File(Thresholds.assetPath)
        .readAsStringSync()
        .replaceFirst('"mergeGapMs": ${t.stepMergeGapMs}', '"mergeGapMs": 0'),
  );

  /// One zone far above every pressure threshold: PEAK, PTI and
  /// LOAD_CONCENTRATION all hold while walking.
  final heavy = Gait(
    kpa: [
      for (var c = 0; c < footLayout.zones.length; c++)
        c == 1 ? t.alertKpa * 2 : 0,
    ],
  );

  /// What a screen and the status read, tick by tick.
  String state(RulesRig rig) {
    final v = rig.view();
    final codes = [for (final c in v.conditions) '${c.code.name}/${c.side}']
      ..sort();
    return '${rig.engine.walkingNow(FootSide.left)} '
        '${rig.engine.walkingNow(FootSide.right)} '
        '${v.status.level} $codes';
  }

  test('walkingNow and the step-based rules end as without the merge', () {
    final merged = RulesRig()..stream();
    final plain = RulesRig(thresholds: noMerge)..stream();
    final walk = Duration(milliseconds: (t.ptiMinSteps + 10) * heavy.strideMs);
    for (final rig in [merged, plain]) {
      rig.walkBoth(walk, heavy);
    }
    // The step-based rules hold at the end of the walk, on both feet.
    final atEnd = state(merged);
    expect(atEnd, startsWith('true true'));
    for (final code in ['pressurePti', 'loadConcentration']) {
      expect(atEnd, contains('$code/FootSide.left'));
      expect(atEnd, contains('$code/FootSide.right'));
    }
    expect(state(merged), state(plain));

    // Then standing still, 160 ms at a time, until everything has ended.
    final still = Gait.standing([
      for (var c = 0; c < footLayout.zones.length; c++) 0,
    ]);
    const tick = Duration(milliseconds: 160);
    final ticks = (t.maxStanceMs + t.peakHoldMs + 2000) ~/ 160;
    var ended = false;
    for (var i = 0; i < ticks; i++) {
      for (final rig in [merged, plain]) {
        rig.run(tick, left: still, right: still);
      }
      expect(state(merged), state(plain), reason: 'tick $i after the walk');
      ended |= state(merged).startsWith('false false');
    }
    expect(ended, isTrue);
  });
}
