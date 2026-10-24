import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../device/device_providers.dart';
import '../ui/clock.dart';
import 'alert_repository.dart';
import 'daily_summary_repository.dart';
import 'database.dart';
import 'foot_check_repository.dart';
import 'local_date.dart';
import 'retention.dart';
import 'temperature_recorder.dart';
import 'temperature_repository.dart';

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

/// Foot photos (S8C): `<app support>/foot_photos`, app-private.
final footPhotoDirProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        '${(await getApplicationSupportDirectory()).path}/foot_photos',
      ),
);

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

/// Row counts for the BLE debug screen.
final temperatureStatsProvider = StreamProvider.autoDispose<TemperatureStats>(
  (ref) => ref.watch(temperatureRepositoryProvider).watchStats(),
);

/// The alerts table's figures for the BLE debug screen (S7 phone check).
final alertStatsProvider = StreamProvider.autoDispose<AlertStats>(
  (ref) => ref.watch(alertRepositoryProvider).watchStats(),
);
