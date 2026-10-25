import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// The My feet balance bar (DESIGN-SPEC §8.3): 12 tall, radius 6,
/// `accentLight` track, the left share in `primary` growing from the left,
/// a 2×18 `ink` centre tick; "ซ้าย" / "ขวา" under the ends.
///
/// Motion (§12.2): it grows from 50 : 50 to its value (`value`) when first
/// built, then slides to each new value; under reduce motion it is simply
/// there. Home keeps its own 10-tall bar.
class BalanceBar extends StatelessWidget {
  const BalanceBar({super.key, required this.leftSharePct});

  final double leftSharePct;

  static const _half = 0.5;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(
            height: Dimens.feetBalanceTickHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: _half, end: leftSharePct / 100),
              duration: Motion.duration(context, Motion.valueDuration),
              curve: Motion.value,
              builder: (context, left, _) => CustomPaint(
                size: Size.infinite,
                painter: _BalancePainter(left: left),
              ),
            ),
          ),
          const SizedBox(height: Dimens.textGap),
          const Row(
            children: [
              Expanded(child: Text('ซ้าย', style: AppText.secondary)),
              Text('ขวา', style: AppText.secondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({required this.left});

  /// Left share, 0–1.
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    const h = Dimens.feetBalanceBarHeight;
    final top = (size.height - h) / 2;
    final bar = RRect.fromLTRBR(
      0,
      top,
      size.width,
      top + h,
      const Radius.circular(h / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRRect(bar, Paint()..color = AppColors.accentLight)
      ..drawRect(
        Rect.fromLTWH(0, top, size.width * left, h),
        Paint()..color = AppColors.primary,
      )
      ..restore()
      ..drawRect(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: Dimens.balanceTickWidth,
          height: Dimens.feetBalanceTickHeight,
        ),
        Paint()..color = AppColors.ink,
      );
  }

  @override
  bool shouldRepaint(_BalancePainter old) => old.left != left;
}
