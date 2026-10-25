import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// One row of numbers: label 16 `inkMuted` over value 16/600 `ink`.
class DetailRow {
  const DetailRow(this.label, this.value);

  final String label;
  final String value;
}

/// "ดูตัวเลขละเอียด" (DESIGN-SPEC §5): a white card whose header button
/// shows or hides the numbers. Plain Thai comes first on every screen; the
/// numbers live here (user decision).
///
/// - Closed each time its screen opens (proposed default, §14).
/// - The chevron turns 180° (`chevron`); the rows appear without a height
///   animation (§12.2). Under reduce motion the chevron jumps.
/// - TalkBack hears the expanded / collapsed state (§13).
class DetailsExpander extends StatefulWidget {
  const DetailsExpander({
    super.key,
    required this.rows,
    this.leading,
    this.trailing = const [],
  });

  final List<DetailRow> rows;

  /// Shown above [rows] while open (My feet's kPa table, §8.1).
  final Widget? leading;

  /// Shown below [rows] while open, each on a `divider` top border (the
  /// Gait tab's class probabilities and CoP, §8.3).
  final List<Widget> trailing;

  @override
  State<DetailsExpander> createState() => _DetailsExpanderState();
}

class _DetailsExpanderState extends State<DetailsExpander> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final label = _open ? 'ซ่อนตัวเลขละเอียด' : 'ดูตัวเลขละเอียด';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: label,
            excludeSemantics: true,
            onTap: _toggle,
            child: InkWell(
              key: const ValueKey('details-expander'),
              borderRadius: BorderRadius.circular(Dimens.radiusCard),
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Dimens.expanderHeaderHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.expanderHeaderPaddingV,
                    horizontal: Dimens.cardPadding,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AppText.bodyStrong.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: Motion.duration(
                          context,
                          Motion.chevronDuration,
                        ),
                        curve: Motion.chevron,
                        child: const Icon(
                          LucideIcons.chevron_down,
                          size: Dimens.iconButtonIcon,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.cardPadding,
                0,
                Dimens.cardPadding,
                Dimens.tightGap,
              ),
              child: Column(
                key: const ValueKey('details-rows'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?widget.leading,
                  for (final r in widget.rows) _Row(row: r),
                  for (final t in widget.trailing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: Dimens.detailRowPaddingV,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      child: t,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final DetailRow row;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Dimens.detailRowPaddingV),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.label, style: AppText.secondary),
            Text(
              row.value,
              style: AppText.labelStrong.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
