import 'package:flutter/material.dart';

import '../routes.dart';
import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
