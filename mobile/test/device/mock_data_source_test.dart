import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/mock_data_source.dart';

/// `shared/thresholds.json`: the numbers each preset must land against.
final thresholds = jsonDecode(
  File('../shared/thresholds.json').readAsStringSync(),
) as Map<String, Object?>;
double th(String group, String key) =>
    ((thresholds[group]! as Map<String, Object?>)[key]! as num).toDouble();

final watchKpa = th('pressure', 'watchKpa');
final alertKpa = th('pressure', 'alertKpa');
final ptiKpaS = th('pressure', 'ptiKpaS');
final deltaC = th('temperature', 'deltaC');
final concentrationPct = th('asymmetry', 'concentrationPct');
final walkingAccelG = th('motion', 'walkingAccelG');
final walkingWindowMs = th('motion', 'walkingWindowMs');

/// Contract §8.3 `BATTERY_LOW` (added to thresholds.json in S5,
/// BACKLOG 30).
final batteryLowPct = th('battery', 'lowPct');

const sampleS = 0.02;

/// What one foot produced over a run.
class FootRun {
  final frames = <SensorFrame>[];
  final temps = <TempFrame>[];
  final statuses = <StatusFrame>[];
  final states = <LinkState>[];

  List<List<double>> get kpa => [
    for (final f in frames)
      for (final s in f.samples) s.fsrKpa,
  ];

  /// Complete stances: runs where any channel carries load, without the
  /// partial first and last ones.
  List<List<List<double>>> get stances {
    final out = <List<List<double>>>[];
    var cur = <List<double>>[];
    for (final k in kpa) {
      if (k.reduce(math.max) > 1) {
        cur.add(k);
      } else if (cur.isNotEmpty) {
        out.add(cur);
        cur = [];
      }
    }
    return out.length > 2 ? out.sublist(1) : const [];
  }

  double get maxPeak => kpa.expand((k) => k).reduce(math.max);

  /// Highest kPa per channel over the run.
  List<double> get channelPeaks => [
    for (var ch = 0; ch < kpa.first.length; ch++)
      kpa.map((k) => k[ch]).reduce(math.max),
  ];

  /// Per-step PTI, kPa·s: as max-over-channels, and per channel.
  double get maxStepPti => stances
      .map((st) => st.fold(0.0, (a, k) => a + k.reduce(math.max) * sampleS))
      .reduce(math.max);
  double get maxChannelPti => stances
      .map(
        (st) => [
          for (var ch = 0; ch < 6; ch++)
            st.fold(0.0, (a, k) => a + k[ch] * sampleS),
        ].reduce(math.max),
      )
      .reduce(math.max);

  /// Per-step channel peaks: the highest share of their sum, %.
  double get maxConcentration => stances
      .map((st) {
        final peaks = [
          for (var ch = 0; ch < 6; ch++) st.map((k) => k[ch]).reduce(math.max),
        ];
        return peaks.reduce(math.max) / peaks.reduce((a, b) => a + b) * 100;
      })
      .reduce(math.max);

  /// Contract §8.3.2: mean |accel magnitude − 1 g| over the walking window,
  /// the highest over the run.
  double get maxWalkingAccel {
    final mags = [
      for (final f in frames)
        for (final s in f.samples)
          (math.sqrt(s.accelG.fold(0.0, (a, v) => a + v * v)) - 1).abs(),
    ];
    final n = (walkingWindowMs / 20).round();
    var best = 0.0;
    for (var i = 0; i + n <= mags.length; i++) {
      best = math.max(best, mags.sublist(i, i + n).reduce((a, b) => a + b) / n);
    }
    return best;
  }

  List<double> get forefoot => [for (final t in temps) t.packet.forefootC!];
  int get battery => statuses.last.packet.batteryPct;
}

