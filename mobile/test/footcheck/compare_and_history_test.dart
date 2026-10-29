import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/footcheck/compare_source.dart';
import 'package:smartinsole/footcheck/history.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/models.dart';

import '../storage/storage_rig.dart';

const yes = FootCheckAnswer.yesOrUnsure;

void main() {
  group('dates', () {
    test('previous and shifted dates cross months and years', () {
      expect(previousLocalDate('2026-10-26'), '2026-10-25');
      expect(previousLocalDate('2026-11-01'), '2026-10-31');
      expect(previousLocalDate('2027-01-01'), '2026-12-31');
      expect(shiftLocalDate('2026-10-26', -6), '2026-10-20');
      expect(shiftLocalDate('2028-02-28', 1), '2028-02-29');
    });
  });

  group('compare source (user decision 3)', () {
    test('yesterday, earlier, none', () {
      FootPhotoRef ref(String d) =>
          FootPhotoRef(path: 'p', atMs: 0, localDate: d);
      expect(
        compareSourceOf(ref('2026-10-25'), '2026-10-26').kind,
        CompareKind.yesterday,
      );
      expect(
        compareSourceOf(ref('2026-10-23'), '2026-10-26').kind,
        CompareKind.earlier,
      );
      expect(compareSourceOf(null, '2026-10-26').kind, CompareKind.none);
    });

    test('repository: newest photo of the view before today; today and '
        'other views do not count', () async {
      final rig = StorageRig();
      await rig.footChecks.save(
        draftOf(
          bkk(2026, 10, 22, 19),
          photos: {FootView.soleLeft: 'a/sole_left-0.jpg'},
        ),
      );
      await rig.footChecks.save(
        draftOf(
          bkk(2026, 10, 23, 19),
          photos: {FootView.soleLeft: 'b/sole_left-0.jpg'},
        ),
      );
      // Yesterday's check skipped the sole; today has one.
      await rig.footChecks.save(
        draftOf(
          bkk(2026, 10, 25, 19),
          photos: {FootView.topLeft: 'c/top_left-0.jpg'},
        ),
      );
      await rig.footChecks.save(
        draftOf(
          bkk(2026, 10, 26, 8),
          photos: {FootView.soleLeft: 'd/sole_left-0.jpg'},
        ),
      );
      final sole = await rig.footChecks.latestPhotoBefore(
        FootView.soleLeft,
        '2026-10-26',
      );
      expect(sole!.path, 'b/sole_left-0.jpg');
      expect(sole.localDate, '2026-10-23');
      expect(compareSourceOf(sole, '2026-10-26').kind, CompareKind.earlier);
      final top = await rig.footChecks.latestPhotoBefore(
        FootView.topLeft,
        '2026-10-26',
      );
      expect(compareSourceOf(top, '2026-10-26').kind, CompareKind.yesterday);
      expect(
        await rig.footChecks.latestPhotoBefore(FootView.topRight, '2026-10-26'),
        isNull,
      );
    });
  });

  group('history and the day result (user decision 4)', () {
    test('repeat checks are all kept; the latest is the day result, and '
        'each finding has its own alert', () async {
      final rig = StorageRig();
      final first = await rig.footChecks.save(
        draftOf(bkk(2026, 10, 26, 8), wound: yes),
      );
      final second = await rig.footChecks.save(
        draftOf(bkk(2026, 10, 26, 19), redness: yes),
      );
      final third = await rig.footChecks.save(draftOf(bkk(2026, 10, 26, 20)));
      final all = await rig.footChecks.range('2026-10-26', '2026-10-26');
      expect(all.map((c) => c.id), [first.id, second.id, third.id]);
      expect(latestPerDay(all)['2026-10-26']!.id, third.id);
      expect(
        (await rig.footChecks.watchLatestOn('2026-10-26').first)!.id,
        third.id,
      );
      final alerts = await rig.alerts.watchVisible(bkk(2026, 10, 26, 21)).first;
      expect(alerts.map((a) => a.footCheckId).toSet(), {first.id, second.id});
      expect(findingsOf(second), [FootCheckQuestion.redness]);
      expect(findingsOf(third), isEmpty);
    });

    test('photo history lists only checks with photos, newest first, '
        'grouped by day', () async {
      final rig = StorageRig();
      await rig.footChecks.save(
        draftOf(bkk(2026, 10, 24, 19), photos: {FootView.soleLeft: 'x'}),
      );
      await rig.footChecks.save(draftOf(bkk(2026, 10, 25, 19)));
      await rig.footChecks.save(
        draftOf(bkk(2026, 10, 26, 8), photos: {FootView.topLeft: 'y'}),
      );
      await rig.footChecks.save(
        draftOf(bkk(2026, 10, 26, 19), photos: {FootView.topRight: 'z'}),
      );
      final checks = await rig.footChecks.watchWithPhotos().first;
      final days = groupByDay(checks);
      expect(days.map((d) => d.localDate), ['2026-10-26', '2026-10-24']);
      expect(days.first.checks.map((c) => c.photos.values.single), ['z', 'y']);
      expect(await rig.footChecks.photoPaths(), {'x', 'y', 'z'});
    });

    test('watchRange follows new saves', () async {
      final rig = StorageRig();
      final stream = rig.footChecks.watchRange('2026-10-20', '2026-10-26');
      expect(await stream.first, isEmpty);
      await rig.footChecks.save(draftOf(bkk(2026, 10, 26, 19)));
      expect(await stream.first, hasLength(1));
    });
  });
}
