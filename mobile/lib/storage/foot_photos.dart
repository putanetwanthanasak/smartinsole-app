import 'dart:io';

import 'package:drift/drift.dart';

import 'database.dart';

/// Photo files in the foot-photo folder (Settings › "ตอนนี้มี {n} รูป").
int countFootPhotos(Directory dir) {
  if (!dir.existsSync()) return 0;
  return dir.listSync(recursive: true).whereType<File>().length;
}

/// Settings › "ลบรูปถ่ายเท้าทั้งหมด" (S8B, user decision 8A): the
/// photo columns of every foot check become null (the answers and results
/// stay), then every file in [photoDir] is deleted. Returns how many files
/// went. Never touches capture data or the export folder.
Future<int> deleteAllFootPhotos(
  AppDatabase db, {
  required Future<Directory> Function() photoDir,
}) async {
  await db
      .update(db.footChecks)
      .write(
        const FootChecksCompanion(
          photoSoleLeft: Value(null),
          photoSoleRight: Value(null),
          photoTopLeft: Value(null),
          photoTopRight: Value(null),
        ),
      );
  final dir = await photoDir();
  var n = 0;
  if (dir.existsSync()) {
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      f.deleteSync();
      n++;
    }
  }
  return n;
}
