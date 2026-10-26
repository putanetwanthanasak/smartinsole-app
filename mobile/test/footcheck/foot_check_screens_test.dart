import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/footcheck/foot_views.dart';
import 'package:smartinsole/footcheck/footcheck_providers.dart';
import 'package:smartinsole/settings/settings_providers.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/clock.dart';
import 'package:smartinsole/ui/screens/foot_check/capture_screen.dart';
import 'package:smartinsole/ui/screens/foot_check/compare_screen.dart';
import 'package:smartinsole/ui/screens/foot_check/foot_check_copy.dart';
import 'package:smartinsole/ui/screens/foot_check/foot_guide.dart';
import 'package:smartinsole/ui/screens/foot_check/photo_history_screen.dart';
import 'package:smartinsole/ui/screens/foot_check_found_screen.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helpers/pump_app.dart';
import 'foot_check_rig.dart';

Future<void> openTab(WidgetTester tester) async {
  await tester.tap(byKey('tab-footCheck'));
  await settleIo(tester);
}

Future<void> answerAll(WidgetTester tester, FootCheckAnswer a) async {
  for (final q in ['redness', 'wound', 'swelling']) {
    await tapKey(tester, 'answer-$q-${a.name}');
  }
}

void main() {
  /// Unread foot-check findings in the database.
  Future<int> unreadFindings(WidgetTester t) async {
    final alerts = await t.runAsync(
      () =>
          containerOf(t)
              .read(alertRepositoryProvider)
              .watchVisible(fixedNow.millisecondsSinceEpoch + 1000)
              .first,
    );
    return alerts!
        .where((a) => a.kind == AlertKind.footCheckFinding && !a.isRead)
        .length;
  }

  group('guide outline (decision 1)', () {
    test('left foot uses the left outline as the preview shows it', () {
      // Front preview mirrored: a sole looks like its own top outline.
      expect(
        guideOutlineOf(FootView.soleLeft, previewMirrored: true),
        FootSide.left,
      );
      expect(
        guideOutlineOf(FootView.soleRight, previewMirrored: true),
        FootSide.right,
      );
      // Back camera on the top: the true top view.
      expect(
        guideOutlineOf(FootView.topLeft, previewMirrored: false),
        FootSide.left,
      );
      // Back camera on a sole (a relative holds the phone): true sole view,
      // which looks like the other foot's top outline.
      expect(
        guideOutlineOf(FootView.soleLeft, previewMirrored: false),
        FootSide.right,
      );
      expect(
        guideOutlineOf(FootView.topRight, previewMirrored: true),
        FootSide.left,
      );
    });

    test('soles start on the front camera, tops on the back', () {
      expect(FootView.soleLeft.autoFacing, CameraFacing.front);
      expect(FootView.topRight.autoFacing, CameraFacing.back);
    });
  });

  group('tab and Home card', () {
    testWidgets('no check today: Start in the tab, card on Home', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await settleIo(t);
      expect(byKey('foot-check-card'), findsOneWidget);
      await openTab(t);
      expect(byKey('foot-check-start'), findsOneWidget);
      expect(find.text(FootCheckCopy.startPhotos), findsOneWidget);
    });

    testWidgets('saved today: Saved in the tab, no card on Home', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, checks: [checkAt(dayAt(0, 8, 5))]);
      await settleIo(t);
      expect(byKey('foot-check-card'), findsNothing);
      await openTab(t);
      expect(byKey('foot-check-saved'), findsOneWidget);
      expect(find.text(FootCheckCopy.checkedAt('08:05')), findsOneWidget);
      expect(find.text(FootCheckCopy.remindAt('19:00')), findsOneWidget);
      expect(byKey('foot-check-yesterday-found'), findsNothing);
    });

    testWidgets('a check yesterday does not hide today\'s card', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, checks: [checkAt(dayAt(1, 20))]);
      await settleIo(t);
      expect(byKey('foot-check-card'), findsOneWidget);
    });

    testWidgets('yesterday found + today saved: the warning box', (t) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [
          checkAt(dayAt(1, 20), wound: yes),
          checkAt(dayAt(0, 8)),
        ],
      );
      await openTab(t);
      expect(byKey('foot-check-yesterday-found'), findsOneWidget);
    });

    testWidgets('the latest check of the day is the day result '
        '(found, then saved again)', (t) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [
          checkAt(dayAt(0, 7), wound: yes),
          checkAt(dayAt(0, 8)),
        ],
      );
      await openTab(t);
      expect(byKey('foot-check-saved'), findsOneWidget);
    });

    testWidgets('found today: the result card, answers and its link', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [checkAt(dayAt(0, 8, 30), redness: yes, swelling: yes)],
      );
      await openTab(t);
      expect(byKey('foot-check-found-today'), findsOneWidget);
      expect(find.text(FootCheckCopy.foundTodayTitle), findsOneWidget);
      expect(find.text('เห็นรอยแดง หรือผิวเปลี่ยนสี'), findsOneWidget);
      expect(find.text('เท้าบวม หรือผิดรูปไปจากเดิม'), findsOneWidget);
      expect(find.text('เห็นแผล รอยถลอก หรือตุ่มพอง'), findsNothing);
      expect(await unreadFindings(t), 1);
      await tapKey(t, 'foot-check-what-to-do');
      await settleIo(t);
      expect(find.byType(FootCheckFoundScreen), findsOneWidget);
      expect(find.text(FootCheckCopy.foundTitle), findsOneWidget);
      // Something found is the finding's result screen (§7.2 decision 7).
      expect(await unreadFindings(t), 0);
    });

    testWidgets('"ตรวจอีกครั้ง" shows Start with a back link to Saved', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t, checks: [checkAt(dayAt(0, 8))]);
      await openTab(t);
      await tapKey(t, 'foot-check-again');
      expect(byKey('foot-check-start'), findsOneWidget);
      await tapKey(t, 'back-link');
      expect(byKey('foot-check-saved'), findsOneWidget);
    });

    testWidgets('the 7-day row: latest per day, missed days, labels', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [
          checkAt(dayAt(6, 20)),
          checkAt(dayAt(2, 20), wound: yes),
          checkAt(dayAt(0, 8)),
        ],
      );
      await openTab(t);
      final labels = [
        for (final d in [6, 5, 4, 3, 2, 1, 0])
          FootCheckCopy.weekdayShort(dayAt(d, 0)),
      ];
      expect(
        find.bySemanticsLabel('${labels[0]} ${FootCheckCopy.daySaved}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('${labels[4]} ${FootCheckCopy.dayFound}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('${labels[5]} ${FootCheckCopy.dayMissed}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${FootCheckCopy.today} ${labels[6]} ${FootCheckCopy.daySaved}',
        ),
        findsOneWidget,
      );
    });
  });

  group('answer-only flow', () {
    testWidgets('no picker or photos; "บันทึก" only after all 3 answers; '
        'all "ไม่มี" → Saved', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      expect(find.byType(CompareScreen), findsOneWidget);
      expect(byKey('compare-view-soleLeft'), findsNothing);
      expect(byKey('compare-today'), findsNothing);
      FilledButton save() => t.widget<FilledButton>(
        find.descendant(
          of: byKey('compare-save'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(save().onPressed, isNull);
      await tapKey(t, 'answer-redness-none');
      await tapKey(t, 'answer-wound-none');
      expect(save().onPressed, isNull);
      await tapKey(t, 'answer-swelling-none');
      expect(save().onPressed, isNotNull);
      await t.tap(byKey('compare-save'));
      await settleIo(t, 300);
      expect(find.byType(CompareScreen), findsNothing);
      expect(byKey('foot-check-saved'), findsOneWidget);
      final stored = await t.runAsync(
        () =>
            containerOf(t)
                .read(footCheckRepositoryProvider)
                .range('2026-10-18', '2026-10-18'),
      );
      expect(stored!.single.result, FootCheckResult.saved);
      expect(stored.single.answerOnly, isTrue);
    });

    testWidgets('Saved opens at the top, not at Start\'s scroll offset', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t, textScale: 1.3);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      await answerAll(t, FootCheckAnswer.none);
      await t.tap(byKey('compare-save'));
      await settleIo(t, 300);
      final scroll = t.state<ScrollableState>(
        find
            .ancestor(
              of: byKey('foot-check-saved'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.position.pixels, 0);
    });

    testWidgets('"มี / ไม่แน่ใจ" → Something found + an alert (rule 14)', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      await tapKey(t, 'answer-redness-none');
      await tapKey(t, 'answer-wound-yesOrUnsure');
      await tapKey(t, 'answer-swelling-none');
      await t.tap(byKey('compare-save'));
      await settleIo(t, 300);
      expect(find.byType(FootCheckFoundScreen), findsOneWidget);
      await settleIo(t);
      expect(find.text('เห็นแผล รอยถลอก หรือตุ่มพอง'), findsOneWidget);
      final alerts = await t.runAsync(
        () =>
            containerOf(t)
                .read(alertRepositoryProvider)
                .watchVisible(fixedNow.millisecondsSinceEpoch + 1000)
                .first,
      );
      expect(alerts!.single.kind, AlertKind.footCheckFinding);
      // Opened right after "บันทึก": read, so the badge doesn't count it.
      expect(alerts.single.isRead, isTrue);
      expect(await unreadFindings(t), 0);
      await tapKey(t, 'found-home');
      expect(byKey('home-scroll'), findsOneWidget);
    });

    testWidgets('a selected answer is announced as checked in its group', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      await tapKey(t, 'answer-wound-yesOrUnsure');
      final data = t
          .getSemantics(byKey('answer-wound-yesOrUnsure'))
          .getSemanticsData();
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(data.flagsCollection.isChecked, isNotNull);
    });
  });

  group('capture', () {
    Future<void> startPhotos(WidgetTester t) async {
      await openTab(t);
      await t.tap(byKey('foot-check-start-photos'));
      await settleIo(t);
      expect(find.byType(CaptureScreen), findsOneWidget);
    }

    Future<void> shoot(WidgetTester t) async {
      await t.tap(byKey('capture-shutter'));
      await settleIo(t, 300);
    }

    testWidgets('soles open the front camera, tops the back; the switch '
        'holds for views of the same kind', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await startPhotos(t);
      expect(rig.camera.opened.last, CameraFacing.front);
      expect(find.text('ฝ่าเท้าซ้าย'), findsOneWidget);
      expect(find.text(FootCheckCopy.counter(1)), findsOneWidget);
      await t.tap(byKey('capture-switch'));
      await settleIo(t);
      expect(rig.camera.opened.last, CameraFacing.back);
      await t.tap(byKey('capture-skip'));
      await settleIo(t);
      expect(find.text('ฝ่าเท้าขวา'), findsOneWidget);
      expect(rig.camera.current, CameraFacing.back); // still switched
      await t.tap(byKey('capture-skip'));
      await settleIo(t);
      expect(find.text('หลังเท้าซ้าย'), findsOneWidget);
      expect(rig.camera.current, CameraFacing.back); // top default
    });

    testWidgets('4 photos are stored in the app folder; Compare shows '
        'them; saving keeps them on the check', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await startPhotos(t);
      for (var i = 0; i < 4; i++) {
        await shoot(t);
      }
      await settleIo(t, 300);
      expect(find.byType(CompareScreen), findsOneWidget);
      final files = rig.photoDir
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(files, hasLength(4));
      expect(byKey('compare-today'), findsOneWidget);
      expect(find.text(FootCheckCopy.noEarlier), findsOneWidget);
      await answerAll(t, FootCheckAnswer.none);
      await t.tap(byKey('compare-save'));
      await settleIo(t, 300);
      final stored = await t.runAsync(
        () =>
            containerOf(t)
                .read(footCheckRepositoryProvider)
                .range('2026-10-18', '2026-10-18'),
      );
      expect(stored!.single.photos.keys, FootView.values);
      expect(stored.single.answerOnly, isFalse);
      for (final rel in stored.single.photos.values) {
        expect(File('${rig.photoDir.path}/$rel').existsSync(), isTrue);
      }
    });

    testWidgets('cancel with no photo leaves at once', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await startPhotos(t);
      await t.tap(byKey('capture-cancel'));
      await settleIo(t);
      expect(find.byType(CaptureScreen), findsNothing);
      expect(byKey('sheet-confirm'), findsNothing);
    });

    testWidgets('cancel after a photo asks first; "ถ่ายต่อ" stays, '
        '"ยกเลิกการตรวจ" deletes the photos (user addition 7)', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await startPhotos(t);
      await shoot(t);
      await t.tap(byKey('capture-cancel'));
      await settleIo(t);
      expect(find.text(FootCheckCopy.cancelSheetTitle), findsOneWidget);
      expect(find.text(FootCheckCopy.cancelSheetText), findsOneWidget);
      await t.tap(find.text(FootCheckCopy.cancelSheetKeep));
      await settleIo(t);
      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(
        rig.photoDir.listSync(recursive: true).whereType<File>(),
        hasLength(1),
      );
      await t.tap(byKey('capture-cancel'));
      await settleIo(t);
      await t.tap(find.text(FootCheckCopy.cancelSheetConfirm));
      await settleIo(t, 300);
      expect(find.byType(CaptureScreen), findsNothing);
      expect(rig.photoDir.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    testWidgets('self-timer counts 3, 2, 1 and then shoots', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, reduceMotion: true);
      await startPhotos(t);
      await t.tap(byKey('capture-timer'));
      await t.pump();
      expect(find.text('3'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(rig.camera.shots, 0);
      await t.pump(const Duration(seconds: 1));
      await settleIo(t, 300);
      expect(rig.camera.shots, 1);
      expect(find.text('ฝ่าเท้าขวา'), findsOneWidget);
    });

    testWidgets('an open overtaken by the app going inactive (the '
        'permission dialog) does not count; resume opens again', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      rig.camera.gate = Completer<void>();
      await openTab(t);
      await t.tap(byKey('foot-check-start-photos'));
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      rig.camera.gate!.complete();
      rig.camera.gate = null;
      await settleIo(t);
      expect(byKey('fake-preview'), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIo(t);
      expect(byKey('fake-preview'), findsOneWidget);
      expect(rig.camera.opened, hasLength(2));
    });

    testWidgets('a shot, skip or switch stops a running self-timer: it '
        'never takes the next view', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, reduceMotion: true);
      await startPhotos(t);
      await t.tap(byKey('capture-timer'));
      await t.pump();
      expect(find.text('3'), findsOneWidget);
      await t.tap(byKey('capture-skip'));
      await settleIo(t);
      expect(find.text('ฝ่าเท้าขวา'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await settleIo(t, 300);
      expect(rig.camera.shots, 0);
      expect(find.text('ฝ่าเท้าขวา'), findsOneWidget);

      await t.tap(byKey('capture-timer'));
      await t.pump();
      await t.tap(byKey('capture-switch'));
      await settleIo(t);
      expect(find.text('3'), findsNothing);
      await t.pump(const Duration(seconds: 4));
      await settleIo(t, 300);
      expect(rig.camera.shots, 0);
    });

    testWidgets('camera refused: "อนุญาต" asks again while Android still '
        'shows its dialog, else opens settings', (t) async {
      final rig = FootCheckRig();
      rig.camera.deny = true;
      await rig.pump(t);
      await startPhotos(t);
      expect(find.text(FootCheckCopy.cameraDenied), findsOneWidget);
      await t.tap(byKey('capture-camera-action'));
      await settleIo(t);
      expect(rig.camera.settingsOpened, 0);
      expect(find.text(FootCheckCopy.cameraDenied), findsOneWidget);

      rig.camera.askAgain = false;
      await t.tap(byKey('capture-camera-action'));
      await settleIo(t);
      await t.tap(byKey('capture-camera-action'));
      await settleIo(t);
      expect(rig.camera.settingsOpened, 1);

      rig.camera.deny = false;
      await t.tap(byKey('capture-camera-action'));
      await settleIo(t);
      expect(rig.camera.settingsOpened, 2);
    });

    testWidgets('camera refused with no photo: answer-only has no picker '
        'and no photos; back returns to the tab', (t) async {
      final rig = FootCheckRig();
      rig.camera.deny = true;
      await rig.pump(t);
      await startPhotos(t);
      await t.tap(byKey('capture-answer-only'));
      await settleIo(t);
      expect(find.byType(CompareScreen), findsOneWidget);
      expect(byKey('compare-view-soleLeft'), findsNothing);
      expect(find.text(FootCheckCopy.skipped), findsNothing);
      expect(find.byType(CaptureScreen), findsNothing);
      await t.tap(byKey('back-link'));
      await settleIo(t);
      expect(find.byType(CompareScreen), findsNothing);
      expect(byKey('foot-check-start-photos'), findsOneWidget);
    });

    testWidgets('camera failing after a photo: answer-only keeps the photo '
        'taken', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, reduceMotion: true);
      await startPhotos(t);
      await shoot(t);
      rig.camera.fail = true;
      await t.tap(byKey('capture-switch'));
      await settleIo(t);
      expect(find.text(FootCheckCopy.cameraFailed), findsOneWidget);
      await t.tap(byKey('capture-answer-only'));
      await settleIo(t);
      expect(find.byType(CompareScreen), findsOneWidget);
      expect(byKey('compare-view-soleLeft'), findsOneWidget);
      expect(
        rig.photoDir.listSync(recursive: true).whereType<File>(),
        hasLength(1),
      );
    });
  });

  group('compare source', () {
    testWidgets('yesterday\'s photo is captioned "เมื่อวาน"; an older one '
        '"ครั้งก่อน" with its date', (t) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [
          checkAt(
            dayAt(1, 20),
            photos: {FootView.soleLeft: 'a/sole_left-0.jpg'},
          ),
          checkAt(dayAt(3, 20), photos: {FootView.topLeft: 'b/top_left-0.jpg'}),
        ],
        photoFiles: ['a/sole_left-0.jpg', 'b/top_left-0.jpg'],
      );
      await openTab(t);
      await t.tap(byKey('foot-check-start-photos'));
      await settleIo(t);
      for (var i = 0; i < 4; i++) {
        await t.tap(byKey('capture-skip'));
        await settleIo(t);
      }
      await settleIo(t);
      expect(
        find.text(
          '${FootCheckCopy.yesterday} · ${FootCheckCopy.dayMonth(dayAt(1, 0))}',
        ),
        findsOneWidget,
      );
      expect(find.text(FootCheckCopy.skipped), findsOneWidget);
      await t.tap(byKey('compare-view-topLeft'));
      await settleIo(t);
      expect(
        find.text(
          '${FootCheckCopy.earlier} · ${FootCheckCopy.dayMonth(dayAt(3, 0))}',
        ),
        findsOneWidget,
      );
      await t.tap(byKey('compare-view-topRight'));
      await settleIo(t);
      expect(find.text(FootCheckCopy.noEarlier), findsOneWidget);
    });
  });

  group('photo history', () {
    testWidgets('grouped by day, only checks with photos; tap opens the '
        'viewer', (t) async {
      final rig = FootCheckRig();
      await rig.pump(
        t,
        checks: [
          checkAt(
            dayAt(2, 20),
            photos: {FootView.soleLeft: 'a/sole_left-0.jpg'},
          ),
          checkAt(dayAt(1, 20)),
          checkAt(
            dayAt(0, 8),
            photos: {FootView.topRight: 'b/top_right-0.jpg'},
          ),
        ],
        photoFiles: ['a/sole_left-0.jpg', 'b/top_right-0.jpg'],
        initialRoute: '/foot-check/photos',
      );
      await settleIo(t);
      expect(find.byType(PhotoHistoryScreen), findsOneWidget);
      expect(find.textContaining('วันนี้ · '), findsOneWidget);
      expect(find.textContaining('เมื่อวาน'), findsNothing);
      expect(find.text(FootCheckCopy.notTaken), findsNWidgets(6));
      await t.tap(find.byKey(const ValueKey('photo-3-topRight')));
      await settleIo(t);
      expect(byKey('viewer-close'), findsOneWidget);
      await t.tap(byKey('viewer-close'));
      await settleIo(t);
      expect(find.byType(PhotoHistoryScreen), findsOneWidget);
    });

    testWidgets('empty state', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t, initialRoute: '/foot-check/photos');
      await settleIo(t);
      expect(find.text(FootCheckCopy.historyEmpty), findsOneWidget);
    });
  });

  group('reminder (user decision 2)', () {
    testWidgets('scheduled from start; today dropped once saved', (t) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await settleIo(t);
      expect(rig.reminders.pending.keys.first, dayAt(0, 19));
      expect(rig.reminders.pending.values.every((s) => s), isTrue);
      await openTab(t);
      await tapKey(t, 'foot-check-answer-only');
      await answerAll(t, FootCheckAnswer.none);
      await t.tap(byKey('compare-save'));
      await settleIo(t, 300);
      expect(rig.reminders.pending.keys.first, dayAt(-1, 19));
      expect(rig.reminders.cancelledDays, isNotEmpty);
    });

    testWidgets('switch off: none; sound off: silent; new time moves them', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await settleIo(t);
      final c = containerOf(t).read(settingsProvider.notifier);
      await c.setSound(false);
      await settleIo(t);
      expect(rig.reminders.pending.values.every((s) => !s), isTrue);
      await c.setReminderTime(const TimeOfDay(hour: 21, minute: 15));
      await settleIo(t);
      expect(rig.reminders.pending.keys.first, dayAt(0, 21, 15));
      await c.setFootCheckReminder(false);
      await settleIo(t);
      expect(rig.reminders.pending, isEmpty);
    });

    testWidgets('a reminder that started the app opens "ตรวจเท้า"', (t) async {
      final rig = FootCheckRig();
      rig.reminders.launched = true;
      await rig.pump(t);
      await settleIo(t);
      expect(byKey('foot-check-start'), findsOneWidget);
    });

    testWidgets('tapping a reminder while open returns to "ตรวจเท้า"', (
      t,
    ) async {
      final rig = FootCheckRig();
      await rig.pump(t);
      await settleIo(t);
      await t.tap(byKey('settings-button'));
      await settleIo(t);
      rig.reminders.onTap!();
      await settleIo(t);
      expect(byKey('foot-check-start'), findsOneWidget);
    });
  });

  group('notification permission (user decision 3)', () {
    testWidgets('asked once, at the first open of the tab', (t) async {
      final rig = FootCheckRig(allowed: false);
      rig.reminders.grantOnRequest = false;
      await rig.pump(t);
      await settleIo(t);
      expect(rig.reminders.requests, 0);
      await openTab(t);
      expect(rig.reminders.requests, 1);
      expect(rig.settings.notificationPromptShown, isTrue);
      await t.tap(byKey('tab-today'));
      await settleIo(t);
      await openTab(t);
      expect(rig.reminders.requests, 1);
    });

    testWidgets('denied: Settings shows the line; tapping asks, then opens '
        'the phone settings', (t) async {
      final rig = FootCheckRig(allowed: false);
      rig.reminders.grantOnRequest = false;
      await rig.pump(t, initialRoute: '/settings');
      await settleIo(t);
      expect(byKey('settings-notify-denied'), findsOneWidget);
      await tapKey(t, 'settings-notify-denied');
      await settleIo(t);
      expect(rig.reminders.requests, 1);
      expect(rig.reminders.settingsOpened, 1);
      rig.reminders.allowed = true;
      await tapKey(t, 'settings-notify-denied');
      await settleIo(t);
      expect(byKey('settings-notify-denied'), findsNothing);
    });

    testWidgets('denied: Saved hides the reminder line', (t) async {
      final rig = FootCheckRig(allowed: false);
      rig.reminders.grantOnRequest = false;
      rig.settings.notificationPromptShown = true;
      await rig.pump(t, checks: [checkAt(dayAt(0, 8))]);
      await openTab(t);
      expect(find.text(FootCheckCopy.remindAt('19:00')), findsNothing);
    });
  });

  group('today', () {
    test('rolls over at local midnight when asked again', () {
      var now = DateTime(2026, 10, 18, 23, 59);
      final c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      expect(c.read(todayProvider), DateTime(2026, 10, 18));
      now = DateTime(2026, 10, 19, 0, 1);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(todayProvider), DateTime(2026, 10, 19));
    });
  });
}
