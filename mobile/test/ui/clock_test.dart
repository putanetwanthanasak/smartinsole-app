import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartinsole/ui/clock.dart';

void main() {
  setUpAll(() => initializeDateFormatting('th'));

  test('group-title day: weekday without "วัน", day, short month', () {
    expect(thaiWeekdayDayMonth(DateTime(2026, 10, 20)), 'อังคาร 20 ต.ค.');
    expect(thaiWeekdayDayMonth(DateTime(2026, 10, 18)), 'อาทิตย์ 18 ต.ค.');
  });

  test('detail time stamp: Buddhist year, seconds', () {
    expect(
      thaiDateTimeBE(DateTime(2026, 10, 21, 14, 32, 10)),
      '21 ต.ค. 2569 14:32:10',
    );
    expect(
      thaiDateTimeBE(DateTime(2027, 1, 2, 7, 5, 9)),
      '2 ม.ค. 2570 07:05:09',
    );
  });

  test('today / yesterday across midnight and month ends', () {
    final now = DateTime(2026, 11, 1, 0, 5);
    expect(relativeDayTh(DateTime(2026, 11, 1, 0, 1), now), 'วันนี้');
    expect(relativeDayTh(DateTime(2026, 10, 31, 23, 59), now), 'เมื่อวาน');
    expect(relativeDayTh(DateTime(2026, 10, 30, 23, 59), now), isNull);
    expect(hhmm(DateTime(2026, 10, 31, 9, 4)), '09:04');
  });
}
