import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';

import 'storage_rig.dart';

void main() {
  final at = bkk(2026, 10, 24, 20, 15);
  const yes = FootCheckAnswer.yesOrUnsure;
  const none = FootCheckAnswer.none;

  test('all "ไม่มี" saves as saved, with no alert', () async {
    final rig = StorageRig();
    final c = await rig.footChecks.save(draftOf(at));
    expect(c.result, FootCheckResult.saved);
    expect(c.localDate, '2026-10-24');
    expect([c.redness, c.wound, c.swelling], [none, none, none]);
    expect(c.answerOnly, isTrue);
    expect(c.photos, isEmpty);
    expect(await rig.db.select(rig.db.alerts).get(), isEmpty);
    expect((await rig.summaries.get('2026-10-24'))!.footCheckDone, isTrue);
  });

  test(
    'any "มี / ไม่แน่ใจ" is a finding, logged as an alert (rule 14)',
    () async {
      for (final draft in [
        draftOf(at, redness: yes),
        draftOf(at, wound: yes),
        draftOf(at, swelling: yes),
        draftOf(at, redness: yes, wound: yes, swelling: yes),
      ]) {
        final rig = StorageRig();
        final c = await rig.footChecks.save(draft);
        expect(c.result, FootCheckResult.found);
        final alerts = await rig.alerts.watchVisible(at).first;
        expect(alerts, hasLength(1));
        final a = alerts.single;
        expect(a.kind, AlertKind.footCheckFinding);
        expect(a.level, 3);
        expect(a.patientLevel, PatientLevel.careful);
        expect(a.footCheckId, c.id);
        expect(a.atMs, at);
        expect(await rig.alerts.watchUnreadCount(at).first, 1);
        final s = (await rig.summaries.get('2026-10-24'))!;
        expect(s.footCheckDone, isTrue);
        expect(s.alertsByLevel, [0, 0, 1, 0, 0]);
      }
    },
  );

  test('the result rule never says fine with a "not sure" in it', () {
    expect(footCheckResultOf([none, none, none]), FootCheckResult.saved);
    expect(footCheckResultOf([none, yes, none]), FootCheckResult.found);
  });

  test(
    'saving with an unanswered question is refused and writes nothing',
    () async {
      final rig = StorageRig();
      for (final draft in [
        draftOf(at, redness: null),
        draftOf(at, wound: null),
        draftOf(at, swelling: null),
      ]) {
        await expectLater(rig.footChecks.save(draft), throwsArgumentError);
      }
      expect(await rig.db.select(rig.db.footChecks).get(), isEmpty);
      expect(await rig.summaries.get('2026-10-24'), isNull);
    },
  );

  test(
    'photo paths read back per view; a skipped view stays missing',
    () async {
      final rig = StorageRig();
      final c = await rig.footChecks.save(
        draftOf(
          at,
          photos: {
            FootView.soleLeft: '2026-10-24/sole_left.jpg',
            FootView.topRight: '2026-10-24/top_right.jpg',
          },
        ),
      );
      expect(c.answerOnly, isFalse);
      expect(c.photos, {
        FootView.soleLeft: '2026-10-24/sole_left.jpg',
        FootView.topRight: '2026-10-24/top_right.jpg',
      });
      expect((await rig.footChecks.byId(c.id))!.photos, c.photos);
    },
  );

  test(
    'latest on a day is the last saved; range covers the 7-day row',
    () async {
      final rig = StorageRig();
      expect(await rig.footChecks.watchLatestOn('2026-10-24').first, isNull);
      await rig.footChecks.save(draftOf(bkk(2026, 10, 22, 20)));
      await rig.footChecks.save(draftOf(at - 60000, wound: yes));
      final last = await rig.footChecks.save(draftOf(at));
      expect(
        (await rig.footChecks.watchLatestOn('2026-10-24').first)!.id,
        last.id,
      );
      final week = await rig.footChecks.range('2026-10-18', '2026-10-24');
      expect(week.map((c) => c.localDate), [
        '2026-10-22',
        '2026-10-24',
        '2026-10-24',
      ]);
    },
  );
}
