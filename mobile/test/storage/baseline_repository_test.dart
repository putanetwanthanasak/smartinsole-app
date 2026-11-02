import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/baseline_repository.dart';
import 'package:smartinsole/storage/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  FootBaseline b(FootSide side, String id, double v, {int at = 1}) =>
      FootBaseline(
        side: side,
        insoleId: id,
        recordedAtMs: at,
        sampleCount: 1500,
        values: [for (var i = 0; i < 14; i++) v + i * 0.25],
      );

  test(
    'one baseline per foot and insole; a new recording replaces it',
    () async {
      final repo = DriftBaselineRepository(db);
      await repo.save(b(FootSide.left, 'INSOLE-L-001', 1));
      await repo.save(b(FootSide.right, 'INSOLE-R-001', 2));
      await repo.save(b(FootSide.left, 'INSOLE-L-002', 3));
      await repo.save(b(FootSide.left, 'INSOLE-L-001', 9, at: 5));
      final all = await repo.watchAll().first;
      expect(all, hasLength(3));
      final l1 = all.singleWhere((x) => x.insoleId == 'INSOLE-L-001');
      expect(l1.recordedAtMs, 5);
      expect(l1.values.first, 9);
      expect(l1.values.last, 9 + 13 * 0.25);
      expect(l1.sampleCount, 1500);
    },
  );
}
