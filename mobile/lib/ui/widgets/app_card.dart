import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';

/// Card (DESIGN-SPEC §5): white, `divider` 1 px, radius 16, no shadow. An
/// [emphasised] card has an `outline` 1.5 px border instead.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Dimens.cardPadding),
    this.emphasised = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: emphasised
            ? Border.all(color: AppColors.outline, width: Dimens.outlineWidth)
            : Border.all(color: AppColors.divider),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
