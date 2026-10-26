import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smartinsole/footcheck/orphan_sweep.dart';
import 'package:smartinsole/footcheck/photo_session.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/storage_providers.dart';

void main() {
  late Directory tmp;
  late Directory root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('footcheck');
    root = Directory(p.join(tmp.path, 'foot_photos'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  test('photos go into foot_photos/<stamp>/, relative paths', () async {
    final s = FootPhotoSession(root: root, stamp: '20261026-190512');
    final rel = await s.put(FootView.soleLeft, jpeg);
    expect(p.split(rel).first, '20261026-190512');
    expect(File(p.join(root.path, rel)).existsSync(), isTrue);
    expect(s.photos, {FootView.soleLeft: rel});
  });

  test('a retake replaces the file under a new name', () async {
    final s = FootPhotoSession(root: root, stamp: 's');
    final first = await s.put(FootView.topRight, jpeg);
    final second = await s.put(FootView.topRight, jpeg);
    expect(second, isNot(first));
    expect(File(p.join(root.path, first)).existsSync(), isFalse);
    expect(File(p.join(root.path, second)).existsSync(), isTrue);
  });

  test('discard removes the check folder and nothing else', () async {
    final keep = File(p.join(root.path, 'other', 'sole_left-0.jpg'))
      ..createSync(recursive: true);
    final s = FootPhotoSession(root: root, stamp: 's');
    await s.put(FootView.soleLeft, jpeg);
    await s.put(FootView.soleRight, jpeg);
    await s.discard();
    expect(Directory(p.join(root.path, 's')).existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(s.isEmpty, isTrue);
  });

  test('photoStampOf is local yyyyMMdd-HHmmss', () {
    expect(photoStampOf(DateTime(2026, 10, 6, 7, 5, 9)), '20261006-070509');
  });

  test('the sweep keeps referenced photos and removes the rest', () async {
    final a = File(p.join(root.path, 'a', 'sole_left-0.jpg'))
      ..createSync(recursive: true);
    final b = File(p.join(root.path, 'b', 'top_left-0.jpg'))
      ..createSync(recursive: true);
    final c = File(p.join(root.path, 'a', 'top_left-1.jpg'))
      ..createSync(recursive: true);
    final outside = File(p.join(tmp.path, 'capture.csv'))..createSync();
    final n = await sweepOrphanFootPhotos(root, {
      p.join('a', 'sole_left-0.jpg'),
    });
    expect(n, 2);
    expect(a.existsSync(), isTrue);
    expect(b.existsSync() || c.existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'b')).existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
  });

  test('the sweep does nothing without a folder', () async {
    expect(await sweepOrphanFootPhotos(root, {}), 0);
  });

  test('camera temp sweep removes only CAP*.jpg at the top level', () async {
    final cache = Directory(p.join(tmp.path, 'cache'))..createSync();
    final cap = File(p.join(cache.path, 'CAP123.jpg'))..createSync();
    final other = File(p.join(cache.path, 'other.jpg'))..createSync();
    final nested = File(p.join(cache.path, 'x', 'CAP9.jpg'))
      ..createSync(recursive: true);
    expect(await sweepCameraTempFiles(cache), 1);
    expect(cap.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    expect(nested.existsSync(), isTrue);
  });

  test('an in-memory database never uses the real photo folder', () async {
    // Its start-up sweep sees no saved checks: pointed at the real folder,
    // a mock or driver run would delete every photo on the phone.
    expect(
      footPhotoPath(inMemory: false, support: '/s', cache: '/c'),
      '/s/foot_photos',
    );
    expect(
      footPhotoPath(inMemory: true, support: '/s', cache: '/c'),
      '/c/foot_photos_memory',
    );
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(db.inMemory, isTrue);
  });
}
