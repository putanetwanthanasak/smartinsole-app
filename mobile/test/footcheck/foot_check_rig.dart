import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';

import '../helpers/fake_foot_camera.dart';
import '../helpers/fake_reminder_notifier.dart';
import '../helpers/pump_app.dart';

const yes = FootCheckAnswer.yesOrUnsure;
const no = FootCheckAnswer.none;

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Directionality).first),
);

/// A local time on [fixedNow]'s day, [daysAgo] days back.
DateTime dayAt(int daysAgo, int hour, [int minute = 0]) => DateTime(
  fixedNow.year,
  fixedNow.month,
  fixedNow.day - daysAgo,
  hour,
  minute,
);

FootCheckDraft checkAt(
  DateTime at, {
  FootCheckAnswer redness = no,
  FootCheckAnswer wound = no,
  FootCheckAnswer swelling = no,
  Map<FootView, String> photos = const {},
}) => FootCheckDraft(
  atMs: at.millisecondsSinceEpoch,
  redness: redness,
  wound: wound,
  swelling: swelling,
  answerOnly: photos.isEmpty,
  photos: photos,
);

/// The app on [fixedNow] with [checks] already saved, photos in a temp
/// folder (with [photoFiles] written as small JPEGs).
class FootCheckRig {
  FootCheckRig({
    this.allowed = true,
    AppSettings settings = const AppSettings(),
  }) : settings = MemorySettingsStore(settings: settings) {
    reminders.allowed = allowed;
  }

  final bool allowed;
  final MemorySettingsStore settings;
  final db = AppDatabase.memory();
  final camera = FakeFootCamera();
  final reminders = FakeReminderNotifier();
  final photoDir = Directory.systemTemp.createTempSync('foot_photos');

  Future<void> pump(
    WidgetTester tester, {
    List<FootCheckDraft> checks = const [],
    List<String> photoFiles = const [],
    String? initialRoute,
    bool reduceMotion = false,
    Size size = referenceSize,
    double textScale = 1.0,
  }) async {
    await tester.runAsync(() async {
      final repo = DriftFootCheckRepository(db);
      for (final c in checks) {
        await repo.save(c);
      }
      for (final f in photoFiles) {
        final file = File('${photoDir.path}/$f');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(FakeFootCamera.jpegOf(f.length));
      }
    });
    await pumpApp(
      tester,
      database: db,
      camera: camera,
      reminders: reminders,
      settings: settings,
      photoDir: photoDir,
      reduceMotion: reduceMotion,
      size: size,
      textScale: textScale,
      initialRoute: initialRoute ?? '/',
    );
  }
}

/// Lets real I/O (database, files) finish, then settles the frames. Real
/// I/O completes only inside `runAsync`, and the futures waiting on it
/// move on only when a frame is pumped, so the two alternate.
Future<void> settleIo(WidgetTester tester, [int ms = 150]) async {
  for (var i = 0; i < ms ~/ 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  if (byKey(key).evaluate().isEmpty) {
    // Lazy lists build only what is near the screen: scroll to it.
    await tester.scrollUntilVisible(
      byKey(key),
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(byKey(key));
  await tester.pumpAndSettle();
}

/// Decodes every image on screen (file images need real I/O), so a golden
/// shows the photos and not their placeholders.
Future<void> loadImages(WidgetTester tester) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  final context = tester.element(find.byType(Navigator).first);
  await tester.runAsync(() async {
    for (final i in images) {
      await precacheImage(i.image, context);
    }
  });
  await tester.pumpAndSettle();
}
