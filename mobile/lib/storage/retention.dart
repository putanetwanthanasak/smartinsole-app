import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'database.dart';
import 'foot_check_repository.dart';
import 'local_date.dart';
import 'models.dart';

class RetentionResult {
  const RetentionResult({
    required this.alerts,
    required this.temperatures,
    required this.footChecks,
    required this.summaries,
    required this.photos,
    required this.photosKept,
  });

  final int alerts;
  final int temperatures;
  final int footChecks;
  final int summaries;

  /// Photo files deleted.
  final int photos;

  /// Checks kept because a photo file could not be deleted; the next run
  /// tries again.
  final int photosKept;
}

/// Deletes rows older than [retentionPeriod]. A row exactly that old is
/// kept; one millisecond older goes.
///
/// Never deleted here:
/// - alerts with a capture stamp: study data for the warm-compress test,
///   removed only with their capture's "Delete from phone";
/// - research capture files (S4C): not in this database, and only paths
///   inside the foot-photo folder are ever deleted.
class Retention {
  Retention(
    this._db, {
    required this.photoDir,
    this.dates = const LocalDates(),
  });

  final AppDatabase _db;
  final Future<Directory> Function() photoDir;
  final LocalDates dates;

  Future<RetentionResult> run(DateTime now) async {
    final cutoffMs =
        now.millisecondsSinceEpoch - retentionPeriod.inMilliseconds;
    final (checks, photos, kept) = await _footChecks(cutoffMs);
    return _db.transaction(() async {
      final alerts =
          await (_db.delete(_db.alerts)..where(
                (t) =>
                    t.atMs.isSmallerThanValue(cutoffMs) &
                    t.captureStamp.isNull(),
              ))
              .go();
      final temperatures = await (_db.delete(
        _db.temperatureReadings,
      )..where((t) => t.atMs.isSmallerThanValue(cutoffMs))).go();
      // A summary row is a whole day: it goes once its day is older than
      // the cutoff's day.
      final cutoffDate = dates.of(cutoffMs);
      final summaries = await (_db.delete(
        _db.dailySummaries,
      )..where((t) => t.localDate.isSmallerThanValue(cutoffDate))).go();
      return RetentionResult(
        alerts: alerts,
        temperatures: temperatures,
        footChecks: checks,
        summaries: summaries,
        photos: photos,
        photosKept: kept,
      );
    });
  }

  /// Photo files first, then the row, so a file that will not delete keeps
  /// its row and is retried next time.
  Future<(int, int, int)> _footChecks(int cutoffMs) async {
    final expired = await (_db.select(
      _db.footChecks,
    )..where((t) => t.atMs.isSmallerThanValue(cutoffMs))).get();
    if (expired.isEmpty) return (0, 0, 0);
    final dir = (await photoDir()).absolute.path;
    var checks = 0, photos = 0, kept = 0;
    for (final row in expired) {
      var ok = true;
      for (final rel in footCheckOf(row).photos.values) {
        final path = p.normalize(p.join(dir, rel));
        if (!p.isWithin(dir, path)) {
          // Not ours to delete (never written by the app): leave the file.
          debugPrint('retention: photo path outside $dir: $rel');
          continue;
        }
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            photos++;
          }
        } on FileSystemException catch (e) {
          debugPrint('retention: could not delete $path: $e');
          ok = false;
        }
      }
      if (!ok) {
        kept++;
        continue;
      }
      checks += await (_db.delete(
        _db.footChecks,
      )..where((t) => t.id.equals(row.id))).go();
    }
    return (checks, photos, kept);
  }
}

/// Runs [Retention] at start, on resume ([maybeRun]) and from an hourly
/// check, each time only if a day has passed since the last run. The timer
/// only asks; "a day has passed" is worked out from timestamps when asked
/// (rule 2), so a starved timer delays a run but never skips one.
class RetentionSchedule {
  RetentionSchedule(
    this._retention, {
    required this.now,
    this.every = const Duration(days: 1),
    this.checkEvery = const Duration(hours: 1),
  });

  final Retention _retention;
  final DateTime Function() now;
  final Duration every;
  final Duration checkEvery;

  Timer? _timer;
  DateTime? _lastRun;
  Future<void>? _running;

  DateTime? get lastRun => _lastRun;

  void start() {
    _timer ??= Timer.periodic(checkEvery, (_) => maybeRun());
    maybeRun();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> maybeRun() {
    if (_running case final r?) return r;
    final at = now();
    final last = _lastRun;
    if (last != null && at.difference(last) < every) return Future.value();
    _lastRun = at;
    return _running = _retention
        .run(at)
        .then<void>(
          (_) {},
          onError: (Object e) {
            debugPrint('retention failed: $e');
            _lastRun = last; // try again at the next check
          },
        )
        .whenComplete(() => _running = null);
  }
}
