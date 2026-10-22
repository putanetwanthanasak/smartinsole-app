import 'dart:io';

import 'package:crypto/crypto.dart';

import 'capture_files.dart';

/// One file in an export manifest.
class ManifestEntry {
  const ManifestEntry(this.name, this.size, this.sha256);
  final String name;
  final int size;
  final String sha256;

  Map<String, Object> toJson() => {
    'name': name,
    'size': size,
    'sha256': sha256,
  };
}

String sha256Of(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Copies a session's files to [exportRoot]`/<sessionId>/` with a
/// `manifest.json` (size + SHA-256 per file), for `adb pull` by
/// `tools/capture/export_capture.py`.
///
/// [exportRoot] is the app-specific external directory
/// (`/sdcard/Android/data/<app id>/files/export`): readable over adb on a
/// release build, which `run-as` is not, and not readable by other apps on
/// Android 11+. The private originals are never touched here; deleting
/// them is a separate, confirmed action after the export is checked.
///
/// Each copy is hashed again after writing and compared with the
/// original's hash, so a bad copy fails here rather than at the laptop.
List<ManifestEntry> stageExport(Directory sessionDir, Directory exportRoot) {
  final id = sessionDir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
  final dest = Directory('${exportRoot.path}/$id');
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  dest.createSync(recursive: true);
  final files =
      sessionDir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final entries = <ManifestEntry>[];
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final hash = sha256Of(f);
    final copy = f.copySync('${dest.path}/$name');
    final copyHash = sha256Of(copy);
    if (copyHash != hash) {
      throw FileSystemException('copy does not match original', copy.path);
    }
    entries.add(ManifestEntry(name, copy.lengthSync(), hash));
  }
  writeJsonAtomic(File('${dest.path}/manifest.json'), {
    'schema': captureSchema,
    'kind': 'manifest',
    'sessionId': id,
    'files': [for (final e in entries) e.toJson()],
  });
  return entries;
}
