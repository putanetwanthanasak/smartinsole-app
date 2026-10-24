import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_providers.dart';

/// Keeps storage's background work alive for the whole app, whatever
/// screen is open: the temperature recorder and the retention schedule,
/// which also gets a chance to run each time the app comes back to the
/// foreground. Draws nothing.
class StorageHost extends ConsumerStatefulWidget {
  const StorageHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StorageHost> createState() => _StorageHostState();
}

class _StorageHostState extends ConsumerState<StorageHost> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(retentionScheduleProvider).maybeRun(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(temperatureRecorderProvider);
    ref.watch(retentionScheduleProvider);
    return widget.child;
  }
}
