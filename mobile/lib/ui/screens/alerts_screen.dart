import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../footcheck/footcheck_providers.dart';
import '../../storage/models.dart';
import '../../storage/storage_providers.dart';
import '../clock.dart';
import '../motion.dart';
import '../routes.dart';
import '../shell/app_shell.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/new_chip.dart';
import '../widgets/page_title.dart';
import '../widgets/status_tag.dart';
import 'alerts/alert_view.dart';

/// Alerts, "แจ้งเตือน" (DESIGN-SPEC §7.2): patient-visible alerts of the
/// last 30 days, grouped by the patient's day, newest first.
///
/// Motion (§12.2): each time the tab opens, the title, group titles,
/// cards and footer rise in with `stagger` (the tab lives in an
/// IndexedStack, so it replays on every selection). An alert that arrives
/// while the list is shown opens its row at the top (height + fade,
/// `enter`) and slides down from above; the bar's bell and badge react on
/// their own. Under reduce motion everything is simply there.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  /// Bumped each time the tab is selected: restarts the entrance.
  int _opened = 0;

  /// Alert ids already on screen; null until the first list arrives. Rows
  /// not in it are new arrivals.
  Set<int>? _seen;

  /// Rows that arrived while the list was shown. Kept until the tab opens
  /// again, so a rebuild in the middle of their entrance (the unread count
  /// changes at the same moment) does not cut it short.
  final _arrived = <int>{};

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedTabProvider, (prev, next) {
      if (next == AppTab.alerts && prev != AppTab.alerts) {
        setState(() {
          _opened++;
          // A fresh entrance: nothing counts as newly arrived.
          _seen = null;
          _arrived.clear();
        });
      }
    });
    final alerts = ref.watch(visibleAlertsProvider).value;
    final unread = ref.watch(unreadAlertCountProvider);
    // "วันนี้" / "เมื่อวาน" follow the day, which rolls over at midnight and
    // on resume, not the clock at the last rebuild (BACKLOG 68).
    final today = ref.watch(todayProvider);

    final seen = _seen;
    final ids = {for (final a in alerts ?? const <StoredAlert>[]) a.id};
    if (seen != null) _arrived.addAll(ids.difference(seen));
    if (alerts != null) _seen = {...?seen, ...ids};

    final children = <Widget>[
      _Header(key: const ValueKey('alerts-header'), unread: unread),
    ];
    if (alerts != null && alerts.isEmpty) {
      children.add(const _Empty(key: ValueKey('alerts-empty')));
    } else if (alerts != null) {
      String? day;
      for (final a in alerts) {
        if (a.localDate != day) {
          day = a.localDate;
          children.add(
            Padding(
              key: ValueKey('group-$day'),
              padding: const EdgeInsets.only(top: Dimens.sectionGap),
              child: Semantics(
                header: true,
                child: Text(groupTitle(day, today), style: AppText.cardTitle),
              ),
            ),
          );
        }
        final card = Padding(
          padding: const EdgeInsets.only(top: Dimens.groupTitleGap),
          child: _AlertCard(alert: a),
        );
        children.add(
          KeyedSubtree(
            key: ValueKey('alert-${a.id}'),
            child: _arrived.contains(a.id) ? _NewRow(child: card) : card,
          ),
        );
      }
      children.add(
        Padding(
          key: const ValueKey('alerts-footer'),
          padding: const EdgeInsets.only(top: Dimens.sectionGap),
          child: Text(
            'แสดงย้อนหลัง ${retentionPeriod.inDays} วัน',
            style: AppText.secondary,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          key: const ValueKey('alerts-scroll'),
          padding: const EdgeInsets.fromLTRB(
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pagePadding,
            Dimens.pageBottom,
          ),
          child: StaggeredEntrance(
            key: ValueKey('alerts-entrance-$_opened'),
            gap: 0,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Title + "ยังไม่ได้อ่าน {n} รายการ". The line is a polite live region
/// that stays in the tree (empty at 0, proposed default), so TalkBack
/// also announces the change from none to one.
class _Header extends StatelessWidget {
  const _Header({super.key, required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle('แจ้งเตือน'),
        Semantics(
          key: const ValueKey('alerts-unread'),
          container: true,
          liveRegion: true,
          child: unread > 0
              ? Text('ยังไม่ได้อ่าน $unread รายการ', style: AppText.secondary)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// One alert (§7.2): the whole card is one link. Unread: `outline` border
/// and the "ใหม่" chip.
class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});

  final StoredAlert alert;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final a = alert;
    final nav = Navigator.of(context);
    Future<void> markRead() => ref
        .read(alertRepositoryProvider)
        .markRead(a.id, ref.read(clockProvider)().millisecondsSinceEpoch);
    switch (targetOf(a.kind)) {
      case AlertTarget.detail:
        // The detail marks it read when it opens.
        await nav.pushNamed(Routes.alertDetail, arguments: a.id);
      case AlertTarget.connection:
        await markRead();
        await nav.pushNamed(Routes.connection);
      case AlertTarget.footCheckFound:
        await markRead();
        await nav.pushNamed(Routes.footCheckFound, arguments: a.footCheckId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = alert;
    final look = lookOf(a.kind);
    final copy = copyOf(a);
    final source = sourceLineOf(a);
    final unread = !a.isRead;
    return Semantics(
      button: true,
      label: cardLabel(a),
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('alert-card-${a.id}'),
          borderRadius: BorderRadius.circular(Dimens.radiusCard),
          onTap: () => _open(context, ref),
          child: AppCard(
            emphasised: unread,
            padding: const EdgeInsets.all(Dimens.smallCardPadding),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Dimens.tightGap,
                        runSpacing: Dimens.tightGap,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusTag(
                            palette: look.palette,
                            icon: look.icon,
                            label: look.tag,
                          ),
                          Text(hhmm(localTimeOf(a)), style: AppText.secondary),
                          if (unread) const NewChip(),
                        ],
                      ),
                      const SizedBox(height: Dimens.tightGap),
                      Text(copy.title, style: AppText.bodyStrong),
                      if (source != null) ...[
                        const SizedBox(height: Dimens.tightGap),
                        Text(source, style: AppText.secondary),
                      ],
                      const SizedBox(height: Dimens.tightGap),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'ควรทำ: ',
                              style: AppText.labelStrong.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: copy.todo,
                              style: AppText.secondary.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dimens.buttonGap),
                const Icon(
                  LucideIcons.chevron_right,
                  size: Dimens.iconButtonIcon,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that arrived while the list is shown: opens (height + fade,
/// `enter`) and slides down from [Motion.newRowSlide] above. Under reduce
/// motion it is simply there.
class _NewRow extends StatefulWidget {
  const _NewRow({required this.child});

  final Widget child;

  @override
  State<_NewRow> createState() => _NewRowState();
}

class _NewRowState extends State<_NewRow> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Motion.enterDuration,
  );
  late final _curve = CurvedAnimation(parent: _controller, curve: Motion.enter);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -Motion.newRowSlide * (1 - _curve.value)),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Empty state (§7.2): 88 `primarySoft` circle with the bell, title and
/// line, centred, 72 below the header.
class _Empty extends StatelessWidget {
  const _Empty({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.sectionGap + Dimens.emptyTop),
      child: Column(
        children: [
          Container(
            width: Dimens.emptyCircle,
            height: Dimens.emptyCircle,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.bell,
              size: Dimens.emptyIcon,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: Dimens.cardGap),
          const Text(
            'ยังไม่มีการแจ้งเตือน',
            style: AppText.emptyTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Dimens.tightGap),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Dimens.emptyTextMaxWidth,
            ),
            child: Text(
              'เมื่อแอปพบเรื่องที่ควรระวัง จะแสดงที่นี่ '
              'พร้อมคำแนะนำว่าควรทำอะไร',
              style: AppText.body.copyWith(color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
