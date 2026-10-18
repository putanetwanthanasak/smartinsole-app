import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

class TemperatureScreen extends StatelessWidget {
  const TemperatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('อุณหภูมิ')),
      body: const PageBody(children: [PlaceholderBody(session: 'S6B')]),
    );
  }
}
