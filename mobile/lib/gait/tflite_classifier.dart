import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'gait_class.dart';
import 'gait_classifier.dart';
import 'gait_timing.dart';
import 'model_spec.dart';

// The only file that imports tflite_flutter.

/// Model A on LiteRT (tflite_flutter), in its own long-lived isolate so an
/// inference never blocks the UI or the 50 Hz path.
///
/// The interpreter is created inside that isolate and never leaves it;
/// only the window's bytes go in and the two output arrays come back.
/// (tflite_flutter's `IsolateInterpreter` shares the interpreter's address
/// between isolates and re-allocates its tensors on every run, which left
/// stale tensor handles and crashed in the S8A spike.)
class TfliteModelRunner implements ModelRunner {
  TfliteModelRunner._(this._isolate, this._send, this._replies, this._port);

  final Isolate _isolate;
  final SendPort _send;
  final StreamIterator<Object?> _replies;
  final ReceivePort _port;

  /// Loads [model] and checks it against the contract: one float32 input
  /// `[1, windowSamples, channels]`, two float32 outputs `[1, 5]`
  /// (`gait_probs`) and `[1, 32]` (`gait_embedding`), in either order.
  /// Throws [FormatException] with the reason otherwise.
  static Future<TfliteModelRunner> start(
    Uint8List model,
    ModelInputSpec spec,
  ) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_worker, (
      port.sendPort,
      TransferableTypedData.fromList([model]),
      [1, spec.windowSamples, spec.channels.length],
    ), debugName: 'gait-model');
    final replies = StreamIterator<Object?>(port);
    await replies.moveNext();
    final first = replies.current;
    if (first is! SendPort) {
      isolate.kill();
      port.close();
      throw FormatException('$first');
    }
    return TfliteModelRunner._(isolate, first, replies, port);
  }

  @override
  Future<ModelOutput> run(Float32List window) async {
    _send.send(
      TransferableTypedData.fromList([
        window.buffer.asUint8List(window.offsetInBytes, window.lengthInBytes),
      ]),
    );
    await _replies.moveNext();
    final reply = _replies.current;
    if (reply is String) throw StateError(reply);
    final (probs, embedding) = reply! as (Float32List, Float32List);
    return ModelOutput(probs: probs, embedding: embedding);
  }

  @override
  Future<void> close() async {
    _send.send(null);
    await _replies.cancel();
    _port.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

void _worker((SendPort, TransferableTypedData, List<int>) args) {
  final (reply, modelData, inputShape) = args;
  final Interpreter interp;
  try {
    interp = Interpreter.fromBuffer(modelData.materialize().asUint8List());
  } on Object catch (e) {
    reply.send('model_a.tflite could not be loaded: $e');
    return;
  }
  final problem = _checkShapes(interp, inputShape);
  if (problem != null) {
    interp.close();
    reply.send(problem);
    return;
  }
  final outs = interp.getOutputTensors();
  final probsAt = outs.indexWhere(
    (t) => t.shape.last == GaitClass.values.length,
  );
  final embAt = outs.indexWhere((t) => t.shape.last == gaitEmbeddingSize);

  final port = ReceivePort();
  reply.send(port.sendPort);
  port.listen((msg) {
    if (msg == null) {
      interp.close();
      port.close();
      return;
    }
    try {
      interp.getInputTensor(0).data = (msg as TransferableTypedData)
          .materialize()
          .asUint8List();
      interp.invoke();
      reply.send((_floats(interp, probsAt), _floats(interp, embAt)));
    } on Object catch (e) {
      reply.send('inference failed: $e');
    }
  });
}

String? _checkShapes(Interpreter interp, List<int> inputShape) {
  final ins = interp.getInputTensors();
  if (ins.length != 1) return 'model has ${ins.length} inputs, expected 1';
  if (!listEquals(ins.single.shape, inputShape) ||
      ins.single.type != TensorType.float32) {
    return 'input is ${ins.single.shape} ${ins.single.type}, '
        'expected $inputShape float32';
  }
  final outs = interp.getOutputTensors();
  final shapes = [for (final t in outs) t.shape];
  final want = [
    [1, GaitClass.values.length],
    [1, gaitEmbeddingSize],
  ];
  final ok =
      outs.length == want.length &&
      outs.every((t) => t.type == TensorType.float32) &&
      want.every((w) => shapes.where((s) => listEquals(s, w)).length == 1);
  return ok ? null : 'outputs are $shapes, expected $want float32';
}

Float32List _floats(Interpreter interp, int index) {
  final data = interp.getOutputTensor(index).data;
  return Float32List.fromList(
    data.buffer.asFloat32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ Float32List.bytesPerElement,
    ),
  );
}
