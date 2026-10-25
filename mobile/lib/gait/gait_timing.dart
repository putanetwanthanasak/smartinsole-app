// Technical constants of lib/gait/: the contract's output size, buffer
// sizes, write cadence and check tolerances. None is a clinical threshold
// (those are in thresholds.json, rule 12); this is the one lib/gait file
// the no-literal test skips.

/// `gait_embedding` is `[1, 32]` (DATA-CONTRACT §7.2).
const gaitEmbeddingSize = 32;

/// Inference times kept for the debug screen's median and max.
const inferenceStatsKept = 60;

/// `check.json`: the app's normalised window may differ from Python's by
/// float32 rounding only; the model's outputs by the interpreter's own
/// rounding (XNNPACK and reference kernels differ slightly).
const checkWindowTolerance = 1e-6;
const checkOutputTolerance = 1e-4;

/// Today's step count is written to `daily_summary.steps` at most this
/// often (and when the day changes or the app stops), so a crash loses at
/// most this much counting.
const stepsWriteEvery = Duration(seconds: 30);

/// Points kept for drawing the newest step's centre-of-pressure path.
const copMaxPoints = 40;
