import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'ui/app.dart';

void main() => runSmartInsole();

/// Starts the app. [overrides] lets the driver entrypoint swap in a fake
/// BLE stack for emulator checks (`test_driver/main_mcp.dart`).
void runSmartInsole({List<Override> overrides = const []}) {
  runApp(ProviderScope(overrides: overrides, child: const SmartInsoleApp()));
}
