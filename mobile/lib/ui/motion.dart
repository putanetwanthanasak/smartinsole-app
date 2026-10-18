import 'package:flutter/widgets.dart';

/// Every animation duration and curve in the app (FLUTTER-PLAN section 8,
/// DESIGN-SPEC section 7). Do not write a `Duration` or `Curve` for an
/// animation anywhere else.
///
/// Rule 16: when the system "reduce motion" setting is on, animations are
/// disabled. Resolve durations through [Motion.duration] so that happens
/// automatically.
abstract final class Motion {
  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 300);
  static const long = Duration(milliseconds: 400);

  /// One cycle of the slow pulse ring on "high" foot dots.
  static const pulse = Duration(milliseconds: 1600);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// True when the system asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [base], or [Duration.zero] when reduced motion is on.
  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}
