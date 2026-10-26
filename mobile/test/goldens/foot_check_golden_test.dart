@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/ui/routes.dart';

import '../footcheck/foot_check_rig.dart';
import '../helpers/pump_app.dart';

/// Daily foot check (DESIGN-SPEC §11, S8C): every screen state, plus the
/// drafts that are not on the boards (§14: history, viewer, camera panels,
/// cancel sheet, found tab, Settings' notification line). Scroll pages
/// render full height. Regenerate:
///   flutter test --update-goldens test/goldens/foot_check_golden_test.dart
void main() {
  Future<void> expectScreen(WidgetTester t, String name) async {
    await loadImages(t);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screens/foot_check_$name.png'),
    );
  }

  const tall = Size(390, 1500);
  const photoA = 'a/sole_left-0.jpg';
  const photoB = 'b/top_left-0.jpg';
  const photoC = 'c/sole_right-0.jpg';

  Future<void> openTab(WidgetTester t) async {
    await t.tap(byKey('tab-footCheck'));
    await settleIo(t);
  }

  Future<void> startPhotos(WidgetTester t) async {
    await openTab(t);
    await t.tap(byKey('foot-check-start-photos'));
    await settleIo(t);
  }

  group('tab', () {
    for (final (scale, name) in [(1.0, 'start_100'), (1.3, 'start_130')]) {
      testWidgets(name, (t) async {
        await FootCheckRig().pump(
          t,
          size: Size(390, scale == 1.0 ? 1300 : 1700),
          textScale: scale,
        );
        await openTab(t);
        await expectScreen(t, name);
      });
    }

    testWidgets('saved', (t) async {
      await FootCheckRig().pump(
        t,
        size: tall,
        checks: [checkAt(dayAt(0, 8, 5))],
      );
      await openTab(t);
      await expectScreen(t, 'saved');
    });

    testWidgets('saved_yesterday_found', (t) async {
      await FootCheckRig().pump(
        t,
        size: tall,
        checks: [
          checkAt(dayAt(3, 20)),
          checkAt(dayAt(1, 20), wound: yes),
          checkAt(dayAt(0, 8, 5)),
        ],
      );
      await openTab(t);
      await expectScreen(t, 'saved_yesterday_found');
    });

    testWidgets('saved_reminder_off', (t) async {
      await FootCheckRig(settings: const AppSettings(footCheckReminder: false))
          .pump(t, size: tall, checks: [checkAt(dayAt(0, 8, 5))]);
      await openTab(t);
      await expectScreen(t, 'saved_reminder_off');
    });

    testWidgets('found_today', (t) async {
      await FootCheckRig().pump(
        t,
        size: tall,
        checks: [
          checkAt(dayAt(1, 20)),
          checkAt(dayAt(0, 8, 30), redness: yes, swelling: yes),
        ],
      );
      await openTab(t);
      await expectScreen(t, 'found_today');
    });

    testWidgets('start_repeat', (t) async {
      await FootCheckRig().pump(t, size: tall, checks: [checkAt(dayAt(0, 8))]);
      await openTab(t);
      await tapKey(t, 'foot-check-again');
      await expectScreen(t, 'start_repeat');
    });
  });

  testWidgets('something_found', (t) async {
    await FootCheckRig().pump(
      t,
      size: tall,
      checks: [checkAt(dayAt(0, 8, 30), redness: yes, wound: yes)],
    );
    await openTab(t);
    await tapKey(t, 'foot-check-what-to-do');
    await settleIo(t);
    await expectScreen(t, 'something_found');
  });

  group('capture', () {
    testWidgets('capture_first', (t) async {
      await FootCheckRig().pump(t);
      await startPhotos(t);
      await expectScreen(t, 'capture_first');
    });

    testWidgets('capture_second', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, reduceMotion: true);
      await startPhotos(t);
      await t.tap(byKey('capture-shutter'));
      await settleIo(t, 300);
      await expectScreen(t, 'capture_second');
    });

    testWidgets('capture_top_back_camera', (t) async {
      await FootCheckRig().pump(t);
      await startPhotos(t);
      await t.tap(byKey('capture-skip'));
      await settleIo(t);
      await t.tap(byKey('capture-skip'));
      await settleIo(t);
      await expectScreen(t, 'capture_top_back_camera');
    });

    testWidgets('capture_countdown', (t) async {
      await FootCheckRig().pump(t, reduceMotion: true);
      await startPhotos(t);
      await t.tap(byKey('capture-timer'));
      await t.pump();
      await expectScreen(t, 'capture_countdown');
      await t.pump(const Duration(seconds: 3));
      await settleIo(t, 300);
    });

    testWidgets('capture_cancel_sheet', (t) async {
      await FootCheckRig().pump(t, reduceMotion: true);
      await startPhotos(t);
      await t.tap(byKey('capture-shutter'));
      await settleIo(t, 300);
      await t.tap(byKey('capture-cancel'));
      await settleIo(t);
      await expectScreen(t, 'capture_cancel_sheet');
    });

    testWidgets('capture_camera_denied', (t) async {
      final rig = FootCheckRig();
      rig.camera.deny = true;
      await rig.pump(t);
      await startPhotos(t);
      await expectScreen(t, 'capture_camera_denied');
    });

    testWidgets('capture_camera_failed', (t) async {
      final rig = FootCheckRig();
      rig.camera.fail = true;
      await rig.pump(t);
      await startPhotos(t);
      await expectScreen(t, 'capture_camera_failed');
    });
  });

  group('compare', () {
    final earlier = [
      checkAt(dayAt(1, 20), photos: {FootView.soleLeft: photoA}),
      checkAt(dayAt(4, 20), photos: {FootView.topLeft: photoB}),
      checkAt(dayAt(2, 20), photos: {FootView.soleRight: photoC}),
    ];

    Future<void> pumpCompare(WidgetTester t, {int shots = 4}) async {
      await FootCheckRig().pump(
        t,
        size: tall,
        reduceMotion: true,
        checks: earlier,
        photoFiles: [photoA, photoB, photoC],
      );
      await startPhotos(t);
      for (var i = 0; i < 4; i++) {
        await t.tap(byKey(i < shots ? 'capture-shutter' : 'capture-skip'));
        await settleIo(t, i < shots ? 300 : 150);
      }
      await settleIo(t);
    }

    testWidgets('compare_yesterday', (t) async {
      await pumpCompare(t);
      await expectScreen(t, 'compare_yesterday');
    });

    testWidgets('compare_earlier', (t) async {
      await pumpCompare(t);
      await t.tap(byKey('compare-view-topLeft'));
      await settleIo(t);
      await expectScreen(t, 'compare_earlier');
    });

    testWidgets('compare_none_answered', (t) async {
      await pumpCompare(t);
      await t.tap(byKey('compare-view-topRight'));
      await settleIo(t);
      for (final q in ['redness', 'wound', 'swelling']) {
        await tapKey(t, 'answer-$q-${q == 'wound' ? 'yesOrUnsure' : 'none'}');
      }
      await t.drag(find.byType(Scrollable).last, const Offset(0, 2000));
      await t.pumpAndSettle();
      await expectScreen(t, 'compare_none_answered');
    });

    testWidgets('compare_skipped', (t) async {
      await pumpCompare(t, shots: 0);
      await expectScreen(t, 'compare_skipped');
    });

    testWidgets('compare_answer_only', (t) async {
      await FootCheckRig().pump(t, size: tall);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      await expectScreen(t, 'compare_answer_only');
    });
  });

  group('photos', () {
    testWidgets('history', (t) async {
      await FootCheckRig().pump(
        t,
        size: tall,
        checks: [
          checkAt(
            dayAt(2, 20),
            photos: {FootView.soleLeft: photoA, FootView.topLeft: photoB},
          ),
          checkAt(dayAt(1, 20)),
          checkAt(dayAt(0, 8), photos: {FootView.soleRight: photoC}),
          checkAt(
            dayAt(0, 9),
            wound: yes,
            photos: {
              FootView.soleLeft: photoA,
              FootView.soleRight: photoC,
              FootView.topLeft: photoB,
              FootView.topRight: photoB,
            },
          ),
        ],
        photoFiles: [photoA, photoB, photoC],
        initialRoute: Routes.footCheckPhotos,
      );
      await settleIo(t);
      await expectScreen(t, 'history');
    });

    testWidgets('history_empty', (t) async {
      await FootCheckRig().pump(t, initialRoute: Routes.footCheckPhotos);
      await settleIo(t);
      await expectScreen(t, 'history_empty');
    });

    testWidgets('viewer', (t) async {
      await FootCheckRig().pump(
        t,
        checks: [
          checkAt(dayAt(1, 20), photos: {FootView.soleLeft: photoA}),
        ],
        photoFiles: [photoA],
        initialRoute: Routes.footCheckPhotos,
      );
      await settleIo(t);
      await t.tap(byKey('photo-1-soleLeft'));
      await settleIo(t);
      await expectScreen(t, 'viewer');
    });
  });

  testWidgets('settings_notify_denied', (t) async {
    final rig = FootCheckRig(allowed: false);
    rig.reminders.grantOnRequest = false;
    await rig.pump(
      t,
      size: const Size(390, 2100),
      initialRoute: Routes.settings,
    );
    await settleIo(t);
    expect(find.text('ต้องอนุญาตการแจ้งเตือนในโทรศัพท์'), findsOneWidget);
    await expectScreen(t, 'settings_notify_denied');
  });
}
