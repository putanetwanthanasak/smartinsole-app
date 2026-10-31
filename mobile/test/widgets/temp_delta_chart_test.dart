import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/screens/my_feet/temp_chart_model.dart';
import 'package:smartinsole/ui/widgets/temp_delta_chart.dart';

void main() {
  testWidgets('an end label wider than the plot is dropped, not clamped '
      'into an error', (t) async {
    const start = 0;
    const end = 60 * 60 * 1000;
    // Site 1, "โคนนิ้วหัวแม่เท้า": one of the longest names.
    const data = TempChartData(
      startMs: start,
      endMs: end,
      runs: [
        [ChartPoint(start, 0.4, 1), ChartPoint(end, 1.2, 1)],
      ],
      gaps: [],
    );
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 140,
              child: TempDeltaChart(
                data: data,
                deltaC: 2.2,
                semanticLabel: 'chart',
                drawInKey: 0,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
