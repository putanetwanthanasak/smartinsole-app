import 'package:flutter/material.dart';

import '../theme/dimens.dart';
import '../widgets/back_link.dart';
import '../widgets/placeholder_body.dart';

/// Foot check › Something found (DESIGN-SPEC §11.4), opened from a
/// foot-check finding on the Alerts list with the check's id. Built in
/// S8C; until then a placeholder that already receives its target. The
/// real screen has no back link (it leaves through its two buttons); this
/// placeholder keeps one so it can be left.
class FootCheckFoundScreen extends StatelessWidget {
  const FootCheckFoundScreen({super.key, required this.footCheckId});

  final int? footCheckId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pageTopPushed,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            const BackLink(),
            const SizedBox(height: Dimens.sectionGap),
            PlaceholderBody(
              key: ValueKey('foot-check-found-$footCheckId'),
              session: 'S8C · foot check $footCheckId',
            ),
          ],
        ),
      ),
    );
  }
}
