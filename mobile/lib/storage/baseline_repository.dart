import 'dart:convert';

import '../ble/packets.dart';
import 'database.dart';

/// One insole's quiet-standing baseline (S9, Model A preprocessing "ทางเอ"):
/// the per-channel median of the foot's 14 model channels.
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

  /// 14 values, the foot's model channels in contract §7.1 order.
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
