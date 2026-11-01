import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/gait/model_spec.dart';
import 'package:smartinsole/gait/preprocess.dart';
import 'package:smartinsole/storage/baseline_repository.dart';

import '../helpers/pump_app.dart';

/// Model A preprocessing "ทางเอ" (S9): the app's numbers must be the
/// training script's, bit for bit (tools/model/preprocess.py).
void main() {
  final spec = testModelInput;

  group('model_preprocess.json', () {
    test('the bundled copy is byte-identical to shared/', () {
      // Fix: cp ../shared/model_preprocess.json assets/config/
      expect(
        File(PreprocessSpec.assetPath).readAsBytesSync(),
        File('../shared/model_preprocess.json').readAsBytesSync(),
      );
    });

    test('pubspec.yaml bundles it (the app loads it at start)', () {
      expect(
        File('pubspec.yaml').readAsLinesSync().map((l) => l.trim()),
        contains('- ${PreprocessSpec.assetPath}'),
      );
    });

    test('30 s, median, all channels, Min-Max, no clipping', () {
      expect(testPreprocess.baselineSeconds, 30);
      expect(testPreprocess.baselineDuration, const Duration(seconds: 30));
    });

    test('any other choice is refused, never computed', () {
      final good = jsonDecode(
        File(PreprocessSpec.assetPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final (key, value) in [
        ('baselineStatistic', 'mean'),
        ('baselineChannels', 'fsr'),
        ('scale', 'zscore'),
        ('clip', true),
        ('normalizationMethod', 'minmax'),
        ('version', 2),
      ]) {
        final m = {...good, key: value};
        expect(
          () => PreprocessSpec.parse(jsonEncode(m)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith('model_preprocess.json $key is $value'),
            ),
          ),
          reason: key,
        );
      }
    });
  });

  group('median', () {
    test('odd count: the middle value; even: the mean of the two', () {
      expect(medianOf([3, 1, 2]), 2);
      expect(medianOf([4, 1, 3, 2]), 2.5);
      expect(medianOf([-1]), -1);
      expect(() => medianOf([]), throwsArgumentError);
    });

    test('the input list is left unsorted', () {
      final v = [3.0, 1.0, 2.0];
      medianOf(v);
      expect(v, [3.0, 1.0, 2.0]);
    });
  });

  group('shared/test_vectors/model_preprocess (Python)', () {
    final doc = jsonDecode(
      File('../shared/test_vectors/model_preprocess/vectors.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    List<double> floats(Object? v) => [
      for (final x in v! as List) (x as num).toDouble(),
    ];
    List<List<double>> table(Object? v) => [
      for (final r in v! as List) floats(r),
    ];
    String bits(double v) {
      final b = ByteData(4)..setFloat32(0, v);
      return [
        for (var i = 0; i < 4; i++)
          b.getUint8(i).toRadixString(16).padLeft(2, '0'),
      ].join();
    }

    test('made for this model_input.json', () {
      expect(doc['modelInputVersion'], spec.version);
      expect(doc['preprocessVersion'], testPreprocess.version);
    });

    for (final c in doc['cases'] as List) {
      final kase = c as Map<String, dynamic>;
      final exp = kase['expected'] as Map<String, dynamic>;
      test('${kase['name']}: same baseline and float32 bits', () {
        final cal = kase['calibration'] as Map<String, dynamic>;
        final left = footBaseline(table(cal['L']));
        final right = footBaseline(table(cal['R']));
        final foot = exp['footBaseline'] as Map<String, dynamic>;
        expect(left, floats(foot['L']));
        expect(right, floats(foot['R']));
        final baseline = modelBaseline(left, right);
        expect(baseline, floats(exp['baseline']));

        final norm = Normalization(
          channels: spec.channels,
          min: floats(kase['min']),
          max: floats(kase['max']),
        );
        final rows = table(kase['rows']);
        final window = normalizeWindow(rows, baseline, norm);
        final want = [
          for (final r in exp['windowF32Bits'] as List)
            for (final b in r as List) b as String,
        ];
        expect(window, hasLength(want.length));
        var outside = 0;
        for (var i = 0; i < window.length; i++) {
          expect(bits(window[i]), want[i], reason: 'value $i');
          if (window[i] < 0 || window[i] > 1) outside++;
        }
        // No clipping: the vectors put values outside 0–1 on purpose.
        expect(outside, greaterThan(0));
      });
    }
  });

  group('modelBaselineOf', () {
    FootBaseline b(FootSide side, String id, double v) => FootBaseline(
      side: side,
      insoleId: id,
      recordedAtMs: 0,
      sampleCount: 1500,
      values: List.filled(14, v),
    );
    final stored = [
      b(FootSide.left, 'L-1', 1),
      b(FootSide.right, 'R-1', 2),
      b(FootSide.left, 'L-2', 3),
    ];

    test('both connected insoles known: left 14, then right 14', () {
      final m = modelBaselineOf(stored, leftId: 'L-2', rightId: 'R-1')!;
      expect(m, [...List.filled(14, 3.0), ...List.filled(14, 2.0)]);
    });

    test('either foot without a baseline, or not connected: none', () {
      expect(modelBaselineOf(stored, leftId: 'L-1', rightId: 'R-9'), isNull);
      expect(modelBaselineOf(stored, leftId: null, rightId: 'R-1'), isNull);
      // A baseline belongs to its foot: a right insole's id on the left
      // finds nothing.
      expect(modelBaselineOf(stored, leftId: 'R-1', rightId: 'R-1'), isNull);
    });
  });

  test('normalizeWindow refuses a baseline of the wrong length', () {
    final norm = demoNorm(spec);
    expect(
      () => normalizeWindow([List.filled(28, 0)], List.filled(14, 0), norm),
      throwsArgumentError,
    );
  });
}

Normalization demoNorm(ModelInputSpec spec) => Normalization(
  channels: spec.channels,
  min: List.filled(spec.channels.length, 0),
  max: List.filled(spec.channels.length, 1),
);
