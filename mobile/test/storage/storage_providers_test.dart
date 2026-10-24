import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../helpers/pump_app.dart';
import 'storage_rig.dart';

void main() {
  test('a mock-preset run never opens the phone\'s database file', () async {
    // No path_provider in tests: opening the file would throw.
    final container = ProviderContainer(
      overrides: [mockPresetProvider.overrideWithValue(MockPreset.safe)],
    );
    addTearDown(container.dispose);
    final repo = container.read(alertRepositoryProvider);
    expect(await repo.watchUnreadCount(0).first, 0);
  });

  test('the badge count comes from the alert store (0 when empty)', () async {
    final now = DateTime.utc(2026, 10, 24, 7, 30);
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        databaseProvider.overrideWith((ref) {
          final db = AppDatabase.memory();
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
    addTearDown(container.dispose);
    final counts = <int>[];
    container.listen(
      unreadAlertCountProvider,
      (_, n) => counts.add(n),
      fireImmediately: true,
    );
    await pumpEventQueue();
    final repo = container.read(alertRepositoryProvider);
    final id = await repo.add(
      alertOf(AlertKind.tempDelta, now.millisecondsSinceEpoch),
    );
    await repo.add(
      alertOf(AlertKind.pressureWatch, now.millisecondsSinceEpoch),
    );
    await pumpEventQueue();
    await repo.markRead(id, now.millisecondsSinceEpoch + 1);
    await pumpEventQueue();
    expect(counts, [0, 1, 0]);
  });

  testWidgets('a stored alert shows on the Alerts tab badge', (tester) async {
    await pumpApp(tester);
    expect(byKey('alerts-badge'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await tester.runAsync(
      () => container
          .read(alertRepositoryProvider)
          .add(
            alertOf(AlertKind.pressurePeak, fixedNow.millisecondsSinceEpoch),
          ),
    );
    await tester.pumpAndSettle();
    expect(byKey('alerts-badge'), findsOneWidget);
    expect(
      find.descendant(of: byKey('alerts-badge'), matching: find.text('1')),
      findsOneWidget,
    );
  });
}
