import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../footcheck/footcheck_providers.dart';
import '../footcheck/orphan_sweep.dart';
import '../notify/reminder_providers.dart';
import '../settings/settings_providers.dart';
import '../storage/storage_providers.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

/// Daily foot check background work (S8C), for the whole app. Draws
/// nothing.
/// - At start: deletes foot photos no saved check refers to and camera
///   temp files (a check left unsaved when the app closed), before any
///   check can be in progress.
/// - Starts the evening reminder; a tapped reminder opens "ตรวจเท้า".
/// - On resume: re-reads today's date and whether notifications are
///   allowed, and reschedules.
/// - The first time "ตรวจเท้า" opens, asks for the Android 13+
///   notification permission once (user decision 3).
class FootCheckHost extends ConsumerStatefulWidget {
  const FootCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FootCheckHost> createState() => _FootCheckHostState();
}

class _FootCheckHostState extends ConsumerState<FootCheckHost> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    unawaited(_sweep());
    unawaited(
      ref.read(reminderServiceProvider).start(openTab: _openFootCheckTab),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _sweep() async {
    try {
      final photos = await sweepOrphanFootPhotos(
        await ref.read(footPhotoDirProvider)(),
        await ref.read(footCheckRepositoryProvider).photoPaths(),
      );
      final temps = await sweepCameraTempFiles(
        await ref.read(cameraCacheDirProvider)(),
      );
      if (photos + temps > 0) {
        debugPrint('foot photos: removed $photos unsaved, $temps camera temp');
      }
    } catch (e) {
      debugPrint('foot photo sweep failed: $e');
    }
  }

  void _onResume() {
    ref.read(todayProvider.notifier).refresh();
    unawaited(ref.read(notificationsAllowedProvider.notifier).refresh());
    unawaited(ref.read(reminderServiceProvider).sync());
  }

  void _openFootCheckTab() {
    ref.read(selectedTabProvider.notifier).select(AppTab.footCheck);
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  Future<void> _askOnce() async {
    final store = ref.read(settingsStoreProvider);
    if (store.notificationPromptShown) return;
    if (!ref.read(settingsProvider).footCheckReminder) return;
    final allowed = ref.read(notificationsAllowedProvider.notifier);
    if (await ref.read(reminderNotifierProvider).enabled()) return;
    await store.setNotificationPromptShown();
    await allowed.request();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderServiceProvider);
    ref.listen(selectedTabProvider, (_, tab) {
      if (tab == AppTab.footCheck) unawaited(_askOnce());
    });
    return widget.child;
  }
}
