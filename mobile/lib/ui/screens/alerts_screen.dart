import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แจ้งเตือน')),
      body: const PageBody(children: [PlaceholderBody(session: 'S6B')]),
    );
  }
}
