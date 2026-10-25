/// Model A's five gait classes, in the index order of its `gait_probs`
/// output (DATA-CONTRACT §7.2). Never reorder: index i of the model's
/// softmax is `GaitClass.values[i]`.
enum GaitClass {
  normal('normal'),
  antalgic('antalgic'),
  toeWalking('toe_walking'),
  heelWalking('heel_walking'),
  rotatedFoot('rotated_foot');

  const GaitClass(this.id);

  /// The contract's class id, as stored with an alert (`gait_class`) and
  /// keyed in `gaitClassTh`.
  final String id;
}

/// Who produced a [GaitResult].
enum GaitSource { rules, model }

/// Why a result came from the rules rather than Model A.
enum RulesBecause {
  /// No usable model in `assets/models/`, or no model result for this
  /// stride (no gap-free window yet, or the run failed) (DESIGN-SPEC §8.3:
  /// "โมเดล AI ยังไม่พร้อม").
  noModel,

  /// The model ran, but its confidence was below `model.minConfidence`
  /// (contract §7.5).
  lowConfidence,
}

/// One gait estimate. Display only, and the gait note's input: it never
/// changes a level (rule 11, contract §8.4).
class GaitResult {
  const GaitResult({
    required this.gaitClass,
    required this.source,
    required this.atMs,
    this.confidence,
    this.probs,
    this.because,
  });

  final GaitClass gaitClass;
  final GaitSource source;

  /// Unix ms of the newest sample the estimate used (sample time, not the
  /// phone's clock when it was computed).
  final double atMs;

  /// Model only: the top class's probability, 0–1.
  final double? confidence;

  /// Model only: every class's probability, in [GaitClass] order.
  final List<double>? probs;

  /// Rules only: why the model's result is not shown.
  final RulesBecause? because;

  @override
  bool operator ==(Object other) =>
      other is GaitResult &&
      other.gaitClass == gaitClass &&
      other.source == source &&
      other.atMs == atMs &&
      other.confidence == confidence &&
      other.because == because &&
      _listEq(other.probs, probs);

  @override
  int get hashCode => Object.hash(
    gaitClass,
    source,
    atMs,
    confidence,
    because,
    probs == null ? null : Object.hashAll(probs!),
  );
}

bool _listEq(List<double>? a, List<double>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
