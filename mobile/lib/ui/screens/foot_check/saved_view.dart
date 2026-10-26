import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../footcheck/compare_source.dart';
import '../../../footcheck/footcheck_providers.dart';
import '../../../footcheck/history.dart';
import '../../../notify/reminder_providers.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/settings_providers.dart';
import '../../../storage/models.dart';
import '../../clock.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/buttons.dart';
import '../../widgets/info_box.dart';
import '../../widgets/page_title.dart';
import '../foot_check_screen.dart';
import 'foot_check_copy.dart';
import 'week_card.dart';

/// Foot check › Saved (DESIGN-SPEC §11.5), or, when today's latest check
/// found something, the found-today view (user decision 4, the approved
/// proposal): a Be-careful result card instead of the white one, and no
/// "yesterday" box (today's result covers it). Both in the tab with the
/// bar.
class SavedView extends ConsumerWidget {
  const SavedView({super.key, required this.check});

  /// Today's latest check.
  final FootCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = check.result == FootCheckResult.found;
    final dates = ref.watch(weekDatesProvider);
    final latest = latestPerDay(ref.watch(weekChecksProvider).value ?? []);
    final yesterday = latest[previousLocalDate(check.localDate)];
    final at = hhmm(DateTime.fromMillisecondsSinceEpoch(check.atMs));
    final remind = _reminderLine(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(FootCheckCopy.title),
        const SizedBox(height: Dimens.sectionGap),
        if (found)
          _FoundTodayCard(check: check, at: at, remind: remind)
        else
          _SavedCard(at: at, remind: remind),
        if (!found && yesterday?.result == FootCheckResult.found) ...[
          const SizedBox(height: Dimens.sectionGap),
          const _YesterdayBox(),
        ],
        const SizedBox(height: Dimens.sectionGap),
        WeekCard(
          dates: dates,
          marks: [for (final d in dates) dayMarkOf(latest[d])],
        ),
        const SizedBox(height: Dimens.sectionGap),
        SecondaryButton(
          key: const ValueKey('foot-check-again'),
          label: FootCheckCopy.again,
          onPressed: () => ref.read(footCheckRepeatProvider.notifier).set(true),
        ),
        const SizedBox(height: Dimens.buttonGap),
        SecondaryButton(
          key: const ValueKey('foot-check-photos'),
          label: FootCheckCopy.seePhotos,
          icon: LucideIcons.image,
          onPressed: () => Navigator.pushNamed(context, Routes.footCheckPhotos),
        ),
      ],
    );
  }

  /// "พรุ่งนี้แอปจะเตือนตอน {HH:mm}", only while the reminder is on and the
  /// phone lets the app post it (user decision 3).
  String? _reminderLine(WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final allowed = ref.watch(notificationsAllowedProvider).value ?? false;
    if (!s.footCheckReminder || !allowed) return null;
    return FootCheckCopy.remindAt(formatReminderTime(s.reminderTime));
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.at, required this.remind});

  final String at;
  final String? remind;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('foot-check-saved-card'),
      padding: const EdgeInsets.all(Dimens.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusStatusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox.square(
            dimension: Dimens.savedCircle,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.check,
                size: Dimens.savedIcon,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: Dimens.cardGap),
          Semantics(
            liveRegion: true,
            child: const Text(
              FootCheckCopy.savedTitle,
              style: AppText.pageTitle,
            ),
          ),
          const SizedBox(height: Dimens.tightGap),
          Text(FootCheckCopy.checkedAt(at), style: AppText.secondary),
          if (remind != null) Text(remind!, style: AppText.secondary),
        ],
      ),
    );
  }
}

class _FoundTodayCard extends StatelessWidget {
  const _FoundTodayCard({
    required this.check,
    required this.at,
    required this.remind,
  });

  final FootCheck check;
  final String at;
  final String? remind;

  @override
  Widget build(BuildContext context) {
    final p = StatusColors.careful;
    final text = p.text;
    return Container(
      key: const ValueKey('foot-check-found-card'),
      padding: const EdgeInsets.all(Dimens.cardPadding),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(Dimens.radiusStatusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox.square(
              dimension: Dimens.statusIconCircle,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.triangle_alert,
                  size: Dimens.statusIcon,
                  color: p.icon,
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.buttonGap),
          Semantics(
            liveRegion: true,
            child: Text(
              FootCheckCopy.foundTodayTitle,
              style: AppText.pageTitle.copyWith(color: text),
            ),
          ),
          const SizedBox(height: Dimens.textGap),
          Text(
            FootCheckCopy.foundCheckedAt(at),
            style: AppText.secondary.copyWith(color: text),
          ),
          const SizedBox(height: Dimens.buttonGap),
          Text(
            FootCheckCopy.youAnswered,
            style: AppText.secondary.copyWith(
              color: text,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final q in findingsOf(check))
            Text(
              FootCheckCopy.finding(q),
              style: AppText.body.copyWith(color: text),
            ),
          const SizedBox(height: Dimens.buttonGap),
          _LinkRow(
            label: FootCheckCopy.whatToDo,
            onTap: () => Navigator.pushNamed(
              context,
              Routes.footCheckFound,
              arguments: check.id,
            ),
          ),
          if (remind != null) ...[
            const SizedBox(height: Dimens.buttonGap),
            Text(remind!, style: AppText.secondary.copyWith(color: text)),
          ],
        ],
      ),
    );
  }
}

/// White link row inside a status card (§5 summary banner pattern):
/// radius 12, min height 48, 18/700 `ink` + `chevron-right` 22.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Dimens.radiusInner);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          key: const ValueKey('foot-check-what-to-do'),
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dimens.linkRowHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.smallCardPadding,
              ),
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
      ),
    );
  }
}

class _YesterdayBox extends StatelessWidget {
  const _YesterdayBox();

  @override
  Widget build(BuildContext context) => const WarningBox(
    key: ValueKey('foot-check-yesterday-found'),
    text: FootCheckCopy.yesterdayFound,
  );
}
