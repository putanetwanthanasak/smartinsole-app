import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_photos.dart';
import 'package:smartinsole/storage/models.dart';

void main() {
  late Directory root;
  late Directory photos;
  late Directory capture;
  late AppDatabase db;

  setUp(() {
    root = Directory.systemTemp.createTempSync('foot_photos_test');
    photos = Directory('${root.path}/foot_photos')..createSync();
    capture = Directory('${root.path}/research/S01')
      ..createSync(recursive: true);
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('delete photos: the folder empties, the photo columns become null, '
      'the answers stay, capture data is untouched', () async {
    for (final name in ['a/sole_left.jpg', 'a/top_right.jpg', 'b.jpg']) {
      File('${photos.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    final kept = File('${capture.path}/trial.csv')..writeAsStringSync('t');
    await db
        .into(db.footChecks)
        .insert(
          FootChecksCompanion.insert(
            atMs: 1,
            localDate: '2026-10-25',
            result: FootCheckResult.found,
            qWound: const Value(FootCheckAnswer.yesOrUnsure),
            photoSoleLeft: const Value('a/sole_left.jpg'),
            photoTopRight: const Value('a/top_right.jpg'),
            answerOnly: false,
          ),
        );
    expect(countFootPhotos(photos), 3);

    final n = await deleteAllFootPhotos(db, photoDir: () async => photos);

    expect(n, 3);
    expect(countFootPhotos(photos), 0);
    expect(kept.existsSync(), isTrue);
    final row = await db.select(db.footChecks).getSingle();
    expect(row.photoSoleLeft, isNull);
    expect(row.photoTopRight, isNull);
    expect(row.qWound, FootCheckAnswer.yesOrUnsure);
    expect(row.result, FootCheckResult.found);
  });

  test('no folder yet: nothing to count or delete', () async {
    photos.deleteSync(recursive: true);
    expect(countFootPhotos(photos), 0);
    expect(await deleteAllFootPhotos(db, photoDir: () async => photos), 0);
  });
}
