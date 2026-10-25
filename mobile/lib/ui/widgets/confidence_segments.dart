import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';

/// [filled] of [count] segments (DESIGN-SPEC §8.3): 36×10, radius 5, gap
/// 4; filled `primary`, empty `track`. The fill changes colour with
/// `enter`. Screen readers hear the word next to it, not the segments.
class ConfidenceSegments extends StatelessWidget {
  const ConfidenceSegments({super.key, required this.filled, this.count = 3});

  final int filled;
  final int count;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, Motion.enterDuration);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: Dimens.confidenceSegmentGap),
            AnimatedContainer(
              key: ValueKey('confidence-segment-$i'),
              duration: duration,
              curve: Motion.enter,
              width: Dimens.confidenceSegmentWidth,
              height: Dimens.confidenceSegmentHeight,
              decoration: BoxDecoration(
                color: i < filled ? AppColors.primary : AppColors.track,
                borderRadius: BorderRadius.circular(
                  Dimens.confidenceSegmentHeight / 2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
