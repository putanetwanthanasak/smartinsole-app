import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// "Today's foot check not done yet" card (DESIGN-SPEC section 5, item 4).
/// The whole card is tappable. Whether it is shown is decided by the caller;
/// the real "done today" logic arrives in S8C.
class FootCheckCard extends StatelessWidget {
  const FootCheckCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _radius = BorderRadius.all(
    Radius.circular(Dimens.radiusCardSmall),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: _radius,
        side: BorderSide(
          color: AppColors.outlineBtn,
          width: Dimens.footCheckBorderWidth,
        ),
      ),
      child: InkWell(
        borderRadius: _radius,
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(Dimens.cardPadding),
          child: Row(
            children: [
              SizedBox.square(
                dimension: Dimens.footCheckIconCircle,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.camera, color: AppColors.primary),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('วันนี้ยังไม่ได้ดูเท้า', style: AppText.bodyStrong),
                    Text(
                      'ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที',
                      style: AppText.tabLabel,
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevron_right, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
