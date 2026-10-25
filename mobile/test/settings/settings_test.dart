import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/settings/app_settings.dart';
import 'package:smartinsole/settings/app_text_scaler.dart';
import 'package:smartinsole/settings/settings_providers.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/test_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults: ปกติ, sound and reminder on, 19:00, no name', () async {
    final s = (await PrefsSettingsStore.open()).load();
    expect(s, const AppSettings());
    expect(s.textSize, TextSizeOption.normal);
    expect(s.sound, isTrue);
    expect(s.footCheckReminder, isTrue);
    expect(formatReminderTime(s.reminderTime), '19:00');
    expect(s.greetingName, isNull);
  });

  test('every setting survives a restart (a new store instance)', () async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          await PrefsSettingsStore.open(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final c = container.read(settingsProvider.notifier);
    await c.setName('  สมชาย ');
    await c.setTextSize(TextSizeOption.extraLarge);
    await c.setSound(false);
    await c.setFootCheckReminder(false);
    await c.setReminderTime(const TimeOfDay(hour: 7, minute: 5));
    await container
        .read(settingsStoreProvider)
        .setBoundInsole(FootSide.left, 'AA:BB');

    // A restart: a fresh SharedPreferences read of what was written.
    final reopened = await PrefsSettingsStore.open();
    final s = reopened.load();
    expect(s.greetingName, 'สมชาย');
    expect(s.textSize, TextSizeOption.extraLarge);
    expect(s.sound, isFalse);
    expect(s.footCheckReminder, isFalse);
    expect(formatReminderTime(s.reminderTime), '07:05');
    expect(reopened.boundInsole(FootSide.left), 'AA:BB');
    expect(reopened.boundInsole(FootSide.right), isNull);
  });

  test('a blank name is removed, so Home says just "สวัสดี"', () async {
    final store = await PrefsSettingsStore.open();
    await store.save(const AppSettings(name: 'สมชาย'));
    await store.save(const AppSettings(name: '   '));
    expect(store.load().greetingName, isNull);
  });

  test('unknown stored values fall back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.textSize: 'huge',
      SettingsKeys.reminderMinute: 9999,
    });
    final s = (await PrefsSettingsStore.open()).load();
    expect(s.textSize, TextSizeOption.normal);
    expect(s.reminderTime, AppSettings.defaultReminderTime);
  });

  test('clearing the test data never resets the settings', () async {
    final store = await PrefsSettingsStore.open();
    const saved = AppSettings(
      name: 'สมชาย',
      textSize: TextSizeOption.large,
      sound: false,
      reminderTime: TimeOfDay(hour: 20, minute: 30),
    );
    await store.save(saved);
    await store.setBoundInsole(FootSide.right, 'CC:DD');

    final db = AppDatabase.memory();
    addTearDown(db.close);
    final photos = Directory.systemTemp.createTempSync('foot_photos_');
    addTearDown(() => photos.deleteSync(recursive: true));
    await clearTestData(db, photoDir: () async => photos);

    final after = await PrefsSettingsStore.open();
    expect(after.load(), saved);
    expect(after.boundInsole(FootSide.right), 'CC:DD');
  });

  group('text size factor', () {
    test('22/18 and 26/18, multiplied with the phone scale', () {
      expect(TextSizeOption.large.factor, closeTo(1.2222, 1e-4));
      expect(TextSizeOption.extraLarge.factor, closeTo(1.4444, 1e-4));
      // The Note 10 runs at 1.3: "ใหญ่มาก" gives about 1.88.
      final s = AppTextScaler.combine(
        const TextScaler.linear(1.3),
        TextSizeOption.extraLarge.factor,
      );
      expect(s.scale(18), closeTo(18 * 1.3 * 26 / 18, 1e-9));
      expect(s.scale(1), closeTo(1.8778, 1e-4));
    });

    test('"ปกติ" leaves the phone scaler untouched', () {
      const phone = TextScaler.linear(1.3);
      expect(identical(AppTextScaler.combine(phone, 1.0), phone), isTrue);
    });
  });
}
