import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_providers.dart';

/// Reconnects the insoles remembered from last time, once, when the app
/// starts (user decision 2A, S8B). Each attempt and its outcome is logged
/// for Diagnostics (`FootFinder.reconnects`). Draws nothing.
class AutoConnectHost extends ConsumerStatefulWidget {
  const AutoConnectHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoConnectHost> createState() => _AutoConnectHostState();
}

class _AutoConnectHostState extends ConsumerState<AutoConnectHost> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(autoConnectProvider)());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
