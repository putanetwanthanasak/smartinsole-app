import 'package:flutter/painting.dart';

/// Size, spacing and radius tokens from docs/design/DESIGN-SPEC.md section 3.
abstract final class Dimens {
  static const pagePadding = 20.0;
  static const cardGap = 14.0;
  static const cardPadding = 18.0;

  static const radiusCardLarge = 24.0;
  static const radiusCardSmall = 20.0;
  static const radiusTip = 16.0;

  static const minTouchTarget = 48.0;
  static const buttonPrimaryHeight = 56.0;
  static const buttonSecondaryHeight = 52.0;
  static const answerChoiceHeight = 44.0;

  static const bottomBarHeight = 80.0;
  static const tabPillWidth = 56.0;
  static const tabPillHeight = 30.0;

  static const footButtonHeight = 48.0;
  static const footCheckIconCircle = 44.0;
  static const footCheckBorderWidth = 1.5;

  /// Shadow is only for floating buttons; cards have none.
  static const floatingShadow = [
    BoxShadow(
      color: Color(0x1F12303A), // rgba(18,48,58,0.12)
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];
}
