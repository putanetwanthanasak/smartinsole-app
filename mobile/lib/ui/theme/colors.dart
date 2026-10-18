import 'package:flutter/painting.dart';

/// Colour tokens from docs/design/DESIGN-SPEC.md section 1.
///
/// Only colours live here. Pressure kPa boundaries that pick between the
/// foot-dot colours come from shared/thresholds.json (rule 12), never from
/// this file.
abstract final class AppColors {
  static const bg = Color(0xFFF2F7F8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF12303A);
  static const inkMuted = Color(0xFF4A626B);
  static const inkSoft = Color(0xFF33505A);
  static const primary = Color(0xFF0A6A87);
  static const primarySoft = Color(0xFFDDF0F4);
  static const info = Color(0xFFE6F2F5);
  static const border = Color(0xFFDCE6E9);
  static const outlineBtn = Color(0xFF9FC3CE);

  /// Alerts tab count badge (DESIGN-SPEC section 4).
  static const badge = Color(0xFFB42318);

  /// Left/right foot button status dot (DESIGN-SPEC section 5).
  static const deviceConnected = Color(0xFF2E7D4F);
  static const deviceDisconnected = Color(0xFF8A9AA1);
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

/// Foot-map pressure dots: differ in both hue and lightness.
abstract final class FootDotColors {
  static const low = Color(0xFFBFE2EB);
  static const medium = Color(0xFFF0B340);
  static const high = Color(0xFFC2410C);
  static const noData = Color(0xFFD3DDE1);
}

/// Daily foot check camera screen.
abstract final class CameraColors {
  static const background = Color(0xFF0F1D22);
  static const viewfinder = Color(0xFF22353B);
  static const guideOutline = Color(0xFF7FD3E3);
  static const textSecondary = Color(0xFFC9DCE1);
}
