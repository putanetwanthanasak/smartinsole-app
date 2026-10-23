import 'package:flutter/material.dart';

import '../widgets/placeholder_body.dart';

/// Bottom-bar tab; built in S6B.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(title: 'แจ้งเตือน', session: 'S6B');
  }
}
