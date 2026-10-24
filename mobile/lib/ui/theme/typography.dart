import 'package:flutter/painting.dart';

import 'colors.dart';

/// Style D type scale from docs/design/DESIGN-SPEC.md section 2.
///
/// Sizes are logical pixels. App and system text scaling are applied by
/// `MediaQuery.textScaler`; nothing here clamps them. Nothing is smaller
/// than 16 except the badge count.
abstract final class AppFonts {
  /// Headings and big numbers (600/700): Figtree for Latin digits and
  /// symbols, Noto Sans Thai for Thai glyphs.
  static const heading = 'Figtree';
  static const headingFallback = ['NotoSansThai'];

  /// Body text (400–700): Noto Sans, with Noto Sans Thai Looped for Thai
  /// glyphs (looped letterforms read better for older users). Figtree last:
  /// it has the few symbols Noto Sans lacks ("→", "≥").
  static const body = 'NotoSans';
  static const bodyFallback = ['NotoSansThaiLooped', 'Figtree'];
}

abstract final class AppText {
  static const _headingHeight = 1.3;
  static const _bodyHeight = 1.5;

  /// Numbers that change use tabular figures so they do not jump.
  static const _tabular = [FontFeature.tabularFigures()];

  /// Countdown digits (research capture timer, camera self-timer): read at
  /// arm's length.
  static const countdown = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 72,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  /// ΔT, balance and other big changing numbers.
  static const bigNumber = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: _headingHeight,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  /// Home status title.
  static const statusTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: _headingHeight,
    color: AppColors.ink,
  );

  /// Page title, greeting.
  static const pageTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: _headingHeight,
    color: AppColors.ink,
  );

  /// Empty-state title (Alerts empty, "no gait result").
  static const emptyTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: _headingHeight,
    color: AppColors.ink,
  );

  /// The number in a numbered-step circle.
  static const stepNumber = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  /// Card title (h2).
  static const cardTitle = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: _headingHeight,
    color: AppColors.ink,
  );

  /// Badge count: the only text below 16.
  static const badge = TextStyle(
    fontFamily: AppFonts.heading,
    fontFamilyFallback: AppFonts.headingFallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: AppColors.surface,
    fontFeatures: _tabular,
  );

  /// Main body, status detail, advice.
  static const body = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: _bodyHeight,
    color: AppColors.ink,
  );

  /// Numbered-step text (DESIGN-SPEC §5: line height 1.55).
  static const step = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.ink,
  );

  /// List-row and chip titles.
  static const bodyStrong = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: _bodyHeight,
    color: AppColors.ink,
  );

  /// Button labels.
  static const button = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: _bodyHeight,
    color: AppColors.ink,
  );

  /// Secondary text.
  static const secondary = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: _bodyHeight,
    color: AppColors.inkMuted,
  );

  /// Labels and tab labels.
  static const label = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: _bodyHeight,
    color: AppColors.inkMuted,
  );

  /// Small headings inside cards, captions, notes, links.
  static const labelStrong = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: _bodyHeight,
    color: AppColors.ink,
  );
}
