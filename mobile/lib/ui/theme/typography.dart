import 'package:flutter/painting.dart';

import 'colors.dart';

/// Type scale from docs/design/DESIGN-SPEC.md section 2.
///
/// Sizes are logical pixels. App and system text scaling are applied by
/// `MediaQuery.textScaler`; nothing here clamps them.
abstract final class AppFonts {
  /// Headings and big numbers (500/600/700).
  static const heading = 'PlexSansThai';

  /// Body text (400/500/600/700); looped letterforms for older readers.
  static const body = 'PlexSansThaiLooped';
}

abstract final class AppText {
  static const _lineHeight = 1.45;

  static const statusTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: _lineHeight,
    color: AppColors.ink,
  );
  static const screenTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: _lineHeight,
    color: AppColors.ink,
  );
  static const cardNumber = TextStyle(
    fontFamily: AppFonts.heading,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: _lineHeight,
    color: AppColors.ink,
  );
  static const cardTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    height: _lineHeight,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: _lineHeight,
    color: AppColors.inkSoft,
  );
  static const bodyStrong = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: _lineHeight,
    color: AppColors.ink,
  );
  static const secondary = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: _lineHeight,
    color: AppColors.inkMuted,
  );
  static const tabLabel = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: _lineHeight,
    color: AppColors.inkMuted,
  );

  /// Research capture countdown: read at arm's length while walking.
  static const captureTimer = TextStyle(
    fontFamily: AppFonts.heading,
    fontSize: 72,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const small = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: _lineHeight,
    color: AppColors.inkMuted,
  );
}
