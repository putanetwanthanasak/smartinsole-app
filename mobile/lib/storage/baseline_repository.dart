import 'dart:convert';

import '../ble/packets.dart';
import 'database.dart';

/// One insole's quiet-standing baseline (S9, Model A preprocessing "ทางเอ"):
/// the per-channel median of the foot's model channels (12 since v1.7,
/// 14 in a v1.6 build's rows).
class FootBaseline {
  const FootBaseline({
    required this.side,
    required this.insoleId,
    required this.recordedAtMs,
    required this.sampleCount,
    required this.values,
  });

  final FootSide side;

  /// The insole's calibration `device_id`.
  final String insoleId;
  final int recordedAtMs;

  /// Samples the median was taken over.
  final int sampleCount;

  /// The foot's model channels in contract §7.1 order (12 since v1.7).
  final List<double> values;
}

/// The baselines table: the latest per foot and insole.
abstract interface class BaselineRepository {
  /// Stores [b], replacing that foot and insole's earlier baseline.
  Future<void> save(FootBaseline b);

  /// Every stored baseline, now and after each change.
  Stream<List<FootBaseline>> watchAll();
}

class DriftBaselineRepository implements BaselineRepository {
  DriftBaselineRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> save(FootBaseline b) => _db
      .into(_db.baselines)
      .insertOnConflictUpdate(
        BaselinesCompanion.insert(
          side: b.side,
          insoleId: b.insoleId,
          recordedAtMs: b.recordedAtMs,
          sampleCount: b.sampleCount,
          values: jsonEncode(b.values),
        ),
      );

  @override
  Stream<List<FootBaseline>> watchAll() => _db
      .select(_db.baselines)
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            FootBaseline(
              side: r.side,
              insoleId: r.insoleId,
              recordedAtMs: r.recordedAtMs,
              sampleCount: r.sampleCount,
              values: [
                for (final v in jsonDecode(r.values) as List)
                  (v as num).toDouble(),
              ],
            ),
        ],
      );
}