/// Runs both mock feet under [preset] for [seconds].
(FootRun, FootRun) runPreset(MockPreset preset, {int seconds = 65}) {
  late (FootRun, FootRun) result;
  fakeAsync((async) {
    final mock = MockInsoles(
      preset,
      now: async.getClock(DateTime(2026, 10, 22, 9)).now,
    );
    final runs = {for (final s in FootSide.values) s: FootRun()};
    for (final side in FootSide.values) {
      final src = mock.source(side);
      final r = runs[side]!;
      src.frames.listen(r.frames.add);
      src.temps.listen(r.temps.add);
      src.statuses.listen(r.statuses.add);
      src.states.listen(r.states.add);
      src.connect();
    }
    async.elapse(Duration(seconds: seconds));
    mock.dispose();
    result = (runs[FootSide.left]!, runs[FootSide.right]!);
  });
  return result;
}

void expectNothingLevel3(FootRun f, String foot) {
  expect(f.maxPeak, lessThan(alertKpa), reason: '$foot peak');
  expect(f.maxStepPti, lessThan(ptiKpaS), reason: '$foot PTI');
  expect(f.maxChannelPti, lessThan(ptiKpaS), reason: '$foot channel PTI');
  expect(f.maxConcentration, lessThan(concentrationPct), reason: foot);
}

void expectSafe(FootRun f, String foot) {
  expectNothingLevel3(f, foot);
  expect(f.maxPeak, lessThan(watchKpa), reason: '$foot peak');
}

void expectDeltaBelow(FootRun l, FootRun r) {
  for (var i = 0; i < math.min(l.temps.length, r.temps.length); i++) {
    expect((l.forefoot[i] - r.forefoot[i]).abs(), lessThan(deltaC));
  }
}

