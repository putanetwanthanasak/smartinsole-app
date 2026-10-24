import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'app_shell.dart';

class BottomBarItem {
  const BottomBarItem({
    required this.tab,
    required this.icon,
    required this.label,
  });

  final AppTab tab;
  final IconData icon;
  final String label;
}

/// Screen-reader label of the Alerts tab (DESIGN-SPEC §4): carries the
/// unread count, because the badge itself is hidden from screen readers.
String alertsTabLabel(String label, int unread) =>
    unread > 0 ? '$label มี $unread รายการที่ยังไม่ได้อ่าน' : label;

/// Bottom bar per DESIGN-SPEC §4: at least 80 high (it grows with large
/// text rather than clipping), white, `divider` top border, padding 8;
/// selected icon in a 64×32 `primarySoft` pill, label `primary` 16/700.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.items,
    required this.selected,
    required this.unreadAlerts,
    required this.onSelect,
  });

  final List<BottomBarItem> items;
  final AppTab selected;

  /// Unread alerts: the badge count; hidden at 0.
  final int unreadAlerts;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.bottomBarHeight),
          child: Padding(
            padding: const EdgeInsets.all(Dimens.bottomBarPadding),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    Expanded(
                      child: _TabButton(
                        key: ValueKey('tab-${item.tab.name}'),
                        item: item,
                        selected: item.tab == selected,
                        badge: item.tab == AppTab.alerts ? unreadAlerts : 0,
                        onTap: () => onSelect(item.tab),
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

class _TabButton extends StatefulWidget {
  const _TabButton({
    super.key,
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final BottomBarItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

/// A new alert (the badge count goes up): the bell wiggles and the badge
/// pops (DESIGN-SPEC §12.2). Neither plays under reduce motion.
class _TabButtonState extends State<_TabButton> with TickerProviderStateMixin {
  late final _wiggle = AnimationController(
    vsync: this,
    duration: Motion.wiggleStep * Motion.wiggleDegrees.length,
  );
  late final _pop = AnimationController(
    vsync: this,
    duration: Motion.popDuration,
    value: 1,
  );
  late final _popCurve = CurvedAnimation(parent: _pop, curve: Motion.pop);
  late final _popScale = _popCurve.drive(
    Tween(begin: Motion.popFrom, end: 1.0),
  );

  @override
  void didUpdateWidget(_TabButton old) {
    super.didUpdateWidget(old);
    if (widget.badge > old.badge && !Motion.reduced(context)) {
      _wiggle.forward(from: 0);
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    _popCurve.dispose();
    _pop.dispose();
    super.dispose();
  }

  /// Bell angle in radians at wiggle progress [t]: −14°, 12°, −8°, 6°, 0°,
  /// one step each, eased within the step.
  static double _angle(double t) {
    const steps = Motion.wiggleDegrees;
    if (t <= 0 || t >= 1) return 0;
    final pos = t * steps.length;
    final i = pos.floor();
    final from = i == 0 ? 0.0 : steps[i - 1];
    final to = steps[i];
    final deg = from + (to - from) * Motion.wiggle.transform(pos - i);
    return deg * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final color = selected ? AppColors.primary : AppColors.inkMuted;
    final label = item.tab == AppTab.alerts
        ? alertsTabLabel(item.label, widget.badge)
        : item.label;

    Widget icon = Icon(item.icon, size: Dimens.iconButtonIcon, color: color);
    if (item.tab == AppTab.alerts) {
      icon = AnimatedBuilder(
        animation: _wiggle,
        builder: (context, child) => Transform.rotate(
          angle: _angle(_wiggle.value),
          alignment: Motion.wigglePivot,
          child: child,
        ),
        child: icon,
      );
    }

    // excludeSemantics also drops the InkWell's tap action, so the tap is
    // given to TalkBack here.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouchTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: Motion.duration(context, Motion.enterDuration),
                    curve: Motion.enter,
                    width: Dimens.tabPillWidth,
                    height: Dimens.tabPillHeight,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primarySoft
                          : AppColors.primarySoft.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(
                        Dimens.tabPillHeight / 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: icon,
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      top: Dimens.badgeTop,
                      right: Dimens.badgeRight,
                      child: ScaleTransition(
                        scale: _popScale,
                        child: _Badge(count: widget.badge),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Dimens.textGap),
              Text(
                item.label,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unread count: min 24×24, radius 12, `badge` fill, 2 px white ring,
/// 14/700 white. Hidden from screen readers (the tab label carries it).
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('alerts-badge'),
        constraints: const BoxConstraints(
          minWidth: Dimens.badgeSize,
          minHeight: Dimens.badgeSize,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Dimens.textGap),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.badge,
          borderRadius: BorderRadius.circular(Dimens.badgeSize / 2),
          border: Border.all(color: AppColors.surface, width: Dimens.badgeRing),
        ),
        child: Text('$count', style: AppText.badge),
      ),
    );
  }
}
