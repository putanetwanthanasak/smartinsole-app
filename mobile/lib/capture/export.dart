import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/alert_repository.dart';
import '../storage/models.dart';
import 'alerts_csv.dart';
import 'capture_files.dart';
import 'capture_session.dart';

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
///
/// [extra] are files made for the export only (name → text), such as
/// `alerts.csv` (BACKLOG 40): written next to the copies and listed and
/// hashed in the manifest the same way.
List<ManifestEntry> stageExport(
  Directory sessionDir,
  Directory exportRoot, {
  Map<String, String> extra = const {},
}) {
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
  final sources = <String, List<int> Function()>{
    for (final f in files) f.uri.pathSegments.last: f.readAsBytesSync,
    for (final e in extra.entries) e.key: () => utf8.encode(e.value),
  };
  final names = sources.keys.toList()..sort();
  final entries = <ManifestEntry>[];
  for (final name in names) {
    final bytes = sources[name]!();
    final hash = sha256.convert(bytes).toString();
    // A new file, not copySync: a copy keeps the private original's mode
    // (0600), which the adb shell can't read; a new file in the external
    // folder gets 0660 for group ext_data_rw, which adb can (checked on
    // the emulator, API 37).
    final copy = File('${dest.path}/$name')
      ..writeAsBytesSync(bytes, flush: true);
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

/// Stages [session]'s export with `alerts.csv`: the alerts raised while
/// its session screen was open (BACKLOG 40). Records the export in
/// `session.json` first, so the copy carries it. Returns the manifest
/// entries and how many alerts went in.
Future<(List<ManifestEntry>, int)> exportSession(
  CaptureSession session,
  Directory exportRoot,
  AlertRepository alerts,
) async {
  final rows = await alerts.forCapture(captureStampOf(session.sessionId));
  session.noteExport();
  final entries = stageExport(
    session.dir,
    exportRoot,
    extra: {alertsCsvName: alertsCsv(rows)},
  );
  return (entries, rows.length);
}

/// "Delete from phone": the session's files and its alerts (BACKLOG 40).
/// The caller has confirmed twice and the export has been checked.
Future<void> deleteSession(
  CaptureSession session,
  AlertRepository alerts,
) async {
  session.dir.deleteSync(recursive: true);
  await alerts.deleteForCapture(captureStampOf(session.sessionId));
}
