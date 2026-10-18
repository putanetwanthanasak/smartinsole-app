import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

class GaitScreen extends StatelessWidget {
  const GaitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การเดิน')),
      body: const PageBody(children: [PlaceholderBody(session: 'S8A')]),
    );
  }
}
