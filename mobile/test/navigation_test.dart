import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ui/screens/alerts_screen.dart';
import 'package:smartinsole/ui/screens/connection_screen.dart';
import 'package:smartinsole/ui/screens/foot_check_screen.dart';
import 'package:smartinsole/ui/screens/home_screen.dart';
import 'package:smartinsole/ui/screens/my_feet_screen.dart';
import 'package:smartinsole/ui/screens/settings_screen.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('every tab opens its screen', (tester) async {
    await pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    for (final (key, screen) in [
      ('tab-myFeet', MyFeetScreen),
      ('tab-footCheck', FootCheckScreen),
      ('tab-alerts', AlertsScreen),
      ('tab-today', HomeScreen),
    ]) {
      await tester.tap(byKey(key));
      await tester.pumpAndSettle();
      // IndexedStack keeps every tab alive; only the selected one is visible.
      expect(find.byType(screen), findsOneWidget, reason: key);
      expect(
        find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(screen),
            )
            .hitTestable(),
        findsWidgets,
        reason: '$key visible',
      );
    }
  });

  testWidgets('the bar has the four style D tabs', (tester) async {
    await pumpApp(tester);
    for (final label in ['วันนี้', 'เท้าของฉัน', 'ตรวจเท้า', 'แจ้งเตือน']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
  });

  for (final (key, tab, screen) in [
    ('foot-check-card', AppTab.footCheck, FootCheckScreen),
    ('see-more', AppTab.myFeet, MyFeetScreen),
  ]) {
    testWidgets('$key switches to the $tab tab', (tester) async {
      await pumpApp(tester);
      await tester.scrollUntilVisible(byKey(key), 200);
      await tester.tap(byKey(key));
      await tester.pumpAndSettle();
      expect(
        find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(screen),
            )
            .hitTestable(),
        findsWidgets,
      );
    });
  }

  for (final (key, screen, title) in [
    ('settings-button', SettingsScreen, 'ตั้งค่า'),
    ('foot-left', ConnectionScreen, 'เชื่อมต่อแผ่นรองเท้า'),
    ('foot-right', ConnectionScreen, 'เชื่อมต่อแผ่นรองเท้า'),
    ('connect-button', ConnectionScreen, 'เชื่อมต่อแผ่นรองเท้า'),
  ]) {
    testWidgets('$key opens $screen and back returns Home', (tester) async {
      await pumpApp(tester);
      await tester.tap(byKey(key));
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(screen), matching: find.text(title)),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('กลับ'));
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  for (final reduceMotion in [false, true]) {
    testWidgets('page transition ${reduceMotion ? 'skipped' : 'shown'} '
        'when reduce motion is ${reduceMotion ? 'on' : 'off'}', (tester) async {
      await pumpApp(tester, reduceMotion: reduceMotion);
      await tester.tap(byKey('settings-button'));
      await tester.pump(); // Route pushed; page still offstage.
      await tester.pump(const Duration(milliseconds: 50)); // Mid-transition.
      expect(
        find.ancestor(
          of: find.byType(SettingsScreen),
          matching: find.byType(SharedAxisTransition),
        ),
        reduceMotion ? findsNothing : findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  }
}
