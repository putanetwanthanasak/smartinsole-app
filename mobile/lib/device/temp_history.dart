import 'dart:collection';

import '../ble/packets.dart';

/// One temperature trend point: the latest reading inside a bucket, with
/// each site's value only when its quality is normal.
class TempPoint {
  const TempPoint({
    required this.bucketStartMs,
    required this.unixMs,
    required this.celsius,
  });

  final int bucketStartMs;
  final double unixMs;

  /// Per site (index = zone); null for a site that could not be read or
  /// whose quality is not normal.
  final List<double?> celsius;
}

/// One foot's temperature trend for the chart: one point per 10-minute
/// bucket over the last 24 h, latest reading wins (as the web app). Only
/// `normal` sites go in; a poor-contact or faulty site is not a temperature
/// (web report 011). Memory only; S6A stores it.
class TempHistory {
  TempHistory({this.bucketMs = 10 * 60 * 1000, this.spanMs = 24 * 3600000});

  final int bucketMs;
  final int spanMs;
  final _points = SplayTreeMap<int, TempPoint>();

  void add(double unixMs, TempPacket p) {
    final celsius = [for (var i = 0; i < p.siteCount; i++) p.usableC(i)];
    if (celsius.every((c) => c == null)) return;
    final bucket = (unixMs ~/ bucketMs) * bucketMs;
    _points[bucket] = TempPoint(
      bucketStartMs: bucket,
      unixMs: unixMs,
      celsius: celsius,
    );
    _prune(unixMs);
  }

  /// Points within the span ending at [now], oldest first. Worked out at
  /// read time, so an idle app never shows day-old points as recent.
  List<TempPoint> points(DateTime now) {
    final from = now.millisecondsSinceEpoch - spanMs;
    return [
      for (final p in _points.values)
        if (p.bucketStartMs + bucketMs > from) p,
    ];
  }

  void _prune(double nowMs) {
    final from = nowMs - spanMs - bucketMs;
    _points.removeWhere((k, _) => k < from);
  }
}
