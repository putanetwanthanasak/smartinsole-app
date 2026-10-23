import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'page_title.dart';

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
            const Text('กำลังพัฒนา', style: AppText.cardTitle),
            const SizedBox(height: Dimens.tightGap),
            Text(
              'Placeholder — built in $session',
              style: AppText.secondary.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bottom-bar tab that a later session builds: page title in the body
/// (not the AppBar, so it scales with large text) + "กำลังพัฒนา".
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.title, required this.session});

  final String title;
  final String session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageBody(
          gap: Dimens.sectionGap,
          children: [
            PageTitle(title),
            PlaceholderBody(session: session),
          ],
        ),
      ),
    );
  }
}

/// Page body with the standard padding, scrollable.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.gap = Dimens.cardGap,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.pagePadding,
        Dimens.pagePadding,
        Dimens.pagePadding,
        Dimens.pageBottom,
      ),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}
