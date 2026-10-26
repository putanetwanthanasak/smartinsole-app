import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/models.dart';
import '../storage/storage_providers.dart';
import '../ui/clock.dart';
import 'compare_source.dart';
import 'foot_camera.dart';
import 'plugin_foot_camera.dart';

/// A new camera for each Capture screen. Tests and the emulator driver
/// may override it with a fake.
final footCameraProvider = Provider<FootCamera Function()>(
  (ref) => PluginFootCamera.new,
);

/// The app cache, where the camera plugin writes its temporary JPEGs.
final cameraCacheDirProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

/// Today's local day (midnight). Derived from the clock when read; a timer
/// at the next midnight and the app's resume only ask for a fresh read
/// (rule 2), so a starved timer can delay the Home card but never latch a
/// wrong day once anything reads again.
final todayProvider = NotifierProvider<Today, DateTime>(Today.new);

class Today extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = ref.watch(clockProvider)();
    final day = DateTime(now.year, now.month, now.day);
    final next = DateTime(now.year, now.month, now.day + 1);
    final timer = Timer(next.difference(now), refresh);
    ref.onDispose(timer.cancel);
    return day;
  }

  void refresh() {
    final now = ref.read(clockProvider)();
    final day = DateTime(now.year, now.month, now.day);
    if (day != state) ref.invalidateSelf();
  }
}

/// Today as the database's `YYYY-MM-DD`.
final todayDateProvider = Provider<String>(
  (ref) => ref
      .watch(localDatesProvider)
      .of(ref.watch(todayProvider).millisecondsSinceEpoch),
);

/// Today's latest check (null until one is saved): the tab shows Start or
/// Saved by it, and Home's card hides once it exists.
final todayCheckProvider = StreamProvider<FootCheck?>(
  (ref) => ref
      .watch(footCheckRepositoryProvider)
      .watchLatestOn(ref.watch(todayDateProvider)),
);

/// The 7 days up to today, oldest first (Saved's 7-day card).
final weekDatesProvider = Provider<List<String>>((ref) {
  final today = ref.watch(todayDateProvider);
  return [for (var d = -6; d <= 0; d++) shiftLocalDate(today, d)];
});

final weekChecksProvider = StreamProvider<List<FootCheck>>((ref) {
  final days = ref.watch(weekDatesProvider);
  return ref
      .watch(footCheckRepositoryProvider)
      .watchRange(days.first, days.last);
});

/// Checks with photos, newest first (photo history).
final photoHistoryProvider = StreamProvider.autoDispose<List<FootCheck>>(
  (ref) => ref.watch(footCheckRepositoryProvider).watchWithPhotos(),
);

/// Compare's left photo for one view.
final compareSourceProvider = FutureProvider.autoDispose
    .family<CompareSource, FootView>((ref, view) async {
      final today = ref.watch(todayDateProvider);
      final photo = await ref
          .watch(footCheckRepositoryProvider)
          .latestPhotoBefore(view, today);
      return compareSourceOf(photo, today);
    });

/// One saved check (Something found).
final footCheckByIdProvider = FutureProvider.autoDispose
    .family<FootCheck?, int>(
      (ref, id) => ref.watch(footCheckRepositoryProvider).byId(id),
    );

/// The foot-photo folder, resolved (thumbnails and the viewer).
final footPhotoDirResolvedProvider = FutureProvider<Directory>(
  (ref) => ref.watch(footPhotoDirProvider)(),
);
