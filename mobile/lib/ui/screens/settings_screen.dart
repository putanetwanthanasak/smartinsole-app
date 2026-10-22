import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/device_providers.dart';
import '../../device/mock_data_source.dart';
import '../routes.dart';
import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only in a debug run started with --dart-define=MOCK=<preset>.
    final mock = ref.watch(mockInsolesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: const Text('ตั้งค่า'),
      ),
      body: PageBody(
        children: [
          const PlaceholderBody(session: 'S8B'),
          // Temporary developer entry (S3A); removed with the debug screen
          // in S8B.
          OutlinedButton(
            key: const ValueKey('ble-debug-button'),
            onPressed: () => Navigator.pushNamed(context, Routes.bleDebug),
            child: const Text('BLE debug (temporary)'),
          ),
          if (mock != null) _MockPresetButton(mock: mock),
        ],
      ),
    );
  }
}

/// Debug builds with the mock only: switches the mock preset live, so
/// every Home state can be shown on the emulator without relaunching.
class _MockPresetButton extends StatelessWidget {
  const _MockPresetButton({required this.mock});

  final MockInsoles mock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mock,
      builder: (context, _) => OutlinedButton(
        key: const ValueKey('mock-preset-button'),
        onPressed: () => _pick(context),
        child: Text('Mock preset (debug): ${mock.preset.name}'),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<MockPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in MockPreset.values)
              ListTile(
                key: ValueKey('mock-preset-${p.name}'),
                title: Text(p.name),
                trailing: p == mock.preset
                    ? const Icon(LucideIcons.check)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) mock.preset = picked;
  }
}
