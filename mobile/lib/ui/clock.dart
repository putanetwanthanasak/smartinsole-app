import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current wall-clock time. Overridden in tests so goldens do not change
/// from day to day.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

const _weekdays = [
  'วันจันทร์',
  'วันอังคาร',
  'วันพุธ',
  'วันพฤหัสบดี',
  'วันศุกร์',
  'วันเสาร์',
  'วันอาทิตย์',
];

const _months = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

/// Thai long date with the Buddhist-era year, e.g. "วันเสาร์ที่ 18 ตุลาคม 2569".
String thaiLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}ที่ ${d.day} ${_months[d.month - 1]} ${d.year + 543}';
