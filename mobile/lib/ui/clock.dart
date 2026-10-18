import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The current wall-clock time. Overridden in tests so goldens do not change
/// from day to day.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Home header date, e.g. "วันศุกร์ 16 ตุลาคม". Thai date symbols are loaded
/// by `GlobalMaterialLocalizations`, so call this below `MaterialApp`.
String thaiLongDate(DateTime d) => DateFormat('EEEE d MMMM', 'th').format(d);
