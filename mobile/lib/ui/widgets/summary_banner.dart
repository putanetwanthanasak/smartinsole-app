import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../rules/patient_status.dart';
import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'status_card.dart';

/// Summary banner (DESIGN-SPEC §5, My feet): status background, radius 16,
/// padding 16 20, gap 12; a 44 white circle with the 26 px status icon;
/// title 18/700 and line 16 in the status text colour. Optionally a link
/// row inside ([linkLabel], white, radius 12, min height 48) or an
/// [action] (a primary button).
///
/// Title and line are a polite live region (§13), so TalkBack reads a new
/// state. The background cross-fades (`enter`); instant under reduce
/// motion.
class SummaryBanner extends StatelessWidget {
  const SummaryBanner({
    super.key,
    required this.level,
    required this.title,
    required this.line,
    this.linkLabel,
    this.onLink,
    this.linkKey,
    this.action,
  });

  final PatientLevel level;
  final String title;
  final String line;
  final String? linkLabel;
  final VoidCallback? onLink;
  final Key? linkKey;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(level);
    return AnimatedContainer(
      duration: Motion.duration(context, Motion.enterDuration),
      curve: Motion.enter,
      padding: const EdgeInsets.symmetric(
        vertical: Dimens.cardGap,
        horizontal: Dimens.linkCardPaddingH,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: Dimens.bannerCircle,
                      height: Dimens.bannerCircle,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        statusIconOf(level),
                        size: Dimens.bannerIcon,
                        color: palette.icon,
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimens.buttonGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppText.button.copyWith(color: palette.text),
                        ),
                        Text(
                          line,
                          style: AppText.secondary.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (linkLabel != null) ...[
            const SizedBox(height: Dimens.buttonGap),
            _LinkRow(key: linkKey, label: linkLabel!, onTap: onLink),
          ],
          if (action != null) ...[
            const SizedBox(height: Dimens.buttonGap),
            action!,
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Dimens.radiusInner);
    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Dimens.cardGap),
            child: Row(
              children: [
                Expanded(child: Text(label, style: AppText.button)),
                const Icon(
                  LucideIcons.chevron_right,
                  size: Dimens.listRowIcon,
                  color: AppColors.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
