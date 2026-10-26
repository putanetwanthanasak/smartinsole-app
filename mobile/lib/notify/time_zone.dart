import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Sets `tz.local` to the phone's zone (user addition 5). The timezone
/// package's default `tz.local` is UTC, which would move a 19:00 reminder
/// to 02:00 in Bangkok. [zoneName] reads the IANA name from the phone
/// (`flutter_timezone`). An unknown name falls back to the fixed-offset
/// `Etc/GMT` zone of [offset] (Thailand has no daylight saving), and to
/// UTC only when even that is missing. Returns the zone used.
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

tz.Location _fixedOffset(Duration offset) {
  // Etc/GMT signs are inverted: UTC+7 is "Etc/GMT-7".
  if (offset.inMinutes % 60 == 0) {
    final h = offset.inHours;
    final name = h == 0 ? 'Etc/UTC' : 'Etc/GMT${h > 0 ? '-' : '+'}${h.abs()}';
    try {
      return tz.getLocation(name);
    } catch (_) {}
  }
  return tz.UTC;
}
