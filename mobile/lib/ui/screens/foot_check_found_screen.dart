import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../footcheck/footcheck_providers.dart';
import '../../footcheck/history.dart';
import '../routes.dart';
import '../shell/app_shell.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/buttons.dart';
import '../widgets/disclaimer_line.dart';
import '../widgets/numbered_steps.dart';
import 'foot_check/foot_check_copy.dart';

/// Foot check › Something found (DESIGN-SPEC §11.4), no bar and no back
/// link: it leaves through its two buttons. Opened after saving a check
/// with any "มี / ไม่แน่ใจ", from a foot-check finding on the Alerts list,
/// and from the found-today tab's "ดูสิ่งที่ควรทำ", always with the
/// check's id. Steps and the urgent box are draft health copy (Appendix A).
class FootCheckFoundScreen extends ConsumerWidget {
  const FootCheckFoundScreen({super.key, required this.footCheckId});

  final int? footCheckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = footCheckId;
    final check = id == null
        ? null
        : ref.watch(footCheckByIdProvider(id)).value;
    final findings = check == null
        ? const <FootCheckQuestion>[]
        : findingsOf(check);
    final careful = StatusColors.careful;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: ValueKey('foot-check-found-$footCheckId'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(Dimens.cardPadding),
              decoration: BoxDecoration(
                color: careful.background,
                borderRadius: BorderRadius.circular(Dimens.radiusStatusCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: Dimens.statusIconCircle,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.triangle_alert,
                        size: Dimens.statusIcon,
                        color: careful.icon,
                      ),
                    ),
                  ),
                  const SizedBox(height: Dimens.buttonGap),
                  Semantics(
                    header: true,
                    child: Text(
                      FootCheckCopy.foundTitle,
                      style: AppText.pageTitle.copyWith(color: careful.text),
                    ),
                  ),
                  if (findings.isNotEmpty) ...[
                    const SizedBox(height: Dimens.buttonGap),
                    Text(
                      FootCheckCopy.youAnswered,
                      style: AppText.secondary.copyWith(
                        color: careful.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final q in findings)
                      Text(
                        FootCheckCopy.finding(q),
                        style: AppText.body.copyWith(color: careful.text),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Dimens.sectionGap),
            const AppCard(
              emphasised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(FootCheckCopy.whatNow, style: AppText.cardTitle),
                  SizedBox(height: Dimens.cardGap),
                  NumberedSteps(steps: FootCheckCopy.foundSteps),
                ],
              ),
            ),
            const SizedBox(height: Dimens.sectionGap),
            const _UrgentBox(),
            const SizedBox(height: Dimens.sectionGap),
            const DisclaimerLine(),
            const SizedBox(height: Dimens.sectionGap),
            SecondaryButton(
              key: const ValueKey('found-photos'),
              label: FootCheckCopy.seePhotos,
              icon: LucideIcons.image,
              onPressed: () =>
                  Navigator.pushNamed(context, Routes.footCheckPhotos),
            ),
            const SizedBox(height: Dimens.buttonGap),
            PrimaryButton(
              key: const ValueKey('found-home'),
              label: FootCheckCopy.backHome,
              onPressed: () {
                ref.read(selectedTabProvider.notifier).select(AppTab.today);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Urgent box (§5): Rest background, radius 16, padding 20;
/// `octagon-alert` 26; text 18/600 in the Rest text colour.
class _UrgentBox extends StatelessWidget {
  const _UrgentBox();

  @override
  Widget build(BuildContext context) {
    final rest = StatusColors.rest;
    return Container(
      padding: const EdgeInsets.all(Dimens.linkCardPaddingH),
      decoration: BoxDecoration(
        color: rest.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.octagon_alert,
            size: Dimens.bannerIcon,
            color: rest.icon,
          ),
          const SizedBox(width: Dimens.buttonGap),
          Expanded(
            child: Text(
              FootCheckCopy.urgent,
              style: AppText.bodyStrong.copyWith(color: rest.text),
            ),
          ),
        ],
      ),
    );
  }
}
