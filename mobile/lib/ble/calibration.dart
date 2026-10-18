import 'dart:convert';

import 'parse_result.dart';

/// Per-insole FSR calibration, read once at connect from the Calibration
/// characteristic (Data Contract §5.1). The number of channels is the
/// insole's FSR count N, which sets the sensor packet's sample size.
class Calibration {
  const Calibration({
    required this.deviceId,
    required this.rPulldownOhm,
    required this.sensorAreaM2,
    required this.channels,
  });

  final String deviceId;
  final double rPulldownOhm;
  final double sensorAreaM2;

  /// Sorted by [CalibrationChannel.index], so `channels[i]` is channel i.
  final List<CalibrationChannel> channels;

  int get fsrCount => channels.length;
}

class CalibrationChannel {
  const CalibrationChannel({
    required this.index,
    required this.a,
    required this.b,
    required this.offsetAdc,
  });

  final int index;

  /// Curve fit `F_newton = a × R_fsr^b`.
  final double a;
  final double b;

  /// Raw ADC under no load (the stored TARE result).
  final double offsetAdc;
}

/// Parses the calibration JSON. A bad blob is a hard connect failure, never
/// a fallback to a plausible-looking default curve. Field checks match the
/// TS parser; unlike TS, N is taken from the blob instead of being fixed at
/// 6, the channel indexes must be exactly 0..N−1, and resistance and area
/// must be positive (zero would make every kPa infinite).
ParseResult<Calibration> parseCalibration(String text) {
  final Object? raw;
  try {
    raw = jsonDecode(text);
  } on FormatException catch (e) {
    return Rejected(RejectReason.calibrationNotJson, e.message);
  }
  if (raw is! Map<String, Object?>) {
    return const Rejected(
      RejectReason.calibrationNotObject,
      'calibration blob is not a JSON object',
    );
  }

  final deviceId = raw['device_id'];
  final rPulldown = raw['r_pulldown_ohm'];
  final area = raw['sensor_area_m2'];
  final rawChannels = raw['channels'];
  if (deviceId is! String) return _missing('device_id');
  if (rPulldown is! num) return _missing('r_pulldown_ohm');
  if (area is! num) return _missing('sensor_area_m2');
  if (rawChannels is! List) return _missing('channels');
  if (rPulldown <= 0 || area <= 0) {
    return Rejected(
      RejectReason.calibrationInvalidValue,
      'r_pulldown_ohm $rPulldown and sensor_area_m2 $area must be > 0',
    );
  }

  final channels = <CalibrationChannel>[];
  for (var i = 0; i < rawChannels.length; i++) {
    final c = rawChannels[i];
    if (c is! Map<String, Object?>) return _missing('channels[$i]');
    final index = c['index'];
    final a = c['a'];
    final b = c['b'];
    final offset = c['offset_adc'];
    if (index is! num || a is! num || b is! num || offset is! num) {
      return _missing('channels[$i].index/a/b/offset_adc');
    }
    if (index != index.toInt()) {
      return Rejected(
        RejectReason.calibrationBadChannelIndex,
        'channels[$i].index $index is not an integer',
      );
    }
    channels.add(
      CalibrationChannel(
        index: index.toInt(),
        a: a.toDouble(),
        b: b.toDouble(),
        offsetAdc: offset.toDouble(),
      ),
    );
  }

  if (channels.isEmpty) {
    return const Rejected(
      RejectReason.calibrationNoChannels,
      'calibration blob has no channels',
    );
  }
  channels.sort((x, y) => x.index.compareTo(y.index));
  for (var i = 0; i < channels.length; i++) {
    if (channels[i].index != i) {
      return Rejected(
        RejectReason.calibrationBadChannelIndex,
        'channel indexes ${channels.map((c) => c.index).toList()} are not '
        '0..${channels.length - 1}',
      );
    }
  }

  return Parsed(
    Calibration(
      deviceId: deviceId,
      rPulldownOhm: rPulldown.toDouble(),
      sensorAreaM2: area.toDouble(),
      channels: List.unmodifiable(channels),
    ),
  );
}

Rejected<Calibration> _missing(String field) => Rejected(
  RejectReason.calibrationMissingField,
  'calibration blob: $field missing or wrong type',
);
