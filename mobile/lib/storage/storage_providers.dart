import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../device/device_providers.dart';
import '../ui/clock.dart';
import 'alert_repository.dart';
import 'daily_summary_repository.dart';
import 'database.dart';
import 'foot_check_repository.dart';
import 'foot_photos.dart';
import 'local_date.dart';
import 'models.dart';
import 'retention.dart';
import 'temperature_recorder.dart';
import 'temperature_repository.dart';
import 'test_data.dart';

// The only way into storage for the rest of the app: screens and services
// read the repository providers, never [AppDatabase].

/// The app's database: the file in app-private storage for real BLE, in
/// memory for a mock-preset run. Tests and the emulator driver override it
/// with [AppDatabase.memory].
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = ref.watch(mockPresetProvider) == null
      ? AppDatabase.open()
      : AppDatabase.memory();
  ref.onDispose(db.close);
  return db;
});

final localDatesProvider = Provider<LocalDates>((ref) => const LocalDates());

/// Foot photos (S8C): `<app support>/foot_photos`, app-private. A run
/// with an in-memory database (mock preset, emulator driver) uses its own
/// cache folder: its start-up sweep sees no saved checks and would
/// otherwise delete every real photo on the phone.
String footPhotoPath({
  required bool inMemory,
  required String support,
  required String cache,
}) => inMemory ? '$cache/foot_photos_memory' : '$support/foot_photos';

final footPhotoDirProvider = Provider<Future<Directory> Function()>((ref) {
  final inMemory = ref.watch(databaseProvider).inMemory;
  return () async => Directory(
    footPhotoPath(
      inMemory: inMemory,
      support: (await getApplicationSupportDirectory()).path,
      cache: (await getTemporaryDirectory()).path,
    ),
  );
});

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => DriftAlertRepository(
    ref.watch(databaseProvider),
    ref.watch(localDatesProvider),
  ),
);

final temperatureRepositoryProvider = Provider<TemperatureRepository>(
  (ref) => DriftTemperatureRepository(
    ref.watch(databaseProvider),
    ref.watch(localDatesProvider),
  ),
);

final dailySummaryRepositoryProvider = Provider<DailySummaryRepository>(
  (ref) => DriftDailySummaryRepository(
    ref.watch(databaseProvider),
    ref.watch(localDatesProvider),
  ),
);

final footCheckRepositoryProvider = Provider<FootCheckRepository>(
  (ref) => DriftFootCheckRepository(
    ref.watch(databaseProvider),
    ref.watch(localDatesProvider),
  ),
);

/// Unread patient-visible alerts (the Alerts badge).
final unreadAlertsProvider = StreamProvider<int>(
  (ref) => ref
      .watch(alertRepositoryProvider)
      .watchUnreadCount(ref.watch(clockProvider)().millisecondsSinceEpoch),
);

/// What the Alerts list shows (S6A's one visibility rule, newest first).
final visibleAlertsProvider = StreamProvider<List<StoredAlert>>(
  (ref) => ref
      .watch(alertRepositoryProvider)
      .watchVisible(ref.watch(clockProvider)().millisecondsSinceEpoch),
);

/// One stored alert, for its detail screen.
final alertByIdProvider = FutureProvider.autoDispose.family<StoredAlert?, int>(
  (ref, id) => ref.watch(alertRepositoryProvider).byId(id),
);

/// The researcher's "Clear app database (test data)" ([clearTestData]).
final clearTestDataProvider = Provider<Future<ClearedTestData> Function()>(
  (ref) =>
      () => clearTestData(
        ref.read(databaseProvider),
        photoDir: ref.read(footPhotoDirProvider),
      ),
);

/// Retention at start and once a day. Started by `StorageHost`.
final retentionScheduleProvider = Provider<RetentionSchedule>((ref) {
  final schedule = RetentionSchedule(
    Retention(
      ref.watch(databaseProvider),
      photoDir: ref.watch(footPhotoDirProvider),
      dates: ref.watch(localDatesProvider),
    ),
    now: ref.watch(clockProvider),
  )..start();
  ref.onDispose(schedule.stop);
  return schedule;
});

/// Stores every temperature reading. Started by `StorageHost`.
final temperatureRecorderProvider = Provider<TemperatureRecorder>((ref) {
  final recorder = TemperatureRecorder(
    manager: ref.watch(deviceManagerProvider),
    temperatures: ref.watch(temperatureRepositoryProvider),
    summaries: ref.watch(dailySummaryRepositoryProvider),
  )..start();
  ref.onDispose(recorder.stop);
  return recorder;
});

/// Both feet's temperature readings on one local day, oldest first: the
/// My feet chart (DESIGN-SPEC §8.2). Keyed by `YYYY-MM-DD`, so the chart
/// moves to the new day once the screen asks for it.
final dayTemperaturesProvider = StreamProvider.autoDispose
    .family<List<TemperatureReading>, String>(
      (ref, localDate) =>
          ref.watch(temperatureRepositoryProvider).watchDay(localDate),
    );

/// Row counts for the BLE debug screen.
final temperatureStatsProvider = StreamProvider.autoDispose<TemperatureStats>(
  (ref) => ref.watch(temperatureRepositoryProvider).watchStats(),
);

/// The alerts table's figures for the BLE debug screen (S7 phone check).
final alertStatsProvider = StreamProvider.autoDispose<AlertStats>(
  (ref) => ref.watch(alertRepositoryProvider).watchStats(),
);

/// Foot photos on the phone now (Settings). Refresh after a delete.
final footPhotoCountProvider = FutureProvider.autoDispose<int>(
  (ref) async => countFootPhotos(await ref.watch(footPhotoDirProvider)()),
);

/// Settings › "ลบรูปถ่ายเท้าทั้งหมด" ([deleteAllFootPhotos]).
final deleteFootPhotosProvider = Provider<Future<int> Function()>(
  (ref) =>
      () => deleteAllFootPhotos(
        ref.read(databaseProvider),
        photoDir: ref.read(footPhotoDirProvider),
      ),
);
