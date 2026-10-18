import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import 'colors.dart';
import 'dimens.dart';
import 'typography.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.surface,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.primary,
      onSecondary: AppColors.surface,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.outlineBtn,
      outlineVariant: AppColors.border,
      error: Color(0xFFB42318),
      onError: AppColors.surface,
    );

    const pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        headlineMedium: AppText.screenTitle,
        headlineSmall: AppText.statusTitle,
        titleLarge: AppText.cardTitle,
        titleMedium: AppText.bodyStrong,
        bodyLarge: AppText.body,
        bodyMedium: AppText.secondary,
        bodySmall: AppText.small,
        labelLarge: AppText.bodyStrong,
        labelMedium: AppText.tabLabel,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Aligns titles with the page padding used by card content.
        titleSpacing: Dimens.pagePadding,
        titleTextStyle: AppText.screenTitle,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(Dimens.radiusCardLarge),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          minimumSize: const Size.fromHeight(Dimens.buttonPrimaryHeight),
          shape: pill,
          textStyle: AppText.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(Dimens.buttonSecondaryHeight),
          shape: pill,
          side: const BorderSide(color: AppColors.outlineBtn, width: 1.5),
          textStyle: AppText.bodyStrong,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.square(Dimens.minTouchTarget),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _ReducibleTransitionsBuilder(
            SharedAxisPageTransitionsBuilder(
              transitionType: SharedAxisTransitionType.horizontal,
            ),
          ),
        },
      ),
    );
  }
}

/// Wraps a page transition so it is skipped entirely when the system asks
/// for reduced motion (rule 16).
class _ReducibleTransitionsBuilder extends PageTransitionsBuilder {
  const _ReducibleTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    return inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
