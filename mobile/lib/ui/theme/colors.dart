import 'package:flutter/painting.dart';

/// Style D colour tokens from docs/design/DESIGN-SPEC.md section 1.
///
/// Only colours live here. Pressure kPa boundaries that pick between the
/// foot-dot levels come from shared/thresholds.json (rule 12), never from
/// this file.
abstract final class AppColors {
  /// Page background; foot-map fill; inner boxes on white cards.
  static const bg = Color(0xFFECFEFF);

  /// Cards, foot chips, settings button, bottom bar, sheets.
  static const surface = Color(0xFFFFFFFF);

  /// Primary text, headings, big numbers.
  static const ink = Color(0xFF164E63);

  /// Secondary text, inactive tabs, dot outlines.
  static const inkMuted = Color(0xFF475569);

  /// Disconnected and no-data outlines.
  static const inkSubtle = Color(0xFF64748B);

  /// Primary buttons, selected tab, links, left part of the balance bar.
  static const primary = Color(0xFF155E75);

  /// Selected-tab pill, icon circles, step-number circles.
  static const primarySoft = Color(0xFFCFFAFE);

  /// 1.5 px borders on chips, settings button, secondary buttons and
  /// emphasised cards; small card icons.
  static const outline = Color(0xFF0891B2);

  /// Card borders, nav top border, row dividers.
  static const divider = Color(0xFFA5F3FC);

  /// Empty bar tracks, chart grid lines.
  static const track = Color(0xFFE8F1F6);

  /// Right part of the balance bar.
  static const accentLight = Color(0xFF67E8F9);

  /// Foot-chip dot when connected; disconnected is a hollow [inkSubtle]
  /// ring.
  static const connected = Color(0xFF059669);

  /// Alerts count badge (white text, 2 px white ring).
  static const badge = Color(0xFF991B1B);
}

/// One patient-facing status colour set. Always shown as icon + text +
/// colour, never colour alone.
class StatusPalette {
  const StatusPalette({
    required this.background,
    required this.text,
    required this.icon,
  });

  final Color background;
  final Color text;
  final Color icon;
}

abstract final class StatusColors {
  static const safe = StatusPalette(
    background: Color(0xFFE2F2E8),
    text: Color(0xFF1B5536),
    icon: Color(0xFF2E7D4F),
  );
  static const careful = StatusPalette(
    background: Color(0xFFFFF0D2),
    text: Color(0xFF5E3E00),
    icon: Color(0xFFA86A00),
  );
  static const rest = StatusPalette(
    background: Color(0xFFFBE3DF),
    text: Color(0xFF7F1D12),
    icon: Color(0xFFB42318),
  );

  /// Must never look like [safe] (rule 5).
  static const noData = StatusPalette(
    background: Color(0xFFE9EEF0),
    text: Color(0xFF33444B),
    icon: Color(0xFF55666E),
  );
}

/// How one foot-map dot level is drawn (DESIGN-SPEC §1). Levels differ in
/// hue, lightness and size.
class FootDotStyle {
  const FootDotStyle({
    required this.fill,
    required this.radius,
    required this.legendRadius,
    this.dashed = false,
  });

  final Color fill;

  /// In foot view-box units (120-wide foot).
  final double radius;

  /// Legend dot radius, logical pixels.
  final double legendRadius;

  /// No-data dots have a dashed [AppColors.inkSubtle] outline instead of
  /// the solid [AppColors.inkMuted] one.
  final bool dashed;

  Color get outline => dashed ? AppColors.inkSubtle : AppColors.inkMuted;

  static FootDotStyle lerp(FootDotStyle a, FootDotStyle b, double t) =>
      FootDotStyle(
        fill: Color.lerp(a.fill, b.fill, t)!,
        radius: a.radius + (b.radius - a.radius) * t,
        legendRadius: b.legendRadius,
        dashed: t < 0.5 ? a.dashed : b.dashed,
      );

  @override
  bool operator ==(Object other) =>
      other is FootDotStyle &&
      other.fill == fill &&
      other.radius == radius &&
      other.dashed == dashed;

  @override
  int get hashCode => Object.hash(fill, radius, dashed);
}

abstract final class FootDotColors {
  static const low = FootDotStyle(
    fill: Color(0xFFBFE2EB),
    radius: 8,
    legendRadius: 5,
  );
  static const medium = FootDotStyle(
    fill: Color(0xFFF0B340),
    radius: 11,
    legendRadius: 7,
  );
  static const high = FootDotStyle(
    fill: Color(0xFFC2410C),
    radius: 14,
    legendRadius: 9,
  );
  static const noData = FootDotStyle(
    fill: Color(0xFFFFFFFF),
    radius: 10,
    legendRadius: 7,
    dashed: true,
  );

  /// Dot outline width, view-box units; legend outline, logical pixels.
  static const outlineWidth = 2.0;
  static const legendOutlineWidth = 1.5;

  /// The "high" pulse ring (DESIGN-SPEC §12.2).
  static const pulseRing = Color(0xFFC2410C);
  static const pulseRingWidth = 2.5;
}

/// Daily foot check camera screen (DESIGN-SPEC §1).
abstract final class CameraColors {
  static const background = Color(0xFF0F1D22);
  static const viewfinder = Color(0xFF22353B);
  static const guide = Color(0xFF7FD3E3);
  static const text2 = Color(0xFFC9DCE1);
  static const chipText = Color(0xFFE3F1F4);
  static const slotDone = Color(0xFF33505A);
  static const slotTodo = Color(0xFF4A6670);
}
