import 'package:flutter/material.dart';

import '../widgets/app_back_button.dart';
import '../widgets/placeholder_body.dart';

class FootCheckScreen extends StatelessWidget {
  const FootCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: const Text('ตรวจเท้าประจำวัน'),
      ),
      body: const PageBody(children: [PlaceholderBody(session: 'S8C')]),
    );
  }
}
