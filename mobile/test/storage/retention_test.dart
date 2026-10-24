import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/retention.dart';

import 'storage_rig.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(bkk(2026, 10, 24, 14, 32));
  final nowMs = now.millisecondsSinceEpoch;
  final cutoff = nowMs - const Duration(days: 30).inMilliseconds;

  late Directory root;
  late Directory photos;

  setUp(() {
    root = Directory.systemTemp.createTempSync('retention_test');
    addTearDown(() {
      Process.runSync('chmod', ['-R', 'u+w', root.path]);
      root.deleteSync(recursive: true);
    });
    photos = Directory('${root.path}/foot_photos')..createSync();
  });

  Retention retentionFor(StorageRig rig) =>
      Retention(rig.db, photoDir: () async => photos, dates: bangkok);

  File photo(String rel) => File('${photos.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsStringSync('jpeg');

  Future<void> temp(StorageRig rig, int atMs) => rig.temperatures.add(
    side: FootSide.left,
    atMs: atMs,
    forefootC: 30,
    heelC: 31,
    quality: TempQuality.normal,
    timeFromArrival: false,
  );

  test('exactly 30 days old is kept; 30 days + 1 ms goes', () async {
    final rig = StorageRig();
    for (final at in [cutoff, cutoff - 1]) {
      await rig.alerts.add(alertOf(AlertKind.tempDelta, at));
      await temp(rig, at);
      await rig.footChecks.save(draftOf(at));
    }
    final r = await retentionFor(rig).run(now);
    expect((r.alerts, r.temperatures, r.footChecks), (1, 1, 1));
    final alerts = await rig.db.select(rig.db.alerts).get();
    expect(alerts.map((a) => a.atMs), [cutoff]);
    final temps = await rig.temperatures.between(0, nowMs);
    expect(temps.map((t) => t.atMs), [cutoff]);
    final checks = await rig.db.select(rig.db.footChecks).get();
    expect(checks.map((c) => c.atMs), [cutoff]);
  });

  test('alerts with a capture stamp are never deleted by age', () async {
    final rig = StorageRig();
    final old = nowMs - const Duration(days: 90).inMilliseconds;
    await rig.alerts.add(
      alertOf(AlertKind.tempDelta, old, captureStamp: '20261110-093000'),
    );
    await rig.alerts.add(alertOf(AlertKind.tempDelta, old));
    await retentionFor(rig).run(now);
    final left = await rig.db.select(rig.db.alerts).get();
    expect(left.map((a) => a.captureStamp), ['20261110-093000']);
    // Only the capture's own delete removes them.
    expect(await rig.alerts.deleteForCapture('20261110-093000'), 1);
  });

  test('summaries go by day: the cutoff\'s day stays', () async {
    final rig = StorageRig();
    // The cutoff is 2026-09-24 14:32 Bangkok.
    for (final d in ['2026-09-22', '2026-09-23', '2026-09-24', '2026-10-24']) {
      await rig.summaries.setActivity(d, nowMs, steps: 1);
    }
    final r = await retentionFor(rig).run(now);
    expect(r.summaries, 2);
    final left = await rig.summaries.range('2000-01-01', '2100-01-01');
    expect(left.map((s) => s.localDate), ['2026-09-24', '2026-10-24']);
  });

  group('foot-check photos', () {
    test('are deleted with their row; a fresh check keeps its own', () async {
      final rig = StorageRig();
      final oldSole = photo('old/sole_left.jpg');
      final oldTop = photo('old/top_right.jpg');
      final fresh = photo('new/sole_left.jpg');
      await rig.footChecks.save(
        draftOf(
          cutoff - 1,
          photos: {
            FootView.soleLeft: 'old/sole_left.jpg',
            FootView.topRight: 'old/top_right.jpg',
            // Already gone from disk: not an error.
            FootView.soleRight: 'old/missing.jpg',
          },
        ),
      );
      await rig.footChecks.save(
        draftOf(cutoff, photos: {FootView.soleLeft: 'new/sole_left.jpg'}),
      );
      final r = await retentionFor(rig).run(now);
      expect(r.footChecks, 1);
      expect(r.photos, 2);
      expect(oldSole.existsSync(), isFalse);
      expect(oldTop.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('a finding\'s alert outlives its deleted check only if it is study '
        'data, and then loses the link', () async {
      final rig = StorageRig();
      final c = await rig.footChecks.save(
        draftOf(cutoff - 1, wound: FootCheckAnswer.yesOrUnsure),
      );
      // Tag the finding as study data so retention keeps it.
      await (rig.db.update(rig.db.alerts))
          .write(const AlertsCompanion(captureStamp: Value('20261110-093000')));
      await retentionFor(rig).run(now);
      expect(await rig.footChecks.byId(c.id), isNull);
      final a = (await rig.db.select(rig.db.alerts).get()).single;
      expect(a.footCheckId, isNull, reason: 'ON DELETE SET NULL');
    });

    test('research files and paths outside the photo folder are never '
        'touched', () async {
      final rig = StorageRig();
      final research = File('${root.path}/research/SI-001_x/trial.csv')
        ..createSync(recursive: true)
        ..writeAsStringSync('data');
      await rig.footChecks.save(
        draftOf(
          cutoff - 1,
          photos: {
            FootView.soleLeft: '../research/SI-001_x/trial.csv',
            FootView.topLeft: '/etc/hostname',
          },
        ),
      );
      final r = await retentionFor(rig).run(now);
      expect(research.existsSync(), isTrue);
      expect(r.photos, 0);
      expect(r.footChecks, 1, reason: 'the row itself still expires');
    });

    test(
      'a photo that will not delete keeps its row for the next run',
      () async {
        final uid = Process.runSync('id', ['-u']).stdout.toString().trim();
        if (uid == '0') return; // root ignores the read-only folder
        final rig = StorageRig();
        final f = photo('locked/sole_left.jpg');
        await rig.footChecks.save(
          draftOf(
            cutoff - 1,
            photos: {FootView.soleLeft: 'locked/sole_left.jpg'},
          ),
        );
        Process.runSync('chmod', ['a-w', '${photos.path}/locked']);
        var r = await retentionFor(rig).run(now);
        expect((r.footChecks, r.photosKept), (0, 1));
        expect(f.existsSync(), isTrue);
        expect(await rig.db.select(rig.db.footChecks).get(), hasLength(1));

        Process.runSync('chmod', ['u+w', '${photos.path}/locked']);
        r = await retentionFor(rig).run(now);
        expect((r.footChecks, r.photos, r.photosKept), (1, 1, 0));
        expect(f.existsSync(), isFalse);
      },
    );
  });

  group('schedule', () {
    test('runs at start, then once a day from the hourly check or resume', () {
      fakeAsync((async) {
        final clock = async.getClock(now);
        final runs = <DateTime>[];
        final schedule = RetentionSchedule(
          _CountingRetention(runs),
          now: clock.now,
        )..start();
        async.flushMicrotasks();
        expect(runs, hasLength(1));

        schedule.maybeRun(); // resume an hour later: too soon
        async.elapse(const Duration(hours: 23));
        expect(runs, hasLength(1));
        async.elapse(const Duration(hours: 1));
        expect(runs, hasLength(2));
        async.elapse(const Duration(hours: 12));
        schedule.maybeRun();
        async.flushMicrotasks();
        expect(runs, hasLength(2));
        schedule.stop();
        async.elapse(const Duration(days: 3));
        expect(runs, hasLength(2));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a resume after a starved timer runs at once', () {
      fakeAsync((async) {
        var at = now;
        final runs = <DateTime>[];
        final schedule = RetentionSchedule(
          _CountingRetention(runs),
          now: () => at,
          checkEvery: const Duration(days: 365), // the timer never fires
        )..start();
        async.flushMicrotasks();
        at = at.add(const Duration(days: 2));
        schedule.maybeRun();
        async.flushMicrotasks();
        expect(runs, [now, at]);
        schedule.stop();
      });
    });

    test('a failed run is retried at the next check', () {
      fakeAsync((async) {
        final clock = async.getClock(now);
        final runs = <DateTime>[];
        final retention = _CountingRetention(runs)..fail = true;
        final schedule = RetentionSchedule(retention, now: clock.now)..start();
        async.flushMicrotasks();
        retention.fail = false;
        async.elapse(const Duration(hours: 1));
        expect(runs, hasLength(2));
        schedule.stop();
      });
    });
  });
}

class _CountingRetention extends Retention {
  _CountingRetention(this.runs)
    : super(_unused, photoDir: () async => Directory.systemTemp);

  static final _unused = AppDatabase.memory();

  final List<DateTime> runs;
  bool fail = false;

  @override
  Future<RetentionResult> run(DateTime now) async {
    runs.add(now);
    if (fail) throw StateError('disk full');
    return const RetentionResult(
      alerts: 0,
      temperatures: 0,
      footChecks: 0,
      summaries: 0,
      photos: 0,
      photosKept: 0,
    );
  }
}
