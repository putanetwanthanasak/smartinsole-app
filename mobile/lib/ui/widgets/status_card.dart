import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../rules/patient_status.dart';
import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';

StatusPalette paletteOf(PatientLevel level) => switch (level) {
  PatientLevel.safe => StatusColors.safe,
  PatientLevel.careful => StatusColors.careful,
  PatientLevel.rest => StatusColors.rest,
  // Rule 5: never green.
  PatientLevel.noData => StatusColors.noData,
};

IconData statusIconOf(PatientLevel level) => switch (level) {
  PatientLevel.safe => LucideIcons.circle_check,
  PatientLevel.careful => LucideIcons.triangle_alert,
  PatientLevel.rest => LucideIcons.octagon_alert,
  PatientLevel.noData => LucideIcons.bluetooth_off,
};

/// Status card (DESIGN-SPEC §5, §6 item 3): status background, radius 20,
/// padding 24; icon in a 56 white circle; title; detail; optional advice
/// box and action. A polite live region, so TalkBack reads a new status.
///
/// Motion (§12.2): the background cross-fades (`enter`); title, detail and
/// icon fade out (`exit`) and the new ones fade in (`enter`, the icon
/// scaling 0.85 → 1); the advice box and the action expand (`enter`) or
/// collapse (`exit`).
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.level,
    required this.title,
    required this.detail,
    this.advice,
    this.action,
  });

  final PatientLevel level;
  final String title;
  final String detail;
  final String? advice;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(level);
    final enter = Motion.duration(context, Motion.enterDuration);
    final exit = Motion.duration(context, Motion.exitDuration);
    // Fade out, then fade in: the incoming child waits for the exit.
    final swap = exit + enter;
    final inCurve = swap == Duration.zero
        ? Motion.enter
        : Interval(
            exit.inMicroseconds / swap.inMicroseconds,
            1,
            curve: Motion.enter,
          );

    return Semantics(
      container: true,
      liveRegion: true,
      child: AnimatedContainer(
        duration: enter,
        curve: Motion.enter,
        padding: const EdgeInsets.all(Dimens.cardPadding),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(Dimens.radiusStatusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: swap,
              reverseDuration: exit,
              switchInCurve: inCurve,
              switchOutCurve: Motion.exit,
              layoutBuilder: _topLeft,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(
                    begin: Motion.statusIconFrom,
                    end: 1.0,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: _IconCircle(
                key: ValueKey(level),
                icon: statusIconOf(level),
                color: palette.icon,
              ),
            ),
            const SizedBox(height: Dimens.tightGap),
            AnimatedSwitcher(
              duration: swap,
              reverseDuration: exit,
              switchInCurve: inCurve,
              switchOutCurve: Motion.exit,
              layoutBuilder: _topLeft,
              child: Column(
                key: ValueKey((title, detail)),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppText.statusTitle.copyWith(color: palette.text),
                    ),
                  ),
                  const SizedBox(height: Dimens.tightGap),
                  Text(
                    detail,
                    style: AppText.body.copyWith(color: palette.text),
                  ),
                ],
              ),
            ),
            _Expanding(
              enter: enter,
              exit: exit,
              child: advice == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: Dimens.cardGap),
                      child: _AdviceBox(advice: advice!),
                    ),
            ),
            _Expanding(
              enter: enter,
              exit: exit,
              child: action == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: Dimens.cardGap),
                      child: action,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _topLeft(Widget? current, List<Widget> previous) => Stack(
    alignment: AlignmentDirectional.topStart,
    children: [...previous, ?current],
  );
}

/// Expands when [child] appears (`enter`), collapses when it goes (`exit`).
class _Expanding extends StatelessWidget {
  const _Expanding({required this.enter, required this.exit, this.child});

  final Duration enter;
  final Duration exit;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final body = child ?? const SizedBox(width: double.infinity);
    // Reduce motion: no AnimatedSize at all. With a zero duration it
    // finishes inside its own layout and asserts (found in S6B part 2).
    if (enter == Duration.zero && exit == Duration.zero) return body;
    return AnimatedSize(
      duration: enter,
      reverseDuration: exit,
      curve: child == null ? Motion.exit : Motion.enter,
      alignment: Alignment.topCenter,
      child: body,
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Dimens.statusIconCircle,
      height: Dimens.statusIconCircle,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: Dimens.statusIcon, color: color),
    );
  }
}

/// "สิ่งที่ควรทำตอนนี้" box: white, radius 12, padding 16.
class _AdviceBox extends StatelessWidget {
  const _AdviceBox({required this.advice});

  final String advice;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimens.smallCardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'สิ่งที่ควรทำตอนนี้',
            style: AppText.labelStrong.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Dimens.textGap),
          Text(advice, style: AppText.body),
        ],
      ),
    );
  }
}
