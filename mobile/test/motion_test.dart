import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/motion.dart';

void main() {
  Future<Duration> resolve(WidgetTester tester, {required bool reduced}) async {
    late Duration result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Builder(
          builder: (context) {
            result = Motion.duration(context, Motion.enterDuration);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('durations pass through when motion is allowed', (tester) async {
    expect(await resolve(tester, reduced: false), Motion.enterDuration);
  });

  testWidgets('durations are zero under reduce motion', (tester) async {
    expect(await resolve(tester, reduced: true), Duration.zero);
  });

  test('spec durations (DESIGN-SPEC §12.1)', () {
    expect(Motion.exitDuration.inMilliseconds, 200);
    expect(Motion.enterDuration.inMilliseconds, 300);
    expect(Motion.valueDuration.inMilliseconds, 400);
    expect(Motion.stagger.inMilliseconds, 40);
    expect(Motion.popDuration.inMilliseconds, 300);
    expect(Motion.pulse.inMilliseconds, 1600);
    expect(Motion.pulseGrow.inMilliseconds, 1400);
    expect(Motion.wiggleStep.inMilliseconds, 110);
    expect(Motion.wiggleDegrees, [-14, 12, -8, 6, 0]);
    expect(Motion.chevronDuration.inMilliseconds, 200);
    expect(Motion.pressDuration.inMilliseconds, 150);
  });

  test('curves are the boards\' exact cubic-beziers', () {
    void expectCubic(Curve c, double a, double b, double cc, double d) {
      expect(c, isA<Cubic>());
      final cubic = c as Cubic;
      expect([cubic.a, cubic.b, cubic.c, cubic.d], [a, b, cc, d]);
    }

    expectCubic(Motion.exit, 0.32, 0, 0.67, 0);
    expectCubic(Motion.enter, 0.33, 1, 0.68, 1);
    expectCubic(Motion.value, 0.33, 1, 0.68, 1);
    expectCubic(Motion.pop, 0.34, 1.3, 0.64, 1);
    // Flutter's named cubics are different curves (§12.1).
    expect(Motion.enter, isNot(Curves.easeOutCubic));
    expect(Motion.exit, isNot(Curves.easeInCubic));
  });
}
