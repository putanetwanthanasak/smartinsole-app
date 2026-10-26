import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Deletes files in the foot-photo folder that no saved check refers to
/// ([keep], relative paths), then empty folders. These are photos of a
/// check that was never saved (the app closed mid-check). Runs once at
/// app start, before any check can be in progress. Touches nothing outside
/// [dir]. Returns how many files went.
Future<int> sweepOrphanFootPhotos(Directory dir, Set<String> keep) async {
  if (!await dir.exists()) return 0;
  final kept = {for (final k in keep) p.normalize(k)};
  var n = 0;
  final entities = await dir.list(recursive: true).toList();
  for (final f in entities.whereType<File>()) {
    final rel = p.normalize(p.relative(f.path, from: dir.path));
    if (kept.contains(rel)) continue;
    try {
      await f.delete();
      n++;
    } on FileSystemException catch (e) {
      debugPrint('foot photo sweep: could not delete ${f.path}: $e');
    }
  }
  // Deepest first, so a parent is empty once its children have gone.
  final dirs = entities.whereType<Directory>().toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final d in dirs) {
    if (await d.list().isEmpty) await d.delete();
  }
  return n;
}

/// Deletes camera temp files the plugin left in the app cache ([cache]:
/// `CAP….jpg`, written by `takePicture`), e.g. when the app closed between
/// a shot and its processing. Only top-level files with that name.
Future<int> sweepCameraTempFiles(Directory cache) async {
  if (!await cache.exists()) return 0;
  final name = RegExp(r'^CAP.*\.jpg$');
  var n = 0;
  await for (final f in cache.list()) {
    if (f is File && name.hasMatch(p.basename(f.path))) {
      try {
        await f.delete();
        n++;
      } on FileSystemException catch (e) {
        debugPrint('camera temp sweep: could not delete ${f.path}: $e');
      }
    }
  }
  return n;
}
