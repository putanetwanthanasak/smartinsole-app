import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/app_shell.dart';
import '../theme/dimens.dart';
import '../widgets/page_title.dart';
import '../widgets/placeholder_body.dart';

/// Bottom-bar tab; built in S6B part 2 (shell, pressure, temperature) and
/// S8A (gait). It already follows the sub-tab that Home and the alert
/// details ask for ([myFeetTabProvider]).
class MyFeetScreen extends ConsumerWidget {
  const MyFeetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(myFeetTabProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageBody(
          gap: Dimens.sectionGap,
          children: [
            const PageTitle('เท้าของฉัน'),
            PlaceholderBody(
              key: ValueKey('my-feet-target-${tab.name}'),
              session: 'S6B part 2 / S8A · tab: ${tab.name}',
            ),
          ],
        ),
      ),
    );
  }
}
