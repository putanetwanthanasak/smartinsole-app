import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../storage/models.dart';
import 'foot_views.dart';

/// The photos of one check in progress, in `foot_photos/<stamp>/`. Paths
/// handed to the repository are relative to the foot-photo folder.
/// [discard] removes them all ("ยกเลิกการตรวจ", or leaving without
/// saving); anything left behind by a crash is removed at the next start
/// by the orphan sweep.
class FootPhotoSession {
  FootPhotoSession({required this.root, required this.stamp});

  /// The foot-photo folder.
  final Directory root;

  /// Folder name for this check, e.g. `20261026-190512`.
  final String stamp;

  final _photos = <FootView, String>{};
  var _n = 0;

  Map<FootView, String> get photos => Map.unmodifiable(_photos);

  bool get isEmpty => _photos.isEmpty;

  File fileOf(String relative) => File(p.join(root.path, relative));

  /// Stores [jpeg] as [view]'s photo, replacing an earlier one. Each shot
  /// gets a new name so a cached thumbnail never shows the old photo.
  Future<String> put(FootView view, Uint8List jpeg) async {
    final rel = p.join(stamp, '${view.fileStem}-${_n++}.jpg');
    final file = fileOf(rel);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpeg, flush: true);
    final old = _photos[view];
    _photos[view] = rel;
    if (old != null) await _delete(old);
    return rel;
  }

  Future<void> discard() async {
    _photos.clear();
    final dir = Directory(p.join(root.path, stamp));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _delete(String rel) async {
    final f = fileOf(rel);
    if (await f.exists()) await f.delete();
  }
}

/// `20261026-190512` for a local time.
String photoStampOf(DateTime local) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}
