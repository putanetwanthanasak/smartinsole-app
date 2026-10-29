import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../rules/asymmetry.dart';
import '../rules/step_detector.dart';
import 'gait_class.dart';
import 'gait_classifier.dart';

/// Contract §7.5's `RuleBasedEngine` for gait: the result whenever Model A
/// is missing or not confident. PROVISIONAL: every boundary is a `gait.*`
/// key in `thresholds.json`, to be checked against the instructed gaits in
/// SR. Display only, never a level (rule 11).
///
/// From each foot's newest `gait.ruleSteps` walking steps:
/// - `toe_walking`: the heel's share of the steps' summed pressure–time
///   integral is below `gait.toeHeelPtiPct`;
/// - `heel_walking`: the forefoot's share (hallux, meta1, meta3, meta5) is
///   below `gait.heelForefootPtiPct`;
/// - `antalgic`: the PAI formula ([paiPercent]) on the two feet's mean
///   stance times is above `gait.stanceAsymmetryPct` (the painful side's
///   stance is shorter);
/// - otherwise `normal`.
///
/// `rotated_foot` comes only from the model: six FSR cannot tell how the
/// foot is turned.
class RuleBasedClassifier implements GaitClassifier {
  const RuleBasedClassifier(this.thresholds, {this.layout = footLayout});

  final Thresholds thresholds;
  final FootLayout layout;

  @override
  Future<GaitResult?> classify(GaitInput input) async => classifyNow(input);

  /// [classify] without the future.
  GaitResult? classifyNow(GaitInput input, {RulesBecause? because}) {
    final n = thresholds.gaitRuleSteps;
    if (input.leftSteps.length < n || input.rightSteps.length < n) {
      return null;
    }
    final left = input.leftSteps.sublist(input.leftSteps.length - n);
    final right = input.rightSteps.sublist(input.rightSteps.length - n);

    var whole = 0.0;
    var heel = 0.0;
    var forefoot = 0.0;
    for (final step in [...left, ...right]) {
      for (
        var c = 0;
        c < step.ptiKpaMs.length && c < layout.zones.length;
        c++
      ) {
        final v = step.ptiKpaMs[c];
        whole += v;
        switch (layout.zones[c].region) {
          case FootRegion.heel:
            heel += v;
          case FootRegion.forefoot:
            forefoot += v;
          case FootRegion.lateral:
          case FootRegion.arch:
            break;
        }
      }
    }
    if (whole <= 0) return null;

    GaitClass gaitClass;
    if (heel * 100 / whole < thresholds.toeHeelPtiPct) {
      gaitClass = GaitClass.toeWalking;
    } else if (forefoot * 100 / whole < thresholds.heelForefootPtiPct) {
      gaitClass = GaitClass.heelWalking;
    } else if (paiPercent(_meanStance(left), _meanStance(right)) >
        thresholds.stanceAsymmetryPct) {
      gaitClass = GaitClass.antalgic;
    } else {
      gaitClass = GaitClass.normal;
    }
    return GaitResult(
      gaitClass: gaitClass,
      source: GaitSource.rules,
      atMs: input.atMs,
      because: because,
    );
  }

  static double _meanStance(List<Step> steps) =>
      steps.fold<double>(0, (a, s) => a + s.durationMs) / steps.length;
}
