import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smartinsole/device/model_channels.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/gait/gait_classifier.dart';
import 'package:smartinsole/rules/step_detector.dart';

/// An asset bundle holding exactly [files] (key → bytes).
class FakeBundle extends CachingAssetBundle {
  FakeBundle(this.files);

  final Map<String, Uint8List> files;

  @override
  Future<ByteData> load(String key) async {
    final f = files[key];
    if (f == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(f);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode((await load(key)).buffer.asUint8List());
}

Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A model that always answers [probs]; records every window it gets.
class FakeRunner implements ModelRunner {
  FakeRunner(this.probs, {this.embedding = const []});

  List<double> probs;
  final List<double> embedding;
  final windows = <Float32List>[];
  bool closed = false;

  /// Every run throws while set (an inference failure).
  bool fail = false;

  @override
  Future<ModelOutput> run(Float32List window) async {
    windows.add(window);
    if (fail) throw StateError('inference failed');
    return ModelOutput(probs: probs, embedding: embedding);
  }

  @override
  Future<void> close() async => closed = true;
}

/// One walking step ending at [endMs] with [ptiKpaS] per zone.
Step step(
  FootSide side, {
  double endMs = 1000,
  double durationMs = 600,
  List<double> ptiKpaS = const [10, 10, 10, 10, 10, 10],
  List<double>? peakKpa,
}) => Step(
  side: side,
  startMs: endMs - durationMs,
  endMs: endMs,
  peakKpa: peakKpa ?? List.filled(ptiKpaS.length, 50),
  ptiKpaMs: [for (final v in ptiKpaS) v * 1000],
);

/// `shared/capture_fixture/schema2/expected.json`: the 28-channel rows the
/// app's pairFeet + modelRow make from the fixture's samples, and their
/// (left, right) times.
Map<String, dynamic> captureFixture() => jsonDecode(
  File('../shared/capture_fixture/schema2/expected.json').readAsStringSync(),
) as Map<String, dynamic>;

/// The fixture's first [n] rows back as the two feet's samples.
(List<FootSample>, List<FootSample>) fixtureSamples(int n) {
  final fx = captureFixture();
  final pairs = fx['pairs'] as List;
  final rows = fx['rows'] as List;
  final left = <FootSample>[];
  final right = <FootSample>[];
  for (var i = 0; i < n; i++) {
    final (l, r) = (pairs[i] as List, rows[i] as List);
    final v = [for (final x in r) (x as num).toDouble()];
    const n = modelFsrCount;
    FootSample s(double t, List<double> foot) => FootSample(
      unixMs: t,
      deviceMs: t.round(),
      fsrAdc: List.filled(n, 0),
      fsrKpa: foot.sublist(0, n),
      accelG: foot.sublist(n, n + 3),
      gyroDps: foot.sublist(n + 3, n + 6),
    );
    left.add(s((l[0] as num).toDouble(), v.sublist(0, modelChannelsPerFoot)));
    right.add(
      s(
        (l[1] as num).toDouble(),
        v.sublist(modelChannelsPerFoot, modelChannelCount),
      ),
    );
  }
  return (left, right);
}

FootBatch batch(
  FootSide side,
  List<FootSample> samples, {
  int session = 1,
  int missingBefore = 0,
}) => FootBatch(
  side: side,
  session: session,
  seq: 0,
  missingBefore: missingBefore,
  receivedAt: DateTime.utc(2026),
  saturated: false,
  calibrating: false,
  samples: samples,
);

/// The dummy model's files, from disk.
Uint8List dummyFile(String name) =>
    File('assets/models_dummy/$name').readAsBytesSync();
