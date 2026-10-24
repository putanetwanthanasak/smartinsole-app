import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// "Today's foot check not done yet" card (DESIGN-SPEC §6 item 4): min
/// height 88, white, `outline` 1.5 px, radius 16, padding 16 20; the whole
/// card is one link. Whether it is shown is decided by the caller; the real
/// "done today" logic arrives in S8C.
class FootCheckCard extends StatelessWidget {
  const FootCheckCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(Dimens.radiusCard));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(color: AppColors.outline, width: Dimens.outlineWidth),
      ),
      child: InkWell(
        key: const ValueKey('foot-check-card'),
        borderRadius: _radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: Dimens.footCheckCardHeight,
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Dimens.linkCardPaddingH,
              vertical: Dimens.smallCardPadding,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: Dimens.iconCircle,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.camera, color: AppColors.primary),
                  ),
                ),
                SizedBox(width: Dimens.cardGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('วันนี้ยังไม่ได้ดูเท้า', style: AppText.bodyStrong),
                      Text(
                        // Non-breaking space keeps "1 นาที" on one line.
                        'ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที',
                        style: AppText.secondary,
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevron_right, color: AppColors.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
