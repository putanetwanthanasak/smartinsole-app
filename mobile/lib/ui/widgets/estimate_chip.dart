import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// "ค่าประมาณ ไม่ใช่การวินิจฉัย" (DESIGN-SPEC §8.3): `info` 18 `primary`,
/// `bg` fill, `divider` border, radius 999, padding 6 12, 16/600.
class EstimateChip extends StatelessWidget {
  const EstimateChip({super.key});

  static const text = 'ค่าประมาณ ไม่ใช่การวินิจฉัย';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(Dimens.radiusPill),
          border: Border.all(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Dimens.estimateChipPaddingV,
            horizontal: Dimens.estimateChipPaddingH,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.info,
                size: Dimens.tagIcon,
                color: AppColors.primary,
              ),
              const SizedBox(width: Dimens.tagGap),
              Flexible(child: Text(text, style: AppText.labelStrong)),
            ],
          ),
        ),
      ),
    );
  }
}
