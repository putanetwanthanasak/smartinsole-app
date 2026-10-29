import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Sets `tz.local` to the phone's zone (user addition 5). The timezone
/// package's default `tz.local` is UTC, which would move a 19:00 reminder
/// to 02:00 in Bangkok. [zoneName] reads the IANA name from the phone
/// (`flutter_timezone`). An unknown name falls back to a zone fixed at
/// the phone's current [offset] (Thailand has no daylight saving), never
/// UTC. Returns the zone used.
Future<tz.Location> initLocalTimeZone({
  required Future<String> Function() zoneName,
  required Duration offset,
}) async {
  tzdata.initializeTimeZones();
  tz.Location location;
  String name = '?';
  try {
    name = await zoneName();
    location = tz.getLocation(name);
  } catch (e) {
    location = _fixedOffset(offset);
    debugPrint('time zone "$name" unknown ($e); using ${location.name}');
  }
  tz.setLocalLocation(location);
  return location;
}

/// A zone with one fixed [offset] and no transitions; works for any
/// offset, including half hours (never falls back to UTC).
tz.Location _fixedOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final m = offset.inMinutes.abs();
  final name =
      'Fixed$sign${(m ~/ 60).toString().padLeft(2, '0')}'
      '${(m % 60).toString().padLeft(2, '0')}';
  return tz.Location(name, const [], const [], [
    tz.TimeZone(offset, isDst: false, abbreviation: name),
  ]);
}
