import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Status card of a pushed result screen (DESIGN-SPEC §7.3 item 2; the
/// foot-check result cards reuse it): status background, radius 20,
/// padding 24, gap 8. A row of the 56 white circle with the 32 px icon and
/// [levelWord] (16/700) over [time] (16), then [title] (28/700) and
/// [detail] (18), all in the status text colour.
class DetailStatusCard extends StatelessWidget {
  const DetailStatusCard({
    super.key,
    required this.palette,
    required this.icon,
    required this.levelWord,
    required this.title,
    required this.detail,
    this.time,
  });

  final StatusPalette palette;
  final IconData icon;
  final String levelWord;
  final String? time;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = palette.text;
    return Container(
      key: const ValueKey('detail-status-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(Dimens.cardPadding),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusStatusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Container(
                  width: Dimens.statusIconCircle,
                  height: Dimens.statusIconCircle,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: Dimens.statusIcon,
                    color: palette.icon,
                  ),
                ),
                const SizedBox(width: Dimens.buttonGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        levelWord,
                        style: AppText.label.copyWith(
                          color: text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (time != null)
                        Text(
                          time!,
                          style: AppText.secondary.copyWith(color: text),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Dimens.tightGap),
          Semantics(
            header: true,
            child: Text(title, style: AppText.pageTitle.copyWith(color: text)),
          ),
          const SizedBox(height: Dimens.tightGap),
          Text(detail, style: AppText.body.copyWith(color: text)),
        ],
      ),
    );
  }
}
