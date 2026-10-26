import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../footcheck/foot_check_flow.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/back_link.dart';
import '../../widgets/buttons.dart';
import '../../widgets/info_box.dart';
import '../../widgets/numbered_steps.dart';
import '../../widgets/page_title.dart';
import '../foot_check_screen.dart';
import 'foot_check_copy.dart';

/// Foot check › Start (DESIGN-SPEC §11.1), in the tab with the bar. Shown
/// again by "ตรวจอีกครั้ง" ([repeat]) with a back link to Saved.
class StartView extends ConsumerWidget {
  const StartView({super.key, this.repeat = false});

  final bool repeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repeat) ...[
          BackLink(
            onTap: () => ref.read(footCheckRepeatProvider.notifier).set(false),
          ),
          const SizedBox(height: Dimens.tightGap),
        ],
        const PageTitle(FootCheckCopy.title),
        const SizedBox(height: Dimens.sectionGap),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(Dimens.radiusCard),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Dimens.linkCardPaddingH,
              vertical: Dimens.smallCardPadding,
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.timer,
                  size: Dimens.timeCardIcon,
                  color: AppColors.ink,
                ),
                SizedBox(width: Dimens.buttonGap),
                Expanded(
                  child: Text(FootCheckCopy.time, style: AppText.button),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Dimens.sectionGap),
        Text(
          FootCheckCopy.reason,
          style: AppText.body.copyWith(height: _reasonHeight),
        ),
        const SizedBox(height: Dimens.sectionGap),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(FootCheckCopy.whatTitle, style: AppText.cardTitle),
              SizedBox(height: Dimens.cardGap),
              NumberedSteps(steps: FootCheckCopy.whatSteps),
            ],
          ),
        ),
        const SizedBox(height: Dimens.sectionGap),
        const InfoBox(text: FootCheckCopy.tip, icon: LucideIcons.lightbulb),
        const SizedBox(height: Dimens.sectionGap),
        Row(
          children: [
            const Icon(
              LucideIcons.lock,
              size: Dimens.privacyIcon,
              color: AppColors.ink,
            ),
            const SizedBox(width: Dimens.tightGap),
            Expanded(
              child: Text(
                FootCheckCopy.privacy,
                style: AppText.secondary.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.sectionGap),
        PrimaryButton(
          key: const ValueKey('foot-check-start-photos'),
          label: FootCheckCopy.startPhotos,
          icon: LucideIcons.camera,
          onPressed: () async {
            await ref
                .read(footCheckFlowProvider.notifier)
                .begin(answerOnly: false);
            if (context.mounted) {
              await Navigator.pushNamed(context, Routes.footCheckCapture);
            }
          },
        ),
        const SizedBox(height: Dimens.buttonGap),
        SecondaryButton(
          key: const ValueKey('foot-check-answer-only'),
          label: FootCheckCopy.answerOnly,
          onPressed: () async {
            await ref
                .read(footCheckFlowProvider.notifier)
                .begin(answerOnly: true);
            if (context.mounted) {
              await Navigator.pushNamed(context, Routes.footCheckCompare);
            }
          },
        ),
      ],
    );
  }

  /// §11.1: reason line height 1.6.
  static const _reasonHeight = 1.6;
}
