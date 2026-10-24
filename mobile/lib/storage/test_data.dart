import 'dart:io';

import 'database.dart';

/// What [clearTestData] removed.
class ClearedTestData {
  const ClearedTestData({
    required this.alerts,
    required this.temperatureReadings,
    required this.dailySummaries,
    required this.footChecks,
    required this.photos,
  });

  final int alerts;
  final int temperatureReadings;
  final int dailySummaries;
  final int footChecks;
  final int photos;
}

/// Clears test data before the study (SR checklist; researcher-only
/// action on the research capture screen).
///
/// Removes, in one transaction: every alert **without** a capture stamp,
/// and every temperature reading, daily summary and foot check. Then
/// empties the foot-photo folder at [photoDir] (its rows are gone).
///
/// Never touches alerts with a capture stamp (study data: they go only
/// with their session, through "Delete from phone"), the capture session
/// folders, or the export folder: they are not in the database or the
/// photo folder.
Future<ClearedTestData> clearTestData(
  AppDatabase db, {
  required Future<Directory> Function() photoDir,
}) async {
  final (alerts, temps, summaries, checks) = await db.transaction(() async {
    final alerts = await (db.delete(
      db.alerts,
    )..where((t) => t.captureStamp.isNull())).go();
    final temps = await db.delete(db.temperatureReadings).go();
    final summaries = await db.delete(db.dailySummaries).go();
    final checks = await db.delete(db.footChecks).go();
    return (alerts, temps, summaries, checks);
  });
  var photos = 0;
  final dir = await photoDir();
  if (dir.existsSync()) {
    for (final e in dir.listSync()) {
      e.deleteSync(recursive: true);
      photos++;
    }
  }
  return ClearedTestData(
    alerts: alerts,
    temperatureReadings: temps,
    dailySummaries: summaries,
    footChecks: checks,
    photos: photos,
  );
}
