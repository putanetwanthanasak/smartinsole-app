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
            result = Motion.duration(context, Motion.medium);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('durations pass through when motion is allowed', (tester) async {
    expect(await resolve(tester, reduced: false), Motion.medium);
  });

  testWidgets('durations are zero under reduce motion', (tester) async {
    expect(await resolve(tester, reduced: true), Duration.zero);
  });

  test('spec durations', () {
    expect(Motion.short.inMilliseconds, 200);
    expect(Motion.medium.inMilliseconds, 300);
    expect(Motion.long.inMilliseconds, 400);
    expect(Motion.pulse.inMilliseconds, 1600);
  });
}
