import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../footcheck/compare_source.dart';
import '../../../footcheck/footcheck_providers.dart';
import '../../../footcheck/history.dart';
import '../../../storage/models.dart';
import '../../clock.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/back_link.dart';
import '../../widgets/info_box.dart';
import '../../widgets/page_title.dart';
import '../../widgets/status_tag.dart';
import 'foot_check_copy.dart';
import 'photo_tile.dart';
import 'photo_viewer_screen.dart';

/// Photo history ("ดูรูปที่บันทึกไว้"): not designed (§14), a draft from
/// §5 components (user decision 7). Checks with photos grouped by day,
/// newest first; each a card with its time, result tag and the 4 views;
/// tap a photo to see it full screen. View-only: deleting stays in
/// Settings.
class PhotoHistoryScreen extends ConsumerWidget {
  const PhotoHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(photoHistoryProvider);
    final now = ref.watch(clockProvider)();
    final days = groupByDay(checks.value ?? const []);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey('photo-history'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pageTopPushed,
            Dimens.pagePadding,
            Dimens.pageBottomPushed,
          ),
          children: [
            const BackLink(),
            const SizedBox(height: Dimens.tightGap),
            const PageTitle(FootCheckCopy.historyTitle),
            const SizedBox(height: Dimens.sectionGap),
            const InfoBox(
              text: FootCheckCopy.historyNote,
              icon: LucideIcons.lock,
            ),
            if (checks.hasValue && days.isEmpty) ...[
              const SizedBox(height: Dimens.emptyTop),
              const _Empty(),
            ],
            for (final day in days) ...[
              const SizedBox(height: Dimens.sectionGap),
              Semantics(
                header: true,
                child: Text(
                  _dayTitle(day.localDate, now),
                  style: AppText.secondary.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final c in day.checks) ...[
                const SizedBox(height: Dimens.tightGap),
                _CheckCard(check: c),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _dayTitle(String localDate, DateTime now) {
    final d = localDateTimeOf(localDate);
    final rel = relativeDayTh(d, now);
    final date = thaiWeekdayDayMonth(d);
    return rel == null ? date : '$rel · $date';
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check});

  final FootCheck check;

  @override
  Widget build(BuildContext context) {
    final found = check.result == FootCheckResult.found;
    final time = hhmm(DateTime.fromMillisecondsSinceEpoch(check.atMs));
    return AppCard(
      key: ValueKey('photo-check-${check.id}'),
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Dimens.buttonGap,
            runSpacing: Dimens.tightGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(FootCheckCopy.atTime(time), style: AppText.bodyStrong),
              StatusTag(
                palette: found ? StatusColors.careful : _savedPalette,
                icon: found ? LucideIcons.triangle_alert : LucideIcons.check,
                label: found ? FootCheckCopy.dayFound : FootCheckCopy.daySaved,
              ),
            ],
          ),
          const SizedBox(height: Dimens.buttonGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final v in FootView.values) ...[
                if (v.index > 0) const SizedBox(width: Dimens.historyThumbGap),
                Expanded(
                  child: _Thumb(check: check, view: v),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// "บันทึกแล้ว" uses the 7-day row's saved colours, not the green Safe
  /// palette: a saved check says nothing about the foot (rule 14).
  static const _savedPalette = StatusPalette(
    background: AppColors.primarySoft,
    text: AppColors.ink,
    icon: AppColors.primary,
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.check, required this.view});

  final FootCheck check;
  final FootView view;

  @override
  Widget build(BuildContext context) {
    final path = check.photos[view];
    final name = FootCheckCopy.slotName(view);
    final radius = BorderRadius.circular(Dimens.radiusAnswer);
    final Widget box;
    if (path == null) {
      box = Semantics(
        label: '$name ${FootCheckCopy.notTaken}',
        excludeSemantics: true,
        child: const AspectRatio(
          aspectRatio: 1,
          child: EmptyPhotoFrame(
            text: FootCheckCopy.notTaken,
            radius: Dimens.radiusAnswer,
          ),
        ),
      );
    } else {
      void open() => Navigator.pushNamed(
        context,
        Routes.footCheckPhoto,
        arguments: PhotoViewerArgs(
          path: path,
          title: FootCheckCopy.viewName(view),
          atMs: check.atMs,
        ),
      );
      box = Semantics(
        button: true,
        image: true,
        label: '${FootCheckCopy.photo} ${FootCheckCopy.viewName(view)}',
        excludeSemantics: true,
        onTap: open,
        child: GestureDetector(
          key: ValueKey('photo-${check.id}-${view.name}'),
          onTap: open,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: radius,
              child: FootPhoto(path: path, cacheWidth: _thumbCacheWidth),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        box,
        const SizedBox(height: Dimens.textGap),
        ExcludeSemantics(
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: AppText.secondary,
          ),
        ),
      ],
    );
  }

  static const _thumbCacheWidth = 240;
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox.square(
          dimension: Dimens.emptyCircle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.image,
              size: Dimens.emptyIcon,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: Dimens.cardGap),
        const Text(
          FootCheckCopy.historyEmpty,
          style: AppText.emptyTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Dimens.tightGap),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Dimens.emptyTextMaxWidth),
          child: const Text(
            FootCheckCopy.historyEmptyText,
            style: AppText.secondary,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
