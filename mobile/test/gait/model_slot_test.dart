import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/model_channels.dart';
import 'package:smartinsole/gait/gait_class.dart';
import 'package:smartinsole/gait/model_classifier.dart';
import 'package:smartinsole/gait/model_spec.dart';
import 'package:smartinsole/gait/model_window.dart';

import '../helpers/pump_app.dart';
import 'gait_rig.dart';

/// The Model A slot (DATA-CONTRACT §7): the files it reads, the checks it
/// makes, and the proof (with the dummy's check.json) that the app feeds
/// the model the same normalised window as the Python scripts.
void main() {
  final spec = testModelInput;
  final normJson = utf8.decode(dummyFile(normalizationFileName));
  final check =
      jsonDecode(utf8.decode(dummyFile(checkFileName))) as Map<String, dynamic>;

  group('model_input.json', () {
    test('the bundled copy is byte-identical to shared/', () {
      // Fix: cp ../shared/model_input.json assets/config/
      expect(
        File(ModelInputSpec.assetPath).readAsBytesSync(),
        File('../shared/model_input.json').readAsBytesSync(),
      );
    });

    test('window 2 s, stride 1 s, the app\'s 24 channels', () {
      expect(spec.windowMs, 2000);
      expect(spec.strideMs, 1000);
      expect(spec.samplePeriodMs, 20);
      expect(spec.channels, modelChannelNames);
    });
  });

  group('normalization.json', () {
    Map<String, dynamic> dummy() =>
        jsonDecode(normJson) as Map<String, dynamic>;

    test('the dummy parses', () {
      final n = Normalization.parse(normJson, spec);
      expect(n.channels, spec.channels);
      expect(n.mean, hasLength(24));
    });

    test('a different channel order is refused, never run', () {
      final m = dummy();
      final ch = [...m['channels'] as List];
      final first = ch[0];
      ch[0] = ch[12];
      ch[12] = first;
      m['channels'] = ch;
      expect(
        () => Normalization.parse(jsonEncode(m), spec),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('channel 0 is R_fsr0_kpa'),
          ),
        ),
      );
    });

    test('a std of 0 is refused', () {
      final m = dummy();
      (m['std'] as List)[5] = 0;
      expect(
        () => Normalization.parse(jsonEncode(m), spec),
        throwsFormatException,
      );
    });

    test('a missing channel is refused', () {
      final m = dummy();
      (m['channels'] as List).removeLast();
      expect(
        () => Normalization.parse(jsonEncode(m), spec),
        throwsFormatException,
      );
    });
  });

  group('loadModelSlot', () {
    Future<ModelSlot> load(
      Map<String, String> files, {
      FakeRunner? runner,
      Object? fail,
    }) => loadModelSlot(
      bundle: FakeBundle({
        for (final e in files.entries)
          '$releaseModelDir/${e.key}': utf8Bytes(e.value),
      }),
      dir: releaseModelDir,
      spec: spec,
      startRunner: (_, _) async {
        if (fail != null) throw fail;
        return runner ?? FakeRunner([1, 0, 0, 0, 0]);
      },
    );

    test('empty slot: missing, the rules classify', () async {
      expect(await load({}), isA<ModelMissing>());
    });

    test(
      'model without normalization.json: invalid, with the reason',
      () async {
        final slot = await load({modelFileName: 'x'});
        expect(
          slot,
          isA<ModelInvalid>().having(
            (s) => s.reason,
            'reason',
            'normalization.json missing',
          ),
        );
      },
    );

    test('wrong channel order: invalid', () async {
      final m = jsonDecode(normJson) as Map<String, dynamic>;
      m['channels'] = (m['channels'] as List).reversed.toList();
      final slot = await load({
        modelFileName: 'x',
        normalizationFileName: jsonEncode(m),
      });
      expect(slot, isA<ModelInvalid>());
    });

    test(
      'a model of the wrong shapes: invalid, with the runner\'s reason',
      () async {
        final slot = await load({
          modelFileName: 'x',
          normalizationFileName: normJson,
        }, fail: const FormatException('outputs are [[1, 4]]'));
        expect(
          slot,
          isA<ModelInvalid>().having(
            (s) => s.reason,
            'r',
            'outputs are [[1, 4]]',
          ),
        );
      },
    );

    test('both files: ready', () async {
      final slot = await load({
        modelFileName: 'x',
        normalizationFileName: normJson,
      });
      expect(slot, isA<ModelReady>());
    });
  });

  group('ModelClassifier', () {
    test('argmax is the class, max the confidence (§7.2)', () {
      final r = ModelClassifier.resultOf([0.1, 0.05, 0.7, 0.1, 0.05], 5);
      expect(r.gaitClass, GaitClass.toeWalking);
      expect(r.confidence, 0.7);
      expect(r.source, GaitSource.model);
      expect(r.probs, hasLength(5));
    });

    test('GaitClass index order is the contract\'s', () {
      expect(
        [for (final c in GaitClass.values) c.id],
        ['normal', 'antalgic', 'toe_walking', 'heel_walking', 'rotated_foot'],
      );
    });

    test('runs are queued, never overlapped', () async {
      final runner = FakeRunner([1, 0, 0, 0, 0]);
      final model = ModelClassifier(
        runner: runner,
        normalization: Normalization.parse(normJson, spec),
      );
      final rows = [
        for (final r in check['rows'] as List)
          [for (final v in r as List) (v as num).toDouble()],
      ];
      await Future.wait([model.runRows(rows), model.runRows(rows)]);
      expect(runner.windows, hasLength(2));
      expect(model.stats.count, 2);
      expect(model.busy, isFalse);
    });
  });

  group('check.json (the dummy, tools/model/make_dummy_model.py)', () {
    test('the app\'s window from the capture fixture equals Python\'s', () {
      // Through the app's own path: samples → ModelWindowBuilder (pairFeet,
      // modelRow) → normalizeWindow. A swapped channel or foot fails here.
      final (left, right) = fixtureSamples(spec.windowSamples);
      final builder = ModelWindowBuilder(spec)
        ..add(batch(FootSide.left, left))
        ..add(batch(FootSide.right, right));
      final rows = builder.latestRows();
      expect(rows, hasLength(spec.windowSamples));
      final window = normalizeWindow(
        rows!,
        Normalization.parse(normJson, spec),
      );
      final expected = [
        for (final r in check['window'] as List)
          for (final v in r as List) (v as num).toDouble(),
      ];
      expect(window, hasLength(expected.length));
      for (var i = 0; i < window.length; i++) {
        expect(window[i], closeTo(expected[i], 1e-6), reason: 'value $i');
      }
    });

    test(
      'runModelCheck passes with the right outputs, fails otherwise',
      () async {
        final probs = [
          for (final v in check['gait_probs'] as List) (v as num).toDouble(),
        ];
        final emb = [
          for (final v in check['gait_embedding'] as List)
            (v as num).toDouble(),
        ];
        final runner = FakeRunner(probs, embedding: emb);
        final model = ModelClassifier(
          runner: runner,
          normalization: Normalization.parse(normJson, spec),
        );
        final bundle = FakeBundle({
          '$dummyModelDir/$checkFileName': dummyFile(checkFileName),
        });
        final ok = await runModelCheck(
          bundle: bundle,
          dir: dummyModelDir,
          classifier: model,
        );
        expect(ok!.passed, isTrue);
        expect(ok.windowMaxDiff, lessThan(1e-6));

        runner.probs = [...probs]..[0] += 0.01;
        final bad = await runModelCheck(
          bundle: bundle,
          dir: dummyModelDir,
          classifier: model,
        );
        expect(bad!.passed, isFalse);
      },
    );

    test('no check file (a real model): no check', () async {
      final model = ModelClassifier(
        runner: FakeRunner([1, 0, 0, 0, 0]),
        normalization: Normalization.parse(normJson, spec),
      );
      expect(
        await runModelCheck(
          bundle: FakeBundle({}),
          dir: releaseModelDir,
          classifier: model,
        ),
        isNull,
      );
    });
  });

  group('ModelWindowBuilder', () {
    test('a gap inside the window: no window', () {
      final (left, right) = fixtureSamples(spec.windowSamples + 5);
      final builder = ModelWindowBuilder(spec)
        ..add(batch(FootSide.left, left.sublist(0, 50)))
        ..add(batch(FootSide.left, left.sublist(53)))
        ..add(batch(FootSide.right, right));
      expect(builder.latestRows(), isNull);
    });

    test('lost packets clear that foot', () {
      final (left, right) = fixtureSamples(spec.windowSamples + 10);
      final builder = ModelWindowBuilder(spec)
        ..add(batch(FootSide.left, left.sublist(0, 100)))
        ..add(batch(FootSide.right, right))
        ..add(batch(FootSide.left, left.sublist(100), missingBefore: 1));
      expect(builder.latestRows(), isNull);
    });

    test('too few rows: no window', () {
      final (left, right) = fixtureSamples(spec.windowSamples - 1);
      final builder = ModelWindowBuilder(spec)
        ..add(batch(FootSide.left, left))
        ..add(batch(FootSide.right, right));
      expect(builder.latestRows(), isNull);
    });
  });
}
