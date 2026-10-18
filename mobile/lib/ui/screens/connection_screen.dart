import 'package:flutter/material.dart';

import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('เชื่อมต่อแผ่นรองเท้า'),
      ),
      body: const PageBody(children: [PlaceholderBody(session: 'S8B')]),
    );
  }
}
