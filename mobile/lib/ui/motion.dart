import 'package:flutter/widgets.dart';

/// Every animation duration and curve in the app (FLUTTER-PLAN section 8,
/// DESIGN-SPEC section 12). Do not write a `Duration` or `Curve` for an
/// animation anywhere else.
///
/// Rule 16: when the system "reduce motion" setting is on, animations are
/// disabled. Resolve durations through [Motion.duration] so that happens
/// automatically.
abstract final class Motion {
  /// `exit`: old content fading out; collapsing.
  static const exitDuration = Duration(milliseconds: 200);

  /// cubic-bezier(0.32, 0, 0.67, 0). Not `Curves.easeInCubic`, which has
  /// different control points (DESIGN-SPEC §12.1).
  static const Curve exit = Cubic(0.32, 0.0, 0.67, 0.0);

  /// `enter`: new content in; expanding; colour changes; dot fill and size.
  static const enterDuration = Duration(milliseconds: 300);

  /// cubic-bezier(0.33, 1, 0.68, 1). Not `Curves.easeOutCubic`.
  static const Curve enter = Cubic(0.33, 1.0, 0.68, 1.0);

  /// `value`: numbers counting, bars, chart draw-in, photo fly.
  static const valueDuration = Duration(milliseconds: 400);
  static const Curve value = enter;

  /// `stagger`: delay per item when cards and list items rise in, and how
  /// far they rise (logical pixels). Each item uses [enter].
  static const stagger = Duration(milliseconds: 40);
  static const staggerRise = 12.0;

  /// A new alert's row on the Alerts list opens at the top (height + fade,
  /// [enter]) and slides down from this far above (logical pixels).
  static const newRowSlide = 8.0;

  /// `pop`: badge count, connected disc (scale [popFrom] → 1, overshoot).
  static const popDuration = Duration(milliseconds: 300);
  static const Curve pop = Cubic(0.34, 1.3, 0.64, 1.0);
  static const popFrom = 0.6;

  /// `pulse`: one cycle of the ring on "high" dots; the ring grows for
  /// [pulseGrow] with [enter], then waits.
  static const pulse = Duration(milliseconds: 1600);
  static const pulseGrow = Duration(milliseconds: 1400);

  /// High-dot pulse ring geometry (view-box units beyond the dot radius)
  /// and opacity; [pulseStill…] is the reduce-motion ring (§12.3).
  static const pulseFromRadius = 1.0;
  static const pulseToRadius = 12.0;
  static const pulseFromOpacity = 0.5;
  static const pulseStillRadius = 5.0;
  static const pulseStillOpacity = 0.6;

  /// `wiggle`: the bell on a new alert, degrees per step, [wiggleStep]
  /// each.
  static const wiggleStep = Duration(milliseconds: 110);
  static const wiggleDegrees = [-14.0, 12.0, -8.0, 6.0, 0.0];
  static const Curve wiggle = Curves.easeInOut;

  /// Pivot of the bell wiggle: 50 % width, 15 % height.
  static const wigglePivot = Alignment(0, -0.7);

  /// `chevron`: details-expander chevron.
  static const chevronDuration = Duration(milliseconds: 200);
  static const Curve chevron = Curves.ease;

  /// `press`: self-timer button ring.
  static const pressDuration = Duration(milliseconds: 150);
  static const Curve press = Curves.ease;

  /// My feet (§12.2): the sub-tab labels change colour over this; the new
  /// panel fades in ([enter]) this long after the old one starts fading
  /// out ([exit]).
  static const labelColorDuration = Duration(milliseconds: 200);
  static const panelEnterDelay = Duration(milliseconds: 80);

  /// Connection, searching (§12.2): a ring around the radius-20 disc grows
  /// to [rippleToRadius] while fading from [rippleFromOpacity] to 0, one
  /// [pulse] cycle each. Reduce motion shows two still rings (§12.3).
  static const rippleFromRadius = 20.0;
  static const rippleToRadius = 31.0;
  static const rippleFromOpacity = 0.6;
  static const rippleStill = [
    (radius: 24.0, opacity: 0.5),
    (radius: 30.0, opacity: 0.25),
  ];

  /// Connection, connected: after the disc's [pop], the check stroke draws
  /// ([enter]) starting this long after the pop starts.
  static const checkDrawDelay = Duration(milliseconds: 120);

  /// Connection: "เสร็จแล้ว กลับหน้าวันนี้" fades in ([enter]) after this.
  static const doneButtonDelay = Duration(milliseconds: 200);

  /// Home status change: the new icon scales from this to 1.
  static const statusIconFrom = 0.85;

  /// True when the system asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [base], or [Duration.zero] when reduced motion is on.
  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}
