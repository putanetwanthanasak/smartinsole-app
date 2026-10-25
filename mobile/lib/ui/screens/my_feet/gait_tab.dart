import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../ble/packets.dart';
import '../../../config/thresholds.dart';
import '../../../gait/gait_class.dart';
import '../../../gait/model_spec.dart';
import '../../motion.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/balance_bar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/confidence_segments.dart';
import '../../widgets/cop_foot.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/estimate_chip.dart';
import '../../widgets/motion_widgets.dart';
import '../home/home_copy.dart' show balanceNote, needBothFeet;
import '../home/home_model.dart';
import 'gait_copy.dart';
import 'gait_model.dart';
import 'my_feet_widgets.dart';

/// My feet › "การเดิน" (DESIGN-SPEC §8.3): "ตอนนี้" and "ก้าววันนี้", the
/// estimated gait, the left–right balance, and the numbers behind
/// "ดูตัวเลขละเอียด". No banner. The gait result is an estimate and never
/// a risk level (rule 11); two-foot values need both feet (rule 4).
///
/// The screen reads only [gaitViewProvider] (and Home's view for the
/// balance card), so the classifier behind it can change without touching
/// this file.
class GaitTab extends ConsumerWidget {
  const GaitTab({super.key, required this.drawInKey});

  /// Changes each time the bottom-bar tab opens: the balance bar grows
  /// from 50 : 50 again.
  final Object drawInKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(gaitViewProvider);
    final t = ref.watch(thresholdsProvider);
    final spec = ref.watch(modelInputSpecProvider);
    final walking = v.activity == GaitActivity.walking || v.estimate != null;
    return Column(
      key: const ValueKey('gait-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoColumns(
          left: _SmallCard(
            key: const ValueKey('gait-now-card'),
            icon: LucideIcons.activity,
            title: 'ตอนนี้',
            child: Text(
              activityTh(v.activity),
              key: const ValueKey('gait-now'),
              style: v.activity == GaitActivity.noData
                  ? AppText.sheetTitle.copyWith(color: AppColors.inkMuted)
                  : AppText.sheetTitle,
            ),
          ),
          right: _SmallCard(
            key: const ValueKey('gait-steps-card'),
            icon: LucideIcons.footprints,
            title: 'ก้าววันนี้',
            child: Semantics(
              label: '${_steps(v.stepsToday)} ก้าว',
              excludeSemantics: true,
              child: AnimatedNumber(
                key: const ValueKey('gait-steps'),
                value: v.stepsToday.toDouble(),
                format: (s) => _steps(s.round()),
                style: AppText.steps,
              ),
            ),
          ),
        ),
        const SizedBox(height: Dimens.sectionGap),
        _EstimateCard(view: v),
        const SizedBox(height: Dimens.sectionGap),
        _BalanceCard(walking: walking, drawInKey: drawInKey),
        const SizedBox(height: Dimens.sectionGap),
        DetailsExpander(
          key: const ValueKey('gait-details'),
          rows: gaitDetailRows(v, t, spec),
          trailing: [
            if (v.estimate?.probsPct case final probs?)
              _Probabilities(probsPct: probs),
            if (walking) _Cop(view: v),
          ],
        ),
      ],
    );
  }
}

final _thousands = NumberFormat('#,##0');
String _steps(int n) => _thousands.format(n);

/// A small card (§8.3): a 20 px `outline` icon and title, then one value.
class _SmallCard extends StatelessWidget {
  const _SmallCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: Dimens.smallCardIcon,
                  color: AppColors.outline,
                ),
                const SizedBox(width: Dimens.tightGap),
                Expanded(child: Text(title, style: AppText.labelStrong)),
              ],
            ),
            const SizedBox(height: Dimens.tightGap),
            child,
          ],
        ),
      ),
    );
  }
}

