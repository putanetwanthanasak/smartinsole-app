import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Neutral "not built yet" card for screens that later sessions fill in.
/// Deliberately not styled like any patient status (rule 5).
class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({super.key, required this.session});

  /// The session that builds this screen, e.g. "S8A". English, for developers.
  final String session;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ยังไม่พร้อมใช้งาน', style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text(
              'Placeholder — built in $session',
              style: AppText.small.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page body with the standard padding, scrollable.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Dimens.pagePadding),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Dimens.cardGap),
          children[i],
        ],
      ],
    );
  }
}
