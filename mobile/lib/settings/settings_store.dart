import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/packets.dart';
import 'app_settings.dart';

/// Where [AppSettings] and each foot's remembered insole live. The app uses
/// [PrefsSettingsStore] (Android `SharedPreferences`, in the app's private
/// `shared_prefs/` folder, not the database), so clearing the test data
/// (`lib/storage/test_data.dart`) never resets them. Tests use
/// [MemorySettingsStore].
abstract interface class SettingsStore {
  AppSettings load();
  Future<void> save(AppSettings settings);

  /// The insole bound to [side] (its BLE device id), remembered so the app
  /// reconnects it at start (user decision 2A, S8B). Null = none.
  String? boundInsole(FootSide side);
  Future<void> setBoundInsole(FootSide side, String? deviceId);
}

/// Preference keys. Never rename one: a renamed key silently resets that
/// setting on the phone.
abstract final class SettingsKeys {
  static const name = 'settings.name';
  static const textSize = 'settings.textSize';
  static const sound = 'settings.sound';
  static const footCheckReminder = 'settings.footCheckReminder';
  static const reminderMinute = 'settings.reminderMinuteOfDay';
  static String boundInsole(FootSide side) => 'insole.bound.${side.name}';
}

class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsSettingsStore> open() async =>
      PrefsSettingsStore(await SharedPreferences.getInstance());

  @override
  AppSettings load() {
    const d = AppSettings();
    final size = _prefs.getString(SettingsKeys.textSize);
    final minute = _prefs.getInt(SettingsKeys.reminderMinute);
    return AppSettings(
      name: _prefs.getString(SettingsKeys.name),
      textSize: TextSizeOption.values.asNameMap()[size] ?? d.textSize,
      sound: _prefs.getBool(SettingsKeys.sound) ?? d.sound,
      footCheckReminder:
          _prefs.getBool(SettingsKeys.footCheckReminder) ?? d.footCheckReminder,
      reminderTime: minute == null || minute < 0 || minute >= 24 * 60
          ? d.reminderTime
          : TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    final name = s.greetingName;
    await Future.wait([
      if (name == null)
        _prefs.remove(SettingsKeys.name)
      else
        _prefs.setString(SettingsKeys.name, name),
      _prefs.setString(SettingsKeys.textSize, s.textSize.name),
      _prefs.setBool(SettingsKeys.sound, s.sound),
      _prefs.setBool(SettingsKeys.footCheckReminder, s.footCheckReminder),
      _prefs.setInt(
        SettingsKeys.reminderMinute,
        s.reminderTime.hour * 60 + s.reminderTime.minute,
      ),
    ]);
  }

  @override
  String? boundInsole(FootSide side) =>
      _prefs.getString(SettingsKeys.boundInsole(side));

  @override
  Future<void> setBoundInsole(FootSide side, String? deviceId) async {
    final key = SettingsKeys.boundInsole(side);
    if (deviceId == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, deviceId);
    }
  }
}

/// In memory only: tests, goldens and the emulator's fake-BLE runs.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({
    this.settings = const AppSettings(),
    Map<FootSide, String>? bound,
  }) : _bound = {...?bound};

  /// What [load] returns; [save] replaces it.
  AppSettings settings;
  final Map<FootSide, String> _bound;

  @override
  AppSettings load() => settings;

  @override
  Future<void> save(AppSettings next) async => settings = next;

  @override
  String? boundInsole(FootSide side) => _bound[side];

  @override
  Future<void> setBoundInsole(FootSide side, String? deviceId) async {
    if (deviceId == null) {
      _bound.remove(side);
    } else {
      _bound[side] = deviceId;
    }
  }
}
