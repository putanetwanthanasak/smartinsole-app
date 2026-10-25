import 'dart:math' as math;

import '../ble/ble_protocol.dart';
import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../device/mock_data_source.dart';
import 'local_date.dart';
import 'temperature_repository.dart';

/// The shape of a seeded day, as fractions of its span (0 = the first
/// reading, 1 = the last). Each preset's day ends the way the live mock
/// goes on (user decision 2026-10-25), so the chart matches the boards
/// FeetDTemp, FeetDTempRest and FeetDTempMissing.
class SampleDayShape {
  const SampleDayShape({
    required this.aboveSite,
    required this.aboveFrom,
    required this.aboveTo,
    required this.gapFrom,
    this.gapTo,
  });

  /// One period above `deltaC`, the right foot warmer.
  final TempSite aboveSite;
  final double aboveFrom;
  final double aboveTo;

  /// The right foot gives no readings from [gapFrom] to [gapTo]; with no
  /// [gapTo] it never comes back (the open gap).
  final double gapFrom;
  final double? gapTo;

  static SampleDayShape of(MockPreset preset) => switch (preset) {
    // The forefoot stays above the threshold up to the end, joining the
    // live mock's right forefoot (2.6 °C warmer).
    MockPreset.rest => const SampleDayShape(
      aboveSite: TempSite.forefoot,
      aboveFrom: 0.75,
      aboveTo: 1,
      gapFrom: 0.30,
      gapTo: 0.38,
    ),
    // The right foot never comes back, as the live mock's.
    MockPreset.oneFootMissing => const SampleDayShape(
      aboveSite: TempSite.heel,
      aboveFrom: 0.30,
      aboveTo: 0.45,
      gapFrom: 0.70,
    ),
    _ => const SampleDayShape(
      aboveSite: TempSite.heel,
      aboveFrom: 0.35,
      aboveTo: 0.50,
      gapFrom: 0.62,
      gapTo: 0.70,
    ),
  };
}

/// The seeded day starts at this local hour (the boards' charts start in
/// the morning).
const sampleDayStartHour = 8;

/// DEBUG ONLY: today's temperature readings for both feet, one every 30 s
/// from 08:00 to just before the first live reading (or [now]), with one
/// period above the ΔT threshold and one right-foot connection gap, shaped
/// by [preset] ([SampleDayShape]). For the design screenshots (S6B part 2).
///
/// Reached only from Settings in a mock-preset run, whose database is in
/// memory: these rows never reach the phone's file. The above-threshold
/// difference is `deltaC` + 0.4 °C (2.6 °C on the boards). Returns the
/// number of rows written.
Future<int> seedSampleDay({
  required TemperatureRepository temperatures,
  required LocalDates dates,
  required Thresholds thresholds,
  required MockPreset preset,
  required DateTime now,
}) async {
  final shape = SampleDayShape.of(preset);
  final period = TempLayout.notifyPeriod.inMilliseconds;
  final today = dates.of(now.millisecondsSinceEpoch);
  final live = await temperatures.watchDay(today).first;
  final endMs =
      (live.isEmpty ? now.millisecondsSinceEpoch : live.first.atMs) - period;
  final morning = DateTime(now.year, now.month, now.day, sampleDayStartHour);
  final midnight = DateTime(now.year, now.month, now.day);
  // Before 08:30, the day so far.
  var startMs = morning.millisecondsSinceEpoch;
  if (endMs - startMs < period * 60) startMs = midnight.millisecondsSinceEpoch;
  if (endMs <= startMs) return 0;
  final span = (endMs - startMs).toDouble();

  final high = thresholds.deltaC + 0.4;
  // How long the difference takes to rise into and fall out of the
  // period: 15 minutes, as a warming foot would.
  final ramp = const Duration(minutes: 15).inMilliseconds / span;

  double above(double f) {
    if (f < shape.aboveFrom - ramp || f > shape.aboveTo + ramp) return 0;
    if (f < shape.aboveFrom) return (f - shape.aboveFrom + ramp) / ramp;
    if (f > shape.aboveTo) return (shape.aboveTo + ramp - f) / ramp;
    return 1;
  }

  var n = 0;
  for (var ms = startMs; ms <= endMs; ms += period) {
    final f = (ms - startMs) / span;
    // A slow drift over the day, and small left–right differences.
    final drift = 0.4 * math.sin(f * math.pi * 2);
    final small = 0.25 + 0.15 * math.sin(f * math.pi * 7);
    final a = above(f);
    // Inside the period it wobbles by ±0.2 °C, staying above deltaC.
    final top = high + 0.2 * math.sin(f * math.pi * 40);
    double diff(TempSite s) =>
        s == shape.aboveSite ? small + (top - small) * a : small * 0.6;
    const leftForefoot = 30.6;
    const leftHeel = 31.2;
    await temperatures.add(
      side: FootSide.left,
      atMs: ms,
      forefootC: _r(leftForefoot + drift),
      heelC: _r(leftHeel + drift),
      quality: TempQuality.normal,
      timeFromArrival: false,
    );
    n++;
    final gap = f >= shape.gapFrom && (shape.gapTo == null || f < shape.gapTo!);
    // The right board reports a few seconds after the left.
    final rightMs = ms + period ~/ 4;
    if (!gap && rightMs <= endMs) {
      await temperatures.add(
        side: FootSide.right,
        atMs: rightMs,
        forefootC: _r(leftForefoot + drift + diff(TempSite.forefoot)),
        heelC: _r(leftHeel + drift + diff(TempSite.heel)),
        quality: TempQuality.normal,
        timeFromArrival: false,
      );
      n++;
    }
  }
  return n;
}

/// The sensor's 0.01 °C resolution.
double _r(double c) => (c * 100).round() / 100;
