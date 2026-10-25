import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'config/thresholds.dart';
import 'gait/model_spec.dart';
import 'ui/app.dart';

void main() => runSmartInsole();

/// Starts the app. [overrides] lets the driver entrypoint swap in a fake
/// BLE stack for emulator checks (`test_driver/main_mcp.dart`).
Future<void> runSmartInsole({List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled with the app; a missing or malformed file is a build error,
  // so let it throw rather than run with no thresholds (rule 12).
  final thresholds = await Thresholds.load();
  final modelInput = await ModelInputSpec.load();
  runApp(
    ProviderScope(
      overrides: [
        thresholdsProvider.overrideWithValue(thresholds),
        modelInputSpecProvider.overrideWithValue(modelInput),
        ...overrides,
      ],
      child: const SmartInsoleApp(),
    ),
  );
}