/// "ท่าเดินที่ระบบประเมิน" (§8.3): the estimate chip, then the result
/// (model or rules), "no result now", or no data; the rule-11 footer.
class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.view});

  final GaitView view;

  @override
  Widget build(BuildContext context) {
    final e = view.estimate;
    final Widget body;
    if (!view.bothUsable) {
      body = _NoResult(
        key: const ValueKey('gait-no-data'),
        icon: LucideIcons.bluetooth_off,
        title: noDataTitle,
        line: noDataLine,
        last: view.last,
        connect: true,
      );
    } else if (e == null) {
      body = _NoResult(
        key: const ValueKey('gait-no-result'),
        icon: LucideIcons.circle_pause,
        title: noResultTitle,
        line: noResultLine,
        last: view.last,
      );
    } else {
      body = _Result(estimate: e);
    }
    return AppCard(
      key: const ValueKey('gait-estimate-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ท่าเดินที่ระบบประเมิน', style: AppText.cardTitle),
          const SizedBox(height: Dimens.cardGap),
          const EstimateChip(),
          const SizedBox(height: Dimens.cardGap),
          body,
          const SizedBox(height: Dimens.cardGap),
          Container(
            padding: const EdgeInsets.only(top: Dimens.gaitFooterPaddingTop),
            decoration: topDivider,
            child: const Text(footerLine, style: AppText.secondary),
          ),
        ],
      ),
    );
  }
}

/// 56 circle with a 28 px icon.
class _Circle extends StatelessWidget {
  const _Circle({required this.icon, required this.fill, required this.color});

  final IconData icon;
  final Color fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Dimens.resultCircle,
      height: Dimens.resultCircle,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: Dimens.resultIcon, color: color),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.estimate});

  final GaitEstimateView estimate;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    return Column(
      key: ValueKey('gait-result-${e.gaitClass.id}-${e.source.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Circle(
                icon: LucideIcons.footprints,
                fill: AppColors.primarySoft,
                color: AppColors.primary,
              ),
              const SizedBox(width: Dimens.cardGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gaitClassName(e.gaitClass),
                      key: const ValueKey('gait-class'),
                      style: AppText.gaitClass,
                    ),
                    Text(
                      gaitClassDescription(e.gaitClass),
                      style: AppText.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimens.cardGap),
        if (e.fromModel)
          MergeSemantics(
            child: Wrap(
              key: const ValueKey('gait-confidence'),
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Dimens.buttonGap,
              runSpacing: Dimens.tightGap,
              children: [
                const Text('ความมั่นใจ', style: AppText.secondary),
                ConfidenceSegments(filled: confidenceFilled(e)),
                Text(confidenceWord(e), style: AppText.labelStrong),
              ],
            ),
          )
        else
          Text(
            rulesLine(e.because),
            key: const ValueKey('gait-rules-line'),
            style: AppText.secondary,
          ),
      ],
    );
  }
}

/// Not walking (§8.3), or no data (S8A default): a grey circle, a title
/// and a line, the last result, and for no data the connect button.
class _NoResult extends StatelessWidget {
  const _NoResult({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    this.last,
    this.connect = false,
  });

  final IconData icon;
  final String title;
  final String line;
  final GaitLastView? last;
  final bool connect;

  @override
  Widget build(BuildContext context) {
    final grey = StatusColors.noData;
    final l = last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Circle(icon: icon, fill: grey.background, color: grey.icon),
              const SizedBox(width: Dimens.cardGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.emptyTitle),
                    Text(line, style: AppText.secondary),
                    if (l != null) ...[
                      const SizedBox(height: Dimens.tightGap),
                      Text(
                        lastLine(l),
                        key: const ValueKey('gait-last'),
                        style: AppText.labelStrong,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (connect) ...[
          const SizedBox(height: Dimens.cardGap),
          PrimaryButton(
            key: const ValueKey('gait-connect'),
            label: 'เชื่อมต่อแผ่นรองเท้า',
            icon: LucideIcons.bluetooth,
            onPressed: () => Navigator.pushNamed(context, Routes.connection),
          ),
        ],
      ],
    );
  }
}

