import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'settings_store.dart';

/// The settings store. `runSmartInsole` overrides it with the phone's
/// [PrefsSettingsStore]; anywhere else (tests, goldens) it is in memory.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => MemorySettingsStore(),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Every change is saved at once; a save that fails leaves the change in
/// memory for this run (the next start reads the last saved value).
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).load();

  Future<void> _update(AppSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(settingsStoreProvider).save(next);
  }

  Future<void> setName(String? name) => _update(
    state.copyWith(
      name: () {
        final n = name?.trim();
        return n == null || n.isEmpty ? null : n;
      },
    ),
  );

  Future<void> setTextSize(TextSizeOption v) =>
      _update(state.copyWith(textSize: v));

  Future<void> setSound(bool v) => _update(state.copyWith(sound: v));

  Future<void> setFootCheckReminder(bool v) =>
      _update(state.copyWith(footCheckReminder: v));

  Future<void> setReminderTime(TimeOfDay v) =>
      _update(state.copyWith(reminderTime: v));
}