void main() {
  group('presets land in their thresholds.json bands', () {
    test('safe: nothing triggers', () {
      final (l, r) = runPreset(MockPreset.safe);
      expectSafe(l, 'left');
      expectSafe(r, 'right');
      expectDeltaBelow(l, r);
      expect(l.battery, greaterThanOrEqualTo(batteryLowPct));
      // Walking, by the §8.3.2 gate, so a peak rule could apply at all.
      expect(l.maxWalkingAccel, greaterThanOrEqualTo(walkingAccelG));
    });

    test('safeOrangeDot: a level-2 peak only (Safe + orange dot)', () {
      final (l, r) = runPreset(MockPreset.safeOrangeDot);
      expect(l.maxPeak, greaterThan(watchKpa)); // PRESSURE_WATCH, level 2
      expectNothingLevel3(l, 'left');
      expectSafe(r, 'right');
      expectDeltaBelow(l, r);
    });

    test('watch: level-3 sustained forefoot load (PRESSURE_PTI)', () {
      final (l, r) = runPreset(MockPreset.watch);
      expect(l.maxChannelPti, greaterThan(ptiKpaS));
      expect(l.maxStepPti, greaterThan(ptiKpaS));
      expect(l.maxConcentration, lessThan(concentrationPct));
      // Zone bands of board HomeDWatch (DESIGN-SPEC §6).
      const low = 0, medium = 1, high = 2;
      int band(double k) => k > alertKpa ? high : (k > watchKpa ? medium : low);
      expect(
        [for (final k in l.channelPeaks) band(k)],
        [
          medium, high, medium, low, low, medium, //
        ],
      );
      expect(
        [for (final k in r.channelPeaks) band(k)],
        [
          low, medium, low, low, low, medium, //
        ],
      );
      // It is the forefoot: meta1 (channel 1) carries the highest PTI.
      final st = l.stances.first;
      final pti = [
        for (var ch = 0; ch < 6; ch++)
          st.fold(0.0, (a, k) => a + k[ch] * sampleS),
      ];
      expect(pti.indexOf(pti.reduce(math.max)), 1);
      expectNothingLevel3(r, 'right'); // orange dots only
      expectDeltaBelow(l, r);
    });

    test('rest: right forefoot warmer beyond ΔT on consecutive readings', () {
      final (l, r) = runPreset(MockPreset.rest);
      final n = math.min(l.temps.length, r.temps.length);
      expect(n, greaterThanOrEqualTo(th('temperature', 'consecutiveReadings')));
      for (var i = 0; i < n; i++) {
        expect(r.forefoot[i] - l.forefoot[i], greaterThan(deltaC));
      }
      expectSafe(l, 'left');
      expectSafe(r, 'right');
    });

    test('lowBattery: safe data, left battery below BATTERY_LOW', () {
      final (l, r) = runPreset(MockPreset.lowBattery);
      expect(l.battery, lessThan(batteryLowPct));
      expect(r.battery, greaterThanOrEqualTo(batteryLowPct));
      expectSafe(l, 'left');
      expectSafe(r, 'right');
    });

    test('noData: neither foot connects', () {
      final (l, r) = runPreset(MockPreset.noData, seconds: 5);
      for (final f in [l, r]) {
        expect(f.frames, isEmpty);
        expect(f.states.last, isA<LinkIdle>());
      }
    });

    test('oneFootMissing: left streams, right never connects', () {
      final (l, r) = runPreset(MockPreset.oneFootMissing, seconds: 5);
      expect(l.states.last, isA<LinkStreaming>());
      expect(l.frames, isNotEmpty);
      expect(r.frames, isEmpty);
      expect(r.states.last, isA<LinkIdle>());
    });
  });

  group('stream shape', () {
    test('8 samples every 160 ms; t0 +160; seq from 0; one session', () {
      final (l, r) = runPreset(MockPreset.safe, seconds: 11);
      for (final f in [l, r]) {
        // 0.6 s connecting, then 6.25 packets/s.
        expect(f.frames.length, inInclusiveRange(64, 65));
        for (var i = 0; i < f.frames.length; i++) {
          final fr = f.frames[i];
          expect(fr.seq, i);
          expect(fr.session, 1);
          expect(fr.missingBefore, 0);
          expect(fr.samples, hasLength(8));
          if (i > 0) {
            expect(
              fr.samples.first.deviceMs -
                  f.frames[i - 1].samples.first.deviceMs,
              160,
            );
          }
        }
      }
      // Two boards, two boot clocks.
      expect(
        l.frames.first.samples.first.deviceMs,
        isNot(r.frames.first.samples.first.deviceMs),
      );
    });

    test('kPa comes from the raw ADC through the real conversion', () {
      final (l, _) = runPreset(MockPreset.safe, seconds: 3);
      final s = l.frames
          .expand((f) => f.samples)
          .firstWhere((s) => s.fsrAdc.any((a) => a > 0));
      expect(s.fsrAdc, hasLength(6));
      expect(s.fsrKpa.reduce(math.max), greaterThan(1));
    });

    test('a preset change applies live to both feet', () {
      fakeAsync((async) {
        final mock = MockInsoles(
          MockPreset.safe,
          now: async.getClock(DateTime(2026, 10, 22, 9)).now,
        );
        final l = mock.source(FootSide.left);
        final r = mock.source(FootSide.right);
        final batteries = <int>[];
        l.statuses.listen((s) => batteries.add(s.packet.batteryPct));
        l.connect();
        r.connect();
        async.elapse(const Duration(seconds: 1));
        expect(r.state, isA<LinkStreaming>());

        mock.preset = MockPreset.oneFootMissing;
        expect(r.state, isA<LinkIdle>());
        mock.preset = MockPreset.lowBattery;
        async.elapse(const Duration(seconds: 1));
        expect(r.state, isA<LinkStreaming>());
        expect(batteries.last, lessThan(batteryLowPct));
        mock.dispose();
      });
    });
  });

  group('debug builds only', () {
    test('release builds never get a mock, whatever the define says', () {
      expect(mockPresetFor('safe', debugBuild: false), isNull);
      expect(mockPresetFor('', debugBuild: true), isNull);
      expect(mockPresetFor('watch', debugBuild: true), MockPreset.watch);
    });

    test('an unknown preset name fails loudly in debug', () {
      expect(
        () => mockPresetFor('wtach', debugBuild: true),
        throwsArgumentError,
      );
    });
  });
}
