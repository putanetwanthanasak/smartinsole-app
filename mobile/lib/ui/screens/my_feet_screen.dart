import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

/// Bottom-bar tab; built in S6B/S8A.
class MyFeetScreen extends StatelessWidget {
  const MyFeetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(title: 'เท้าของฉัน', session: 'S6B/S8A');
  }
}
