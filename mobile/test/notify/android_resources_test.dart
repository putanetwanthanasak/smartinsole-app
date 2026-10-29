import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/notify/android_resources.dart';

/// Resources the notification plugin looks up by name must survive the
/// release build's resource shrinker (S8C: the release APK lost the
/// reminder icon). This checks the source side; the built APK is checked
/// by `tool/check_release_resources.sh`.
void main() {
  const res = 'android/app/src/main/res';

  Set<String> keptResources() {
    final xml = File('$res/raw/keep.xml').readAsStringSync();
    final keep = RegExp(r'tools:keep="([^"]*)"').firstMatch(xml)?.group(1);
    return {
      for (final r in (keep ?? '').split(','))
        if (r.trim().isNotEmpty) r.trim(),
    };
  }

  test('every runtime resource name is kept in keep.xml', () {
    final kept = keptResources();
    for (final n in AndroidResources.drawables) {
      expect(kept, contains('@drawable/$n'));
    }
    for (final n in AndroidResources.raws) {
      expect(kept, contains('@raw/$n'));
    }
  });

  test('every runtime resource name has a resource file', () {
    final names = {
      for (final d in Directory(res).listSync().whereType<Directory>())
        for (final f in d.listSync().whereType<File>())
          '${d.uri.pathSegments[d.uri.pathSegments.length - 2].split('-').first}'
              '/${f.uri.pathSegments.last.split('.').first}',
    };
    for (final n in AndroidResources.drawables) {
      expect(names, contains('drawable/$n'));
    }
    for (final n in AndroidResources.raws) {
      expect(names, contains('raw/$n'));
    }
  });

  test('lib/ passes no literal resource names to the plugin', () {
    // A literal here would bypass AndroidResources and so keep.xml.
    final byName = RegExp(
      r"(AndroidInitializationSettings\(|\bicon:|"
      r"DrawableResourceAndroid\w*\(|RawResourceAndroidNotificationSound\()"
      r"\s*'",
    );
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final m in byName.allMatches(f.readAsStringSync()))
            '${f.path}: ${m.group(0)}',
    ];
    expect(offenders, isEmpty);
  });
}
