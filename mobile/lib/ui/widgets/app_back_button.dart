import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Back button with the Thai TalkBack label "กลับ" (DESIGN-SPEC section 8).
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(LucideIcons.chevron_left, size: 28),
      tooltip: 'กลับ',
      onPressed: () => Navigator.maybePop(context),
    );
  }
}
