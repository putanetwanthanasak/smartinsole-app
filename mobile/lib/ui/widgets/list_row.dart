import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

/// A Settings group (DESIGN-SPEC §10.1): label 16/700 `inkMuted`, 8 above
/// a card whose rows are split by `divider` lines.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            style: AppText.label.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: Dimens.tightGap),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Dimens.radiusCard),
            border: Border.all(color: AppColors.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Dimens.radiusCard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: Dimens.dividerWidth,
                      thickness: Dimens.dividerWidth,
                      color: AppColors.divider,
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The colours of a row's icon circle, title and chevron. [destructive]
/// rows use the Rest-your-feet colours (§10.1 "ลบรูปถ่ายเท้าทั้งหมด").
class RowTone {
  const RowTone({
    required this.circle,
    required this.icon,
    required this.title,
    required this.chevron,
  });

  static const normal = RowTone(
    circle: AppColors.primarySoft,
    icon: AppColors.primary,
    title: AppColors.ink,
    chevron: AppColors.ink,
  );
  static final destructive = RowTone(
    circle: StatusColors.rest.background,
    icon: StatusColors.rest.icon,
    title: StatusColors.rest.text,
    chevron: StatusColors.rest.text,
  );
  static final locked = RowTone(
    circle: StatusColors.noData.background,
    icon: StatusColors.noData.icon,
    title: AppColors.ink,
    chevron: AppColors.ink,
  );

  final Color circle;
  final Color icon;
  final Color title;
  final Color chevron;
}

/// List row (DESIGN-SPEC §5): min height 72, padding 12 16, gap 16; a 40
/// circle with a 22 px icon; title 18/600 over value 16 `inkMuted`;
/// `chevron-right` 22 when it opens something ([onTap]), or a [trailing]
/// widget (a switch) instead.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.trailing,
    this.tone = RowTone.normal,
    this.chevron = true,
    this.valueKey,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final RowTone tone;

  /// Shows `chevron-right` when the row opens something.
  final bool chevron;

  /// Key on the value text, for tests.
  final Key? valueKey;

  /// Above this text scale a [trailing] switch goes under the title
  /// instead of squeezing it (the same breakpoint as Home and My feet).
  static const stackAboveScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final stacked =
        trailing != null &&
        MediaQuery.textScalerOf(context).scale(1) > stackAboveScale;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Dimens.listRowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Dimens.smallCardPadding,
          vertical: Dimens.buttonGap,
        ),
        child: Row(
          children: [
            Container(
              width: Dimens.listRowCircle,
              height: Dimens.listRowCircle,
              decoration: BoxDecoration(
                color: tone.circle,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: Dimens.listRowIcon, color: tone.icon),
            ),
            const SizedBox(width: Dimens.cardGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.bodyStrong.copyWith(color: tone.title),
                  ),
                  if (value != null)
                    Text(value!, key: valueKey, style: AppText.secondary),
                  if (stacked) ...[
                    const SizedBox(height: Dimens.tightGap),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (stacked)
              const SizedBox.shrink()
            else if (trailing != null) ...[
              const SizedBox(width: Dimens.buttonGap),
              trailing!,
            ] else if (onTap != null && chevron) ...[
              const SizedBox(width: Dimens.buttonGap),
              Icon(
                LucideIcons.chevron_right,
                size: Dimens.listRowIcon,
                color: tone.chevron,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Switch (DESIGN-SPEC §5): the state word 16/700 left of a 52×32 track,
/// radius 16. On: "เปิด", `primary` track, 24 white knob on the right. Off
/// (§14 proposed default, S8B): "ปิด", knob on the left, `track` fill with
/// a 2 px `inkSubtle` border; the knob is `inkSubtle` so it shows on the
/// light track. Exposes on/off to screen readers.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// The row title, for the screen reader ("เสียงแจ้งเตือน").
  final String label;

  static const _width = 52.0;
  static const _height = 32.0;
  static const _knob = 24.0;
  static const _offBorder = 2.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimens.radiusInner),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dimens.minTouchTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value ? 'เปิด' : 'ปิด',
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color: value ? AppColors.ink : AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: Dimens.tightGap),
              Container(
                width: _width,
                height: _height,
                padding: const EdgeInsets.all((_height - _knob) / 2),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? AppColors.primary : AppColors.track,
                  borderRadius: BorderRadius.circular(_height / 2),
                  border: value
                      ? null
                      : Border.all(
                          color: AppColors.inkSubtle,
                          width: _offBorder,
                        ),
                ),
                child: Container(
                  width: _knob - (value ? 0 : _offBorder * 2),
                  height: _knob - (value ? 0 : _offBorder * 2),
                  decoration: BoxDecoration(
                    color: value ? AppColors.surface : AppColors.inkSubtle,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
