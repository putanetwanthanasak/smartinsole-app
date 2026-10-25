import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/storage_providers.dart';
import 'package:smartinsole/ui/routes.dart';
import 'package:smartinsole/ui/screens/settings_screen.dart';

import '../helpers/pump_app.dart';

/// Opens Settings with [store] (defaults) and a fixed app version.
Future<MemorySettingsStore> pumpSettings(
  WidgetTester tester, {
  MemorySettingsStore? store,
  int photos = 0,
  Future<int> Function()? deletePhotos,
}) async {
  final s = store ?? MemorySettingsStore();
  await pumpApp(
    tester,
    initialRoute: Routes.settings,
    settings: s,
    overrides: [
      appVersionProvider.overrideWithValue(Future.value('1.0.0+1')),
      footPhotoCountProvider.overrideWith((ref) async => photos),
      if (deletePhotos != null)
        deleteFootPhotosProvider.overrideWithValue(deletePhotos),
    ],
  );
  return s;
}

Future<void> scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(byKey(key), 300);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(byKey(key)).data!;

void main() {
  testWidgets('switches show เปิด / ปิด and persist', (tester) async {
    final store = await pumpSettings(tester);
    await scrollTo(tester, 'settings-sound');
    expect(
      find.descendant(of: byKey('settings-sound'), matching: find.text('เปิด')),
      findsOneWidget,
    );
    await tester.tap(byKey('settings-sound'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: byKey('settings-sound'), matching: find.text('ปิด')),
      findsOneWidget,
    );
    expect(store.settings.sound, isFalse);

    await tester.tap(byKey('settings-reminder'));
    await tester.pumpAndSettle();
    expect(store.settings.footCheckReminder, isFalse);
    // TalkBack hears the state (§13).
    expect(
      tester.getSemantics(byKey('settings-reminder')),
      matchesSemantics(
        label: 'เตือนให้ดูเท้าทุกวัน',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('text size: 22/18 and 26/18 times the phone scale, persisted', (
    tester,
  ) async {
    final store = await pumpSettings(tester);
    double scaleOf18() =>
        MediaQuery.textScalerOf(tester.element(byKey('text-size-preview')))
            .scale(18);
    expect(scaleOf18(), 18);
    await tester.tap(byKey('text-size-large'));
    await tester.pumpAndSettle();
    expect(scaleOf18(), closeTo(22, 0.01));
    expect(store.settings.textSize, TextSizeOption.large);
    await tester.tap(byKey('text-size-extraLarge'));
    await tester.pumpAndSettle();
    expect(scaleOf18(), closeTo(26, 0.01));
    expect(
      tester.getSemantics(find.bySemanticsLabel('ใหญ่มาก')),
      matchesSemantics(
        label: 'ใหญ่มาก',
        isButton: true,
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('the name sheet saves the greeting name', (tester) async {
    final store = await pumpSettings(tester);
    expect(textOf(tester, 'settings-name-value'), 'ยังไม่ได้ตั้งชื่อ');
    await tester.tap(byKey('settings-name'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('name-field'), 'สมชาย');
    await tester.tap(byKey('sheet-confirm'));
    await tester.pumpAndSettle();
    expect(store.settings.name, 'สมชาย');
    expect(textOf(tester, 'settings-name-value'), 'สมชาย');
  });

  testWidgets('cancel leaves the name as it was', (tester) async {
    final store = await pumpSettings(
      tester,
      store: MemorySettingsStore(settings: const AppSettings(name: 'มาลี')),
    );
    await tester.tap(byKey('settings-name'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('name-field'), 'อื่น');
    await tester.tap(byKey('sheet-cancel'));
    await tester.pumpAndSettle();
    expect(store.settings.name, 'มาลี');
  });

  testWidgets('delete photos: count, confirmation sheet, then deleted', (
    tester,
  ) async {
    var deleted = 0;
    await pumpSettings(
      tester,
      photos: 28,
      deletePhotos: () async {
        deleted++;
        return 28;
      },
    );
    await scrollTo(tester, 'settings-delete-photos');
    expect(find.text('ตอนนี้มี 28 รูป'), findsOneWidget);
    await tester.tap(byKey('settings-delete-photos'));
    await tester.pumpAndSettle();
    expect(find.text('ลบแล้วนำรูปกลับมาไม่ได้'), findsOneWidget);
    // Cancel deletes nothing.
    await tester.tap(byKey('sheet-cancel'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await tester.tap(byKey('settings-delete-photos'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('sheet-confirm'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('ลบรูปถ่ายเท้าแล้ว 28 รูป'), findsOneWidget);
  });

  testWidgets('no photos: the delete row opens nothing', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, 'settings-delete-photos');
    expect(find.text('ยังไม่มีรูปถ่ายเท้า'), findsOneWidget);
    await tester.tap(byKey('settings-delete-photos'));
    await tester.pumpAndSettle();
    expect(byKey('sheet-confirm'), findsNothing);
  });

  testWidgets('version is the app version · รุ่นทดสอบงานวิจัย', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, 'settings-version');
    expect(
      textOf(tester, 'settings-version'),
      '1.0.0+1 · ${SettingsCopy.buildLabel}',
    );
  });

  testWidgets('the insole row opens Connection', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, 'settings-connection');
    expect(find.text('ยังไม่ได้เชื่อมต่อ'), findsOneWidget);
    await tester.tap(byKey('settings-connection'));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อทีละข้าง ซ้ายและขวา'), findsOneWidget);
  });

  testWidgets('the reminder time opens the 24-hour platform picker', (
    tester,
  ) async {
    await pumpSettings(tester);
    await scrollTo(tester, 'settings-reminder-time');
    expect(textOf(tester, 'settings-reminder-time-value'), 'ทุกวัน 19:00');
    await tester.tap(byKey('settings-reminder-time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(
      MediaQuery.of(tester.element(find.byType(TimePickerDialog)))
          .alwaysUse24HourFormat,
      isTrue,
    );
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('no debug button for normal users', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, 'researcher-row');
    expect(find.text('BLE debug (temporary)'), findsNothing);
    expect(find.textContaining('debug'), findsNothing);
  });
}
