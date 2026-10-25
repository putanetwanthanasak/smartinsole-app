import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Info box (DESIGN-SPEC §5): white, `divider` border, radius 16, padding
/// 16, gap 12; a 24 px `info` icon (or `lightbulb` for tips) in `primary`;
/// text 16 `ink`.
class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.text, this.icon = LucideIcons.info});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.smallCardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: Dimens.iconButtonIcon, color: AppColors.primary),
            const SizedBox(width: Dimens.buttonGap),
            Expanded(
              child: Text(
                text,
                style: AppText.secondary.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warning box (DESIGN-SPEC §5): Be-careful background, radius 12–16,
/// padding 16; `triangle-alert` in the Be-careful icon colour; text 16 in
/// the Be-careful text colour.
class WarningBox extends StatelessWidget {
  const WarningBox({
    super.key,
    required this.text,
    this.radius = Dimens.radiusCard,
  });

  final String text;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = StatusColors.careful;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.smallCardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.triangle_alert,
              size: Dimens.iconButtonIcon,
              color: p.icon,
            ),
            const SizedBox(width: Dimens.buttonGap),
            Expanded(
              child: Text(
                text,
                style: AppText.secondary.copyWith(color: p.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
