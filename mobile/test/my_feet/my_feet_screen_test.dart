import 'dart:ui' show SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/config/foot_layout.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/rules/alert_code.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/screens/alert_detail_screen.dart';
import 'package:smartinsole/ui/screens/connection_screen.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';
import 'package:smartinsole/ui/theme/colors.dart';
import 'package:smartinsole/ui/widgets/summary_banner.dart';

import '../alerts/alerts_rig.dart' show containerOf;
import '../helpers/pump_app.dart';
import 'my_feet_rig.dart';

Finder _inBanner(Finder f) =>
    find.descendant(of: byKey('my-feet-banner'), matching: f);

void main() {
  group('tabs', () {
    testWidgets('the sub-tabs switch the panel', (tester) async {
      await pumpMyFeet(tester, MockPreset.safe);
      expect(byKey('pressure-tab'), findsOneWidget);
      await openSubTab(tester, MyFeetTab.temperature);
      expect(byKey('temperature-tab'), findsOneWidget);
      expect(byKey('pressure-tab'), findsNothing);
      await openSubTab(tester, MyFeetTab.gait);
      expect(byKey('gait-tab'), findsOneWidget);
      expect(byKey('temperature-tab'), findsNothing);
      await unmount(tester);
    });

    testWidgets('the header says when no foot streams', (tester) async {
      await pumpMyFeet(tester, MockPreset.noData);
      expect(find.text('ยังไม่มีข้อมูล'), findsWidgets);
      expect(find.text('อัปเดตเมื่อสักครู่'), findsNothing);
      // No numbers to open without data.
      expect(byKey('pressure-details'), findsNothing);
      await unmount(tester);
    });

    testWidgets('screen reader: a tab list with the selected tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpMyFeet(tester, MockPreset.safe);
      final bar = tester.getSemantics(find.bySemanticsLabel('เรื่องที่ดู'));
      expect(bar.role, SemanticsRole.tabBar);
      final pressure = tester.getSemantics(
        find
            .descendant(
              of: byKey('my-feet-tab-pressure'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(pressure.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
      await unmount(tester);
    });
  });

  group('pressure', () {
    testWidgets('safe: banner, both maps, top 3 and the numbers', (
      tester,
    ) async {
      await pumpMyFeet(tester, MockPreset.safe);
      expect(_inBanner(find.text('แรงกดกระจายดีทั้งสองข้าง')), findsOneWidget);
      expect(byKey('feet-map-left'), findsOneWidget);
      expect(byKey('feet-map-right'), findsOneWidget);
      expect(find.text('ทั้งสองข้าง'), findsNWidgets(3));
      await openDetails(tester);
      expect(byKey('kpa-table'), findsOneWidget);
      expect(find.textContaining('kPa·s'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('watch: Be careful, its alert copy and the link', (
      tester,
    ) async {
      await pumpMyFeet(tester, MockPreset.watch);
      final banner = tester.widget<SummaryBanner>(find.byType(SummaryBanner));
      expect(banner.level.name, 'careful');
      expect(_inBanner(find.text('ดูสิ่งที่ควรทำ')), findsOneWidget);
      expect(byKey('banner-connect'), findsNothing);
      await unmount(tester);
    });

    testWidgets('one foot missing: the banner names it; connect opens '
        'Connection', (tester) async {
      await pumpMyFeet(tester, MockPreset.oneFootMissing);
      expect(_inBanner(find.text('ยังไม่ได้รับข้อมูลเท้าขวา')), findsOneWidget);
      // The connected foot still shows its zones.
      expect(find.text('เท้าซ้าย'), findsWidgets);
      await tester.tap(byKey('banner-connect'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ConnectionScreen), findsOneWidget);
      await unmount(tester);
    });
  });

  group('temperature', () {
    testWidgets('rest: the link opens the newest TEMP_DELTA alert', (
      tester,
    ) async {
      await pumpMyFeet(
        tester,
        MockPreset.rest,
        tab: MyFeetTab.temperature,
        seedDay: true,
      );
      final banner = tester.widget<SummaryBanner>(find.byType(SummaryBanner));
      expect(banner.level.name, 'rest');
      // The rest preset: heel centre +2.6, lateral heel +2.3 on the right.
      expect(banner.title, 'กลางส้นเท้าขวาอุ่นกว่าซ้าย 2.6 องศา');
      expect(byKey('site-card-lateralHeel'), findsOneWidget);
      final card = byKey('site-card-heel');
      expect(
        find.descendant(of: card, matching: find.text('ขวาอุ่นกว่า')),
        findsOneWidget,
      );
      final newest = containerOf(tester)
          .read(visibleAlertsProvider)
          .value!
          .firstWhere((a) => a.kind.code == AlertCode.tempDelta);
      await tester.tap(byKey('banner-link'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<AlertDetailScreen>(find.byType(AlertDetailScreen))
            .alertId,
        newest.id,
      );
      await unmount(tester);
    });

    testWidgets('one foot missing: no two-foot numbers (rule 4)', (
      tester,
    ) async {
      await pumpMyFeet(
        tester,
        MockPreset.oneFootMissing,
        tab: MyFeetTab.temperature,
        seedDay: true,
      );
      expect(_inBanner(find.text('เทียบความอุ่นไม่ได้')), findsOneWidget);
      // No ΔT anywhere: the interim default sites, MTH1 and heel centre.
      for (final site in ['meta1', 'heel']) {
        expect(
          find.descendant(
            of: byKey('site-card-$site'),
            matching: find.text('—'),
          ),
          findsOneWidget,
        );
      }
      // The banner is the No-data colour, never green (rule 5).
      final banner = tester.widget<SummaryBanner>(find.byType(SummaryBanner));
      expect(banner.level.name, 'noData');
      expect(
        StatusColors.noData.background,
        isNot(StatusColors.safe.background),
      );
      await unmount(tester);
    });

    testWidgets('the chart has a spoken summary', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMyFeet(
        tester,
        MockPreset.safe,
        tab: MyFeetTab.temperature,
        seedDay: true,
      );
      await tester.scrollUntilVisible(
        byKey('temp-chart'),
        200,
        scrollable: find.descendant(
          of: byKey('my-feet-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final names = footLayout.zones.map((z) => z.nameTh).join('|');
      expect(
        find.bySemanticsLabel(
          RegExp('^กราฟความต่างของความอุ่นวันนี้ ($names)'),
        ),
        findsOneWidget,
      );
      handle.dispose();
      await unmount(tester);
    });

    testWidgets('no data today: the chart says so', (tester) async {
      await pumpMyFeet(tester, MockPreset.noData, tab: MyFeetTab.temperature);
      expect(find.text('ยังไม่มีข้อมูลวันนี้'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('motion', () {
    testWidgets('the chart draws in once; 10 Hz updates never restart it; '
        'opening the tab again does', (tester) async {
      await pumpMyFeet(
        tester,
        MockPreset.safe,
        tab: MyFeetTab.temperature,
        seedDay: true,
      );
      expect(chartProgress(tester), 1);
      // A minute of snapshots and two temperature readings.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(chartProgress(tester), 1);
      }
      await tester.tap(byKey('tab-today'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(byKey('tab-myFeet'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(chartProgress(tester), lessThan(1));
      await tester.pump(const Duration(seconds: 1));
      expect(chartProgress(tester), 1);
      await unmount(tester);
    });

    testWidgets('reduce motion: the chart is drawn at once', (tester) async {
      await pumpMyFeet(
        tester,
        MockPreset.safe,
        seedDay: true,
        reduceMotion: true,
      );
      await tester.tap(byKey('my-feet-tab-temperature'));
      await tester.pump();
      expect(chartProgress(tester), 1);
      expect(byKey('pressure-tab'), findsNothing);
      await unmount(tester);
    });
  });
}
