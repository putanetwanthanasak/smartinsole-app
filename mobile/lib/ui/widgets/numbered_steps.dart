import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// Numbered steps (DESIGN-SPEC §5): a 32 `primarySoft` circle with the
/// number (18/700 heading font), text 18 with line height 1.55, 12 between
/// circle and text, [stepGap] between steps (16; 12 in the TARE sheet).
class NumberedSteps extends StatelessWidget {
  const NumberedSteps({
    super.key,
    required this.steps,
    this.stepGap = Dimens.cardGap,
  });

  final List<String> steps;
  final double stepGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) SizedBox(height: stepGap),
          // One TalkBack item per step: "1 นั่งพักเท้า".
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: Dimens.stepCircle,
                  height: Dimens.stepCircle,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}', style: AppText.stepNumber),
                ),
                const SizedBox(width: Dimens.stepTextGap),
                Expanded(child: Text(steps[i], style: AppText.step)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
