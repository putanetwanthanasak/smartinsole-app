import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

/// Bottom-bar tab; built in S8C.
class FootCheckScreen extends StatelessWidget {
  const FootCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(title: 'ตรวจเท้าประจำวัน', session: 'S8C');
  }
}
