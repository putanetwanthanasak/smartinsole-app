import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Back link at the top left of pushed screens (DESIGN-SPEC §5):
/// `chevron-left` 24 + "กลับ" 18/600 `ink`, at least 48 high; returns to
/// the previous screen.
class BackLink extends StatelessWidget {
  const BackLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        label: 'กลับ',
        excludeSemantics: true,
        onTap: () => Navigator.maybePop(context),
        child: InkWell(
          key: const ValueKey('back-link'),
          borderRadius: BorderRadius.circular(Dimens.radiusInner),
          onTap: () => Navigator.maybePop(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Dimens.minTouchTarget,
              minWidth: Dimens.minTouchTarget,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.chevron_left,
                  size: Dimens.iconButtonIcon,
                  color: AppColors.ink,
                ),
                Text('กลับ', style: AppText.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
