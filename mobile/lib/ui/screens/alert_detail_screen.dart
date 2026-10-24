import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/packets.dart';
import '../../config/thresholds.dart';
import '../../rules/alert_copy.dart';
import '../../storage/models.dart';
import '../../storage/storage_providers.dart';
import '../clock.dart';
import '../routes.dart';
import '../shell/app_shell.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/back_link.dart';
import '../widgets/buttons.dart';
import '../widgets/detail_status_card.dart';
import '../widgets/details_expander.dart';
import '../widgets/disclaimer_line.dart';
import '../widgets/foot_map.dart';
import '../widgets/numbered_steps.dart';
import '../widgets/temp_site_map.dart';
import 'alerts/alert_view.dart';

/// Alert detail (DESIGN-SPEC §7.3), pushed with the alert's id as the
/// route argument. Opening it marks the alert read (decision 7). Motion:
/// only the details expander's chevron (§12.2).
class AlertDetailScreen extends ConsumerStatefulWidget {
  const AlertDetailScreen({super.key, required this.alertId});

  final int alertId;

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  @override
  void initState() {
    super.initState();
    ref
        .read(alertRepositoryProvider)
        .markRead(
          widget.alertId,
          ref.read(clockProvider)().millisecondsSinceEpoch,
        );
  }

  @override
  Widget build(BuildContext context) {
    final alert = ref.watch(alertByIdProvider(widget.alertId)).value;
    final thresholds = ref.watch(thresholdsProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('alert-detail-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pageTopPushed,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            const BackLink(),
            if (alert != null)
              ..._sections(
                context,
                alert,
                thresholds,
                now,
              ).expand((w) => [const SizedBox(height: Dimens.sectionGap), w]),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    StoredAlert a,
    Thresholds t,
    DateTime now,
  ) {
    final look = lookOf(a.kind);
    final copy = copyOf(a);
    final action = actionOf(a.kind);
    final note = gaitNoteOf(a, t);
    final temp = tempMapOf(a);
    final pressure = pressureMapOf(a, t);
    return [
      DetailStatusCard(
        palette: look.palette,
        icon: look.icon,
        levelWord: look.levelWord,
        time: detailTime(a, now),
        title: copy.title,
        detail: copy.detail,
      ),
      AppCard(
        key: const ValueKey('detail-steps'),
        emphasised: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text('สิ่งที่ควรทำ', style: AppText.cardTitle),
            ),
            const SizedBox(height: Dimens.cardGap),
            NumberedSteps(steps: copy.steps),
          ],
        ),
      ),
      if (temp != null)
        _MapCard(
          caption: temp.caption,
          captionColor: look.palette.text,
          legend: const TempSiteLegend(textStyle: AppText.secondary),
          foot: (side) => TempSiteMap(
            key: ValueKey('detail-map-${side.name}'),
            side: side,
            warmSite: side == temp.warmSide ? temp.site : null,
            semanticLabel: temp.labels[side]!,
            width: Dimens.homeFootWidth,
            height: Dimens.homeFootHeight,
          ),
        ),
      if (pressure != null)
        _MapCard(
          caption: pressure.caption,
          captionColor: look.palette.text,
          legend: const PressureLegend(textStyle: AppText.secondary),
          foot: (side) => FootMap(
            key: ValueKey('detail-map-${side.name}'),
            side: side,
            levels: pressure.levels[side],
            ringChannel: side == pressure.side ? pressure.channel : null,
            pulse: false,
            semanticLabel: pressure.labels[side]!,
            width: Dimens.homeFootWidth,
            height: Dimens.homeFootHeight,
          ),
        ),
      AppCard(
        key: const ValueKey('detail-why'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text('ทำไมแอปถึงเตือน', style: AppText.cardTitle),
            ),
            const SizedBox(height: Dimens.cardGap),
            Text(copy.why, style: AppText.body),
            if (note != null) ...[
              const SizedBox(height: Dimens.cardGap),
              _GaitNote(text: note),
            ],
          ],
        ),
      ),
      DetailsExpander(rows: detailRowsOf(a, t)),
      const DisclaimerLine(),
      if (action != null)
        PrimaryButton(
          key: const ValueKey('detail-action'),
          label: action.label,
          trailingIcon: LucideIcons.chevron_right,
          onPressed: () {
            final tab = action.myFeetTab;
            if (tab == null) {
              Navigator.pushNamed(context, Routes.connection);
            } else {
              openMyFeet(context, ref, tab);
            }
          },
        ),
    ];
  }
}

/// "ตำแหน่งที่พบ": both feet (84×188, 48 apart, "ซ้าย" / "ขวา"), caption
/// in the status text colour, legend.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.caption,
    required this.captionColor,
    required this.legend,
    required this.foot,
  });

  final String caption;
  final Color captionColor;
  final Widget legend;
  final Widget Function(FootSide side) foot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('detail-map'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('ตำแหน่งที่พบ', style: AppText.cardTitle),
          ),
          const SizedBox(height: Dimens.cardGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final side in FootSide.values) ...[
                if (side == FootSide.right)
                  const SizedBox(width: Dimens.homeFootGap),
                Column(
                  children: [
                    foot(side),
                    const SizedBox(height: Dimens.tightGap),
                    ExcludeSemantics(
                      child: Text(
                        sideTh(side),
                        style: AppText.labelStrong.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: Dimens.cardGap),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppText.labelStrong.copyWith(color: captionColor),
          ),
          const SizedBox(height: Dimens.buttonGap),
          legend,
        ],
      ),
    );
  }
}

/// The gait note (contract §8.3.1): `bg` box, radius 12, padding 16,
/// `footprints` 24 `primary`, text 16. It explains, never changes the
/// level (rule 11).
class _GaitNote extends StatelessWidget {
  const _GaitNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('gait-note'),
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(Dimens.radiusInner),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.footprints,
            size: Dimens.noteIcon,
            color: AppColors.primary,
          ),
          const SizedBox(width: Dimens.buttonGap),
          Expanded(
            child: Text(
              text,
              style: AppText.secondary.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
