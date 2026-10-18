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

/// Bottom bar per DESIGN-SPEC section 4: height 80, selected icon in a
/// 56×30 `primarySoft` pill, selected label `primary` / 700.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.items,
    required this.selected,
    required this.alertCount,
    required this.onSelect,
  });

  final List<BottomBarItem> items;
  final AppTab selected;

  /// Count shown on the alerts tab badge; hidden at 0.
  final int alertCount;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Dimens.bottomBarHeight,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _TabButton(
                    item: item,
                    selected: item.tab == selected,
                    badge: item.tab == AppTab.alerts ? alertCount : 0,
                    onTap: () => onSelect(item.tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.duration(context, Motion.short),
              curve: Motion.enter,
              width: Dimens.tabPillWidth,
              height: Dimens.tabPillHeight,
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(Dimens.tabPillHeight / 2),
              ),
              child: Badge(
                isLabelVisible: badge > 0,
                backgroundColor: AppColors.badge,
                label: Text('$badge'),
                child: Icon(item.icon, size: 24, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppText.tabLabel.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
