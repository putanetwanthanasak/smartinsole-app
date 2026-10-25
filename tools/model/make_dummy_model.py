# /// script
# requires-python = "==3.12.*"
# dependencies = ["tensorflow-cpu==2.20.*", "numpy<2.3"]
# ///
"""Make the dummy Model A for the app's model slot (S8A).

The weights are untrained (fixed seed): the file only proves the slot, i.e.
that the app loads a model of the contract's shapes, feeds it the 24
channels in the order of shared/model_input.json, normalises them with
normalization.json, and runs it fast enough. It is never a gait result.

DATA-CONTRACT §7.1/§7.2: input [1, 100, 24] float32; outputs gait_probs
[1, 5] (softmax) and gait_embedding [1, 32] (the layer before softmax). The
model is converted with TFLite builtin ops only; the real model must be too
(the app bundles no Flex delegate).

Writes, in mobile/assets/models_dummy/:
  model_a.tflite      the dummy model
  normalization.json  per-channel mean/std over the capture fixture's rows
  check.json          the fixture's first 100 rows, the normalised window,
                      and this interpreter's outputs for it (the app's
                      on-device check compares against these)

Run from the repo root:  uv run tools/model/make_dummy_model.py
"""

import json
import os
import pathlib
import tempfile

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np  # noqa: E402
import tensorflow as tf  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODEL_INPUT = ROOT / "shared" / "model_input.json"
FIXTURE = ROOT / "shared" / "capture_fixture" / "expected.json"
OUT = ROOT / "mobile" / "assets" / "models_dummy"
SEED = 20261025
CLASSES = 5
EMBEDDING = 32


def build_model(window: int, channels: int) -> tf.keras.Model:
    tf.keras.utils.set_random_seed(SEED)
    x_in = tf.keras.Input(shape=(window, channels), batch_size=1, name="window")
    x = tf.keras.layers.Conv1D(32, 5, padding="same", activation="relu")(x_in)
    x = tf.keras.layers.MaxPooling1D(2)(x)
    # Unrolled: a looped Keras 3 LSTM needs TensorList ops, which are not
    # TFLite builtins (the converter below refuses them).
    x = tf.keras.layers.LSTM(32, unroll=True)(x)
    emb = tf.keras.layers.Dense(EMBEDDING, activation="relu", name="gait_embedding")(x)
    probs = tf.keras.layers.Dense(CLASSES, activation="softmax", name="gait_probs")(emb)
    return tf.keras.Model(x_in, {"gait_probs": probs, "gait_embedding": emb})


def convert(model: tf.keras.Model) -> bytes:
    # Through Keras's own SavedModel export, which freezes the weights into
    # constants (a tf.function or tf.Module conversion of a Keras 3 model
    # keeps them as resource variables, and the interpreter then reads
    # uninitialised memory). The input shape, batch 1 included, comes from
    # the model's Input.
    with tempfile.TemporaryDirectory() as tmp:
        model.export(tmp)
        converter = tf.lite.TFLiteConverter.from_saved_model(tmp)
        # Builtins only: fail here rather than ship a model the app can't run.
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
        return converter.convert()


def main() -> None:
    spec = json.loads(MODEL_INPUT.read_text())
    names = spec["channels"]
    window = spec["windowSamples"]
    channels = len(names)

    fixture = json.loads(FIXTURE.read_text())
    if fixture["channels"] != names:
        raise SystemExit("capture fixture channels differ from model_input.json")
    rows = np.asarray(fixture["rows"], dtype=np.float64)
    if rows.shape[0] < window:
        raise SystemExit(f"capture fixture has {rows.shape[0]} rows, need {window}")

    mean = rows.mean(axis=0)
    std = rows.std(axis=0)
    std[std == 0] = 1.0

    tflite = convert(build_model(window, channels))

    raw = rows[:window]
    norm = ((raw - mean) / std).astype(np.float32)

    interp = tf.lite.Interpreter(model_content=tflite)
    interp.allocate_tensors()
    (inp,) = interp.get_input_details()
    assert list(inp["shape"]) == [1, window, channels], inp["shape"]
    interp.set_tensor(inp["index"], norm[np.newaxis])
    interp.invoke()
    outs = {}
    for d in interp.get_output_details():
        outs[tuple(int(v) for v in d["shape"])] = interp.get_tensor(d["index"])[0]
    probs = outs[(1, CLASSES)]
    emb = outs[(1, EMBEDDING)]

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "model_a.tflite").write_bytes(tflite)
    (OUT / "normalization.json").write_text(
        json.dumps(
            {
                "version": 1,
                "about": "DUMMY (S8A): mean/std over shared/capture_fixture rows, "
                "not a training set. Made by tools/model/make_dummy_model.py.",
                "channels": names,
                "mean": [float(v) for v in mean],
                "std": [float(v) for v in std],
            },
            indent=2,
        )
        + "\n"
    )
    (OUT / "check.json").write_text(
        json.dumps(
            {
                "version": 1,
                "about": "The capture fixture's first rows, the window normalised "
                "with normalization.json, and the dummy's outputs from Python "
                f"TFLite (tensorflow {tf.__version__}). The app's model check "
                "must reproduce them.",
                "rows": raw.tolist(),
                "window": [[float(v) for v in r] for r in norm],
                "gait_probs": [float(v) for v in probs],
                "gait_embedding": [float(v) for v in emb],
            }
        )
        + "\n"
    )
    print(f"model_a.tflite {len(tflite)} bytes; probs {np.round(probs, 4).tolist()}")


if __name__ == "__main__":
    main()
