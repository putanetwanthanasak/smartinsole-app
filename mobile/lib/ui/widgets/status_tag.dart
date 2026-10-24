import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Status tag (DESIGN-SPEC §5): a pill in the status background with an
/// 18 px status icon and 16/700 text in the status text colour. Always
/// icon + text + colour.
class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
  });

  final StatusPalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: Dimens.tagPaddingV,
        horizontal: Dimens.tagPaddingH,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Dimens.tagIcon, color: palette.icon),
          const SizedBox(width: Dimens.tagGap),
          Flexible(
            child: Text(
              label,
              style: AppText.label.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
