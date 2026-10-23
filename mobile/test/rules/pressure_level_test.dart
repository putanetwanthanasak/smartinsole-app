import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/pressure_level.dart';

import '../helpers/pump_app.dart';

void main() {
  final t = testThresholds;

  test('levels come from thresholds.json, strictly above each boundary', () {
    expect(pressureLevel(0, t), PressureLevel.low);
    expect(pressureLevel(t.watchKpa, t), PressureLevel.low);
    expect(pressureLevel(t.watchKpa + 0.1, t), PressureLevel.medium);
    expect(pressureLevel(t.alertKpa, t), PressureLevel.medium);
    expect(pressureLevel(t.alertKpa + 0.1, t), PressureLevel.high);
  });

  test('legend words', () {
    expect(PressureLevel.values.map((l) => l.th), ['น้อย', 'ปานกลาง', 'มาก']);
  });
}
