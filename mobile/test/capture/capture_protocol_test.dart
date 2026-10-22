import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_protocol.dart';

void main() {
  group('subject code (IRB: codes only)', () {
    test('accepts SI-nnn and TEST-nnn, trimmed and upper-cased', () {
      expect(SubjectCode.parse('SI-001')!.number, 1);
      expect(SubjectCode.parse(' si-030 ')!.code, 'SI-030');
      expect(SubjectCode.parse('SI-012')!.rehearsal, isFalse);
      expect(SubjectCode.parse('TEST-002')!.rehearsal, isTrue);
    });

    test('rejects names, free text and malformed codes', () {
      for (final bad in [
        '',
        'Somchai',
        'สมชาย ใจดี',
        'SI-1',
        'SI-0001',
        'SI-000',
        'SI 001',
        'SI-001 Somchai',
        '1234567890123',
      ]) {
        expect(SubjectCode.parse(bad), isNull, reason: bad);
      }
    });

    test('antalgic pain side: odd number left, even right', () {
      expect(SubjectCode.parse('SI-001')!.painSide, FootSide.left);
      expect(SubjectCode.parse('SI-002')!.painSide, FootSide.right);
      expect(SubjectCode.parse('SI-029')!.painSide, FootSide.left);
      expect(SubjectCode.parse('SI-030')!.painSide, FootSide.right);
    });
  });

  group('trial order', () {
    test('normal first, then a permutation of the 4 abnormal gaits', () {
      for (var seed = 0; seed < 200; seed++) {
        final o = trialOrder(seed);
        expect(o.first, GaitClass.normal);
        expect(o.skip(1).toSet(), {
          GaitClass.antalgic,
          GaitClass.toeWalking,
          GaitClass.heelWalking,
          GaitClass.rotatedFoot,
        });
        expect(o, hasLength(5));
      }
    });

    test('the same seed gives the same order', () {
      expect(trialOrder(12345), trialOrder(12345));
    });

    test('1000 seeds cover all 24 orders', () {
      final r = math.Random(1);
      final seen = {
        for (var i = 0; i < 1000; i++)
          trialOrder(newOrderSeed(r)).map((g) => g.id).join(','),
      };
      expect(seen, hasLength(24));
    });
  });

  test('gait ids and model indices are contract §7.2', () {
    expect(
      {for (final g in GaitClass.values) g.modelIndex: g.id},
      {
        0: 'normal',
        1: 'antalgic',
        2: 'toe_walking',
        3: 'heel_walking',
        4: 'rotated_foot',
      },
    );
  });

  test('timings: doc 03 for the study, short only for rehearsal codes', () {
    expect(
      CaptureTimings.of(SubjectCode.parse('SI-001')!),
      same(CaptureTimings.study),
    );
    expect(CaptureTimings.study.practice, const Duration(seconds: 30));
    expect(CaptureTimings.study.trial, const Duration(minutes: 3));
    expect(CaptureTimings.study.calibration, const Duration(seconds: 30));
    expect(
      CaptureTimings.of(SubjectCode.parse('TEST-001')!),
      same(CaptureTimings.rehearsal),
    );
  });
}
