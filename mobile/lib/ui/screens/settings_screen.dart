import 'package:flutter/material.dart';

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
      body: const PageBody(children: [PlaceholderBody(session: 'S8B')]),
    );
  }
}