/// "การลงน้ำหนักซ้าย–ขวา" (§8.3), from Home's view so the two screens
/// show the same share and note. While `ASYMMETRY_PEAK` holds, the
/// number and note are in the Be-careful text colour with `triangle-alert`
/// (§14 proposed default, as Home).
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.walking, required this.drawInKey});

  final bool walking;
  final Object drawInKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (share, note, noLoad, asymmetry) = ref.watch(
      homeViewProvider.select(
        (v) => (
          v.leftSharePct,
          v.leftSharePct == null ? '' : balanceNote(v),
          v.balanceNoLoad,
          v.asymmetrySide != null,
        ),
      ),
    );
    final careful = StatusColors.careful;
    return AppCard(
      key: const ValueKey('gait-balance-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(balanceTitle(walking: walking), style: AppText.cardTitle),
          const SizedBox(height: Dimens.tightGap),
          if (share == null) ...[
            Text(
              '—',
              key: const ValueKey('gait-balance-none'),
              style: AppText.bigNumber.copyWith(color: AppColors.inkMuted),
            ),
            if (!noLoad) const Text(needBothFeet, style: AppText.secondary),
          ] else ...[
            Semantics(
              label: 'ซ้าย $share ขวา ${100 - share}',
              excludeSemantics: true,
              child: AnimatedNumber(
                key: const ValueKey('gait-balance-number'),
                value: share.toDouble(),
                format: (v) => '${v.round()} : ${100 - v.round()}',
                style: asymmetry
                    ? AppText.bigNumber.copyWith(color: careful.text)
                    : AppText.bigNumber,
              ),
            ),
            const SizedBox(height: Dimens.tightGap),
            BalanceBar(
              key: ValueKey(('gait-balance-bar', drawInKey)),
              leftSharePct: share.toDouble(),
            ),
            const SizedBox(height: Dimens.tightGap),
            asymmetry
                ? Row(
                    key: const ValueKey('gait-balance-warning'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.triangle_alert,
                        size: Dimens.smallCardIcon,
                        color: careful.icon,
                      ),
                      const SizedBox(width: Dimens.textGap),
                      Expanded(
                        child: Text(
                          note,
                          style: AppText.labelStrong.copyWith(
                            color: careful.text,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    note,
                    key: const ValueKey('gait-balance-note'),
                    style: AppText.labelStrong,
                  ),
          ],
        ],
      ),
    );
  }
}

/// "ความน่าจะเป็นของแต่ละท่า" (model only): name + "{n}%" over a bar 8
/// tall, radius 4, `primary` on `track`; the top class in bold. Bars move
/// with `value`.
class _Probabilities extends StatelessWidget {
  const _Probabilities({required this.probsPct});

  final List<int> probsPct;

  @override
  Widget build(BuildContext context) {
    var top = 0;
    for (var i = 1; i < probsPct.length; i++) {
      if (probsPct[i] > probsPct[top]) top = i;
    }
    final duration = Motion.duration(context, Motion.valueDuration);
    return Column(
      key: const ValueKey('gait-probabilities'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(probabilitiesTitle, style: AppText.secondary),
        for (var i = 0; i < probsPct.length; i++) ...[
          const SizedBox(height: Dimens.tightGap),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        gaitClassName(GaitClass.values[i]),
                        style: i == top
                            ? AppText.labelStrong.copyWith(
                                fontWeight: FontWeight.w700,
                              )
                            : AppText.label.copyWith(color: AppColors.ink),
                      ),
                    ),
                    Text(
                      '${probsPct[i]}%',
                      style: AppText.labelStrong.copyWith(
                        fontWeight: i == top
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Dimens.textGap),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      Dimens.probabilityBarHeight / 2,
                    ),
                    child: SizedBox(
                      height: Dimens.probabilityBarHeight,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: probsPct[i] / 100),
                        duration: duration,
                        curve: Motion.value,
                        builder: (context, p, _) => LinearProgressIndicator(
                          value: p,
                          minHeight: Dimens.probabilityBarHeight,
                          color: AppColors.primary,
                          backgroundColor: AppColors.track,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "เส้นทางของแรงกดในก้าวล่าสุด (CoP)": both feet at 60×134.
class _Cop extends StatelessWidget {
  const _Cop({required this.view});

  final GaitView view;

  @override
  Widget build(BuildContext context) {
    Widget foot(FootSide side) {
      final th = side == FootSide.left ? 'ซ้าย' : 'ขวา';
      final path = view.cop(side);
      return Semantics(
        label:
            'เท้า$th เส้นทางของแรงกด'
            '${path == null || path.isEmpty ? ' ยังไม่มีข้อมูล' : ''}',
        excludeSemantics: true,
        child: Column(
          children: [
            CopFoot(
              key: ValueKey('gait-cop-${side.name}'),
              side: side,
              path: path,
            ),
            const SizedBox(height: Dimens.textGap),
            Text(th, style: AppText.secondary),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('gait-cop'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(copTitle, style: AppText.secondary),
        const SizedBox(height: Dimens.tightGap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            foot(FootSide.left),
            const SizedBox(width: Dimens.feetFootGap),
            foot(FootSide.right),
          ],
        ),
      ],
    );
  }
}
