import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// "ใหม่" chip (DESIGN-SPEC §5): `primary` fill, white 16/700, padding
/// 2 10, a pill.
class NewChip extends StatelessWidget {
  const NewChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: Dimens.chipPaddingV,
        horizontal: Dimens.tagPaddingH,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(Dimens.radiusPill),
      ),
      child: Text(
        'ใหม่',
        style: AppText.label.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
