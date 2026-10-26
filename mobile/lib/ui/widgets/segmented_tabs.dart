import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// One option of [SegmentedTabs].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    required this.key,
  });

  final T value;
  final String label;
  final Key key;
}

/// Segmented control used as sub-tabs (DESIGN-SPEC §5, §8): white frame,
/// `outline` 1.5 px, radius 16, padding 4, gap 4; options min height 48,
/// radius 12, labels 18. A sliding `primary` indicator moves to the
/// selected option (`enter`) and the labels change colour over 200 ms
/// (§12.2); both are instant under reduce motion.
///
/// Screen readers get a tab list named [semanticLabel] whose options are
/// tabs with a selected state (§13).
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.semanticLabel,
    this.radio = false,
    this.small = false,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final String semanticLabel;

  /// Screen readers hear a radio group instead of tabs (Foot check's view
  /// picker "รูปที่ดู", §11.3 and §13).
  final bool radio;

  /// Option labels 16 instead of 18 (§11.3: four options in one row).
  final bool small;

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.value == selected);
    final slide = Motion.duration(context, Motion.enterDuration);
    final fade = Motion.duration(context, Motion.labelColorDuration);
    const gap = Dimens.segmentPadding;
    final radius = BorderRadius.circular(Dimens.radiusInner);
    return Semantics(
      role: radio ? SemanticsRole.radioGroup : SemanticsRole.tabBar,
      label: semanticLabel,
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(Dimens.segmentPadding),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Dimens.radiusCard),
          border: Border.all(
            color: AppColors.outline,
            width: Dimens.outlineWidth,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final n = options.length;
            final w = (constraints.maxWidth - gap * (n - 1)) / n;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: slide,
                  curve: Motion.enter,
                  left: index * (w + gap),
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: radius,
                    ),
                  ),
                ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Expanded(
                          child: _Option(
                            option: options[i],
                            selected: i == index,
                            fade: fade,
                            radius: radius,
                            radio: radio,
                            small: small,
                            onTap: () => onSelect(options[i].value),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Option<T> extends StatelessWidget {
  const _Option({
    required this.option,
    required this.selected,
    required this.fade,
    required this.radius,
    required this.onTap,
    this.radio = false,
    this.small = false,
  });

  final SegmentOption<T> option;
  final bool selected;
  final Duration fade;
  final BorderRadius radius;
  final VoidCallback onTap;
  final bool radio;
  final bool small;

  @override
  Widget build(BuildContext context) {
    var style = selected
        ? AppText.button.copyWith(color: AppColors.surface)
        : AppText.bodyStrong;
    if (small) style = style.copyWith(fontSize: AppText.secondary.fontSize);
    return Semantics(
      role: radio ? null : SemanticsRole.tab,
      selected: radio ? null : selected,
      inMutuallyExclusiveGroup: radio ? true : null,
      checked: radio ? selected : null,
      button: true,
      label: option.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: option.key,
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouchTarget),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimens.textGap),
              child: AnimatedDefaultTextStyle(
                duration: fade,
                style: style,
                textAlign: TextAlign.center,
                child: Text(option.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
