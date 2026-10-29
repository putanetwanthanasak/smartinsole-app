import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../footcheck/foot_check_flow.dart';
import '../../../footcheck/footcheck_providers.dart';
import '../../../footcheck/history.dart';
import '../../../storage/models.dart';
import '../../clock.dart';
import '../../routes.dart';
import '../../shell/app_shell.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/back_link.dart';
import '../../widgets/buttons.dart';
import '../../widgets/info_box.dart';
import '../../widgets/page_title.dart';
import '../../widgets/segmented_tabs.dart';
import 'foot_check_copy.dart';
import 'photo_tile.dart';

/// Foot check › Compare & answer (DESIGN-SPEC §11.3), no bar. Back goes to
/// Capture, or to Start when answering only (which also drops the run).
/// Answer-only has no view picker and no photos (§14). "บันทึก" is enabled
/// once all 3 questions are answered; none is answered when it opens
/// (decision 9).
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  var _view = FootView.soleLeft;
  var _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final check = await ref.read(footCheckFlowProvider.notifier).save();
    ref.read(selectedTabProvider.notifier).select(AppTab.footCheck);
    nav.popUntil((r) => r.isFirst);
    if (check.result == FootCheckResult.found) {
      await nav.pushNamed(Routes.footCheckFound, arguments: check.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(footCheckFlowProvider);
    if (run == null) return const Scaffold(body: SizedBox.shrink());
    final now = ref.watch(clockProvider)();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && run.answerOnly && !_saving) {
          ref.read(footCheckFlowProvider.notifier).discard();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            key: const ValueKey('compare-scroll'),
            padding: const EdgeInsets.fromLTRB(
              Dimens.pagePadding,
              Dimens.pageTopPushed,
              Dimens.pagePadding,
              Dimens.pageBottomPushed,
            ),
            children: [
              const BackLink(),
              const SizedBox(height: Dimens.tightGap),
              PageTitle(
                run.answerOnly
                    ? FootCheckCopy.answerOnlyTitle
                    : FootCheckCopy.compareTitle,
              ),
              const SizedBox(height: Dimens.sectionGap),
              if (!run.answerOnly) ...[
                SegmentedTabs<FootView>(
                  semanticLabel: FootCheckCopy.pickerLabel,
                  radio: true,
                  small: true,
                  selected: _view,
                  onSelect: (v) => setState(() => _view = v),
                  options: [
                    for (final v in FootView.values)
                      SegmentOption(
                        value: v,
                        label: FootCheckCopy.slotName(v),
                        key: ValueKey('compare-view-${v.name}'),
                      ),
                  ],
                ),
                const SizedBox(height: Dimens.cardGap),
                _Photos(view: _view, today: run.photos[_view], now: now),
                const SizedBox(height: Dimens.sectionGap),
              ],
              _Questions(
                answers: run.answers,
                onAnswer: ref.read(footCheckFlowProvider.notifier).answer,
              ),
              const SizedBox(height: Dimens.sectionGap),
              const InfoBox(text: FootCheckCopy.note),
              const SizedBox(height: Dimens.sectionGap),
              PrimaryButton(
                key: const ValueKey('compare-save'),
                label: FootCheckCopy.save,
                onPressed: run.complete && !_saving ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Photos extends ConsumerWidget {
  const _Photos({required this.view, required this.today, required this.now});

  final FootView view;
  final String? today;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(compareSourceProvider(view)).value;
    final name = FootCheckCopy.viewName(view);
    final todayCaption =
        '${FootCheckCopy.today} · ${FootCheckCopy.dayMonth(now)}';
    final leftCaption = source == null
        ? ''
        : FootCheckCopy.compareCaption(source);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('compare-earlier'),
                height: Dimens.comparePhotoHeight,
                child: source?.photo == null
                    ? EmptyPhotoFrame(
                        text: source == null ? '' : FootCheckCopy.noEarlier,
                      )
                    : Semantics(
                        image: true,
                        label: '${FootCheckCopy.photo} $name $leftCaption',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            Dimens.radiusCard,
                          ),
                          child: FootPhoto(path: source!.photo!.path),
                        ),
                      ),
              ),
              const SizedBox(height: Dimens.tightGap),
              Text(leftCaption, style: AppText.secondary),
            ],
          ),
        ),
        const SizedBox(width: Dimens.gridGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('compare-today'),
                height: Dimens.comparePhotoHeight,
                child: today == null
                    ? const EmptyPhotoFrame(text: FootCheckCopy.skipped)
                    : Semantics(
                        image: true,
                        label:
                            '${FootCheckCopy.photo} $name ${FootCheckCopy.today}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              Dimens.radiusCard,
                            ),
                            border: Border.all(
                              color: AppColors.primary,
                              width: Dimens.todayPhotoBorder,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              Dimens.radiusCard - Dimens.todayPhotoBorder,
                            ),
                            child: FootPhoto(path: today!),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: Dimens.tightGap),
              Text(
                todayCaption,
                style: AppText.secondary.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Questions extends StatelessWidget {
  const _Questions({required this.answers, required this.onAnswer});

  final Map<FootCheckQuestion, FootCheckAnswer> answers;
  final void Function(FootCheckQuestion, FootCheckAnswer) onAnswer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in FootCheckQuestion.values) ...[
            if (q.index > 0) const SizedBox(height: Dimens.sectionGap),
            Semantics(
              role: SemanticsRole.radioGroup,
              label: FootCheckCopy.question(q),
              container: true,
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      FootCheckCopy.question(q),
                      style: AppText.bodyStrong,
                    ),
                  ),
                  const SizedBox(height: Dimens.buttonGap),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final a in FootCheckAnswer.values) ...[
                          if (a.index > 0)
                            const SizedBox(width: Dimens.buttonGap),
                          Expanded(
                            child: _Answer(
                              key: ValueKey('answer-${q.name}-${a.name}'),
                              answer: a,
                              selected: answers[q] == a,
                              onTap: () => onAnswer(q, a),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One answer button (§11.3): min height 56, radius 14. "ไม่มี" selected:
/// `primarySoft`, 2 px `primary`, `check` 20. "มี / ไม่แน่ใจ" selected:
/// Be-careful colours, 2 px icon colour, `triangle-alert` 20. Unselected:
/// white, `outline` 1.5, `ink` 600.
class _Answer extends StatelessWidget {
  const _Answer({
    super.key,
    required this.answer,
    required this.selected,
    required this.onTap,
  });

  final FootCheckAnswer answer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final none = answer == FootCheckAnswer.none;
    final label = none ? FootCheckCopy.none : FootCheckCopy.yesOrUnsure;
    final careful = StatusColors.careful;
    final Color fill, border, text;
    final double width;
    IconData? icon;
    Color? iconColor;
    if (!selected) {
      fill = AppColors.surface;
      border = AppColors.outline;
      text = AppColors.ink;
      width = Dimens.outlineWidth;
    } else if (none) {
      fill = AppColors.primarySoft;
      border = AppColors.primary;
      text = AppColors.ink;
      width = Dimens.answerBorder;
      icon = LucideIcons.check;
      iconColor = AppColors.primary;
    } else {
      fill = careful.background;
      border = careful.icon;
      text = careful.text;
      width = Dimens.answerBorder;
      icon = LucideIcons.triangle_alert;
      iconColor = careful.icon;
    }
    final radius = BorderRadius.circular(Dimens.radiusAnswer);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border, width: width),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dimens.answerHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.tightGap,
                vertical: Dimens.textGap,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: Dimens.answerIcon, color: iconColor),
                    const SizedBox(width: Dimens.textGap * 1.5),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(
                        color: text,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
