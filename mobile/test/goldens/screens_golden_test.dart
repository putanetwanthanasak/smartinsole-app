@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/routes.dart';

import '../helpers/pump_app.dart';

/// One golden per screen. Regenerate with:
///   flutter test --update-goldens test/goldens
void main() {
  Future<void> expectScreen(String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
  );

  group('tabs', () {
    for (final (tab, name) in [
      ('home', 'home'),
      ('gait', 'gait'),
      ('temperature', 'temperature'),
      ('alerts', 'alerts'),
    ]) {
      testWidgets(name, (tester) async {
        await pumpApp(tester);
        await tester.tap(byKey('tab-$tab'));
        await tester.pumpAndSettle();
        await expectScreen(name);
      });
    }
  });

  group('pushed screens', () {
    for (final (route, name) in [
      (Routes.connection, 'connection'),
      (Routes.settings, 'settings'),
      (Routes.footCheck, 'foot_check'),
    ]) {
      testWidgets(name, (tester) async {
        await pumpApp(tester, initialRoute: route);
        await expectScreen(name);
      });
    }
  });
}
