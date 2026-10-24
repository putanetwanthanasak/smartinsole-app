import 'package:flutter/material.dart';

import '../theme/typography.dart';

/// Page title (DESIGN-SPEC §5): 28/700 heading font in the page body, with
/// an optional 16 `inkMuted` line under it. A screen-reader header.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: AppText.pageTitle)),
        if (subtitle != null) Text(subtitle!, style: AppText.secondary),
      ],
    );
  }
}
