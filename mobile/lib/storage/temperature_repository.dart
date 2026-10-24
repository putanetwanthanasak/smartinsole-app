import 'package:drift/drift.dart';

import '../ble/packets.dart';
import 'database.dart';
import 'local_date.dart';
import 'models.dart';

/// Row count and newest reading per foot (the BLE debug screen's storage
/// line, S6A phone check).
class TemperatureStats {
  const TemperatureStats(this.count, this.latestMs);

  static const empty = TemperatureStats({}, {});

  final Map<FootSide, int> count;
  final Map<FootSide, int> latestMs;
}

/// Every 30 s reading of both feet. Connection gaps are not stored: they
/// are the spaces between rows, worked out when the chart reads them.
abstract interface class TemperatureRepository {
  Future<void> add({
    required FootSide side,
    required int atMs,
    required double? forefootC,
    required double? heelC,
    required TempQuality quality,
    required bool timeFromArrival,
  });

  /// Both feet's readings on one local day, oldest first (the "today"
  /// chart, DESIGN-SPEC §8.2).
  Stream<List<TemperatureReading>> watchDay(String localDate);

  /// Readings in `[fromMs, toMs]`, oldest first.
  Future<List<TemperatureReading>> between(
    int fromMs,
    int toMs, {
    FootSide? side,
  });

  Future<TemperatureReading?> latest(FootSide side);

  Stream<TemperatureStats> watchStats();
}

class DriftTemperatureRepository implements TemperatureRepository {
  DriftTemperatureRepository(this._db, [this._dates = const LocalDates()]);

  final AppDatabase _db;
  final LocalDates _dates;

  @override
  Future<void> add({
    required FootSide side,
    required int atMs,
    required double? forefootC,
    required double? heelC,
    required TempQuality quality,
    required bool timeFromArrival,
  }) => _db
      .into(_db.temperatureReadings)
      .insert(
        TemperatureReadingsCompanion.insert(
          atMs: atMs,
          localDate: _dates.of(atMs),
          side: side,
          forefootC: Value(forefootC),
          heelC: Value(heelC),
          quality: quality,
          timeFromArrival: timeFromArrival,
        ),
      );

  @override
  Stream<List<TemperatureReading>> watchDay(String localDate) =>
      (_db.select(_db.temperatureReadings)
            ..where((t) => t.localDate.equals(localDate))
            ..orderBy([(t) => OrderingTerm.asc(t.atMs)]))
          .map(_toModel)
          .watch();

  @override
  Future<List<TemperatureReading>> between(
    int fromMs,
    int toMs, {
    FootSide? side,
  }) async {
    final q = _db.select(_db.temperatureReadings)
      ..where(
        (t) =>
            t.atMs.isBetweenValues(fromMs, toMs) &
            (side == null ? const Constant(true) : t.side.equalsValue(side)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.atMs)]);
    return (await q.get()).map(_toModel).toList();
  }

  @override
  Future<TemperatureReading?> latest(FootSide side) async {
    final row =
        await (_db.select(_db.temperatureReadings)
              ..where((t) => t.side.equalsValue(side))
              ..orderBy([(t) => OrderingTerm.desc(t.atMs)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  @override
  Stream<TemperatureStats> watchStats() {
    final t = _db.temperatureReadings;
    final count = t.id.count();
    final latest = t.atMs.max();
    final q = _db.selectOnly(t)
      ..addColumns([t.side, count, latest])
      ..groupBy([t.side]);
    return q.watch().map((rows) {
      final counts = <FootSide, int>{};
      final latestMs = <FootSide, int>{};
      for (final r in rows) {
        final side = FootSide.values.byName(r.read(t.side)!);
        counts[side] = r.read(count) ?? 0;
        if (r.read(latest) case final ms?) latestMs[side] = ms;
      }
      return TemperatureStats(counts, latestMs);
    });
  }
}

TemperatureReading _toModel(TemperatureRow r) => TemperatureReading(
  atMs: r.atMs,
  localDate: r.localDate,
  side: r.side,
  forefootC: r.forefootC,
  heelC: r.heelC,
  quality: r.quality,
  timeFromArrival: r.timeFromArrival,
);
