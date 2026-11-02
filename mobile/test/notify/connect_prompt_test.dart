import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/capture/capture_providers.dart';
import 'package:smartinsole/device/device_providers.dart';
import 'package:smartinsole/device/mock_data_source.dart';
import 'package:smartinsole/settings/settings_store.dart';
import 'package:smartinsole/ui/shell/app_shell.dart';

import '../connection/connection_rig.dart' show pumpFor;
import '../helpers/fake_reminder_notifier.dart';
import '../helpers/pump_app.dart';

/// BACKLOG 73 (user decision 2026-11-02): the notification permission is
/// asked once, the first time both insoles stream, never during a
/// research capture; the "ตรวจเท้า" and reminder asks stay.
void main() {
  Future<ProviderContainer> pumpWith(
    WidgetTester tester, {
    required FakeReminderNotifier reminders,
    required MemorySettingsStore settings,
    MockPreset preset = MockPreset.safe,
    bool captureOpen = false,
  }) async {
    await pumpApp(
      tester,
      now: fakeTimeClock(tester),
      settle: false,
      reminders: reminders,
      settings: settings,
      overrides: [mockPresetProvider.overrideWithValue(preset)],
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    if (captureOpen) {
      c.read(activeCaptureProvider.notifier).open('S01_20261110_0930');
    }
    await pumpFor(tester, const Duration(seconds: 2));
    return c;
  }

  testWidgets('both insoles stream, notifications off: asked once and '
      'remembered', (tester) async {
    final reminders = FakeReminderNotifier(allowed: false);
    final settings = MemorySettingsStore();
    await pumpWith(tester, reminders: reminders, settings: settings);
    expect(reminders.requests, 1);
    expect(settings.connectPromptShown, isTrue);
    expect(reminders.settingsOpened, 0, reason: 'never opens settings');
    await pumpFor(tester, const Duration(seconds: 3));
    expect(reminders.requests, 1, reason: 'not again while streaming');
  });

  testWidgets('already asked on an earlier run: not asked again', (
    tester,
  ) async {
    final reminders = FakeReminderNotifier(allowed: false);
    await pumpWith(
      tester,
      reminders: reminders,
      settings: MemorySettingsStore(connectPromptShown: true),
    );
    expect(reminders.requests, 0);
  });

  testWidgets('notifications already show: not asked, not remembered', (
    tester,
  ) async {
    final reminders = FakeReminderNotifier();
    final settings = MemorySettingsStore();
    await pumpWith(tester, reminders: reminders, settings: settings);
    expect(reminders.requests, 0);
    expect(settings.connectPromptShown, isFalse);
  });

  testWidgets('no insole streaming: not asked', (tester) async {
    final reminders = FakeReminderNotifier(allowed: false);
    await pumpWith(
      tester,
      reminders: reminders,
      settings: MemorySettingsStore(),
      preset: MockPreset.noData,
    );
    expect(reminders.requests, 0);
  });

  testWidgets('never during a research capture; asked once it is closed', (
    tester,
  ) async {
    final reminders = FakeReminderNotifier(allowed: false);
    final settings = MemorySettingsStore();
    final c = await pumpWith(
      tester,
      reminders: reminders,
      settings: settings,
      captureOpen: true,
    );
    expect(reminders.requests, 0);
    expect(settings.connectPromptShown, isFalse);
    c.read(activeCaptureProvider.notifier).close('S01_20261110_0930');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(reminders.requests, 1);
    expect(settings.connectPromptShown, isTrue);
  });
}
