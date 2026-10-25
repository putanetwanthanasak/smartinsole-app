import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../motion.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/buttons.dart';
import 'connection_model.dart';

/// Sizes on the Connection screen (DESIGN-SPEC §9).
abstract final class ConnectDimens {
  static const visual = 64.0;
  static const circle = 48.0;
  static const circleIcon = 24.0;
  static const disc = 40.0; // radius 20
  static const connectedDisc = 44.0; // radius 22
  static const ringWidth = 2.0;
  static const cardPadding = 20.0;
  static const progressHeight = 8.0;
  static const progressRadius = 4.0;
  static const panelPadding = 20.0;
  static const panelTitle = 20.0;
  static const notFoundNumber = 24.0;
}

/// One foot's card (§9): white, radius 16, padding 20, gap 16; `divider`
/// only when connected or waiting for Bluetooth, `outline` otherwise; a
/// polite live region.
class FootConnectionCard extends StatelessWidget {
  const FootConnectionCard({
    super.key,
    required this.card,
    required this.onFind,
    required this.onStop,
    required this.onDisconnect,
    required this.onReconnect,
  });

  final FootCardState card;
  final VoidCallback onFind;
  final VoidCallback onStop;
  final VoidCallback onDisconnect;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final quiet = switch (card.kind) {
      CardKind.connected ||
      CardKind.bluetoothOff ||
      CardKind.waitingPermission => true,
      _ => false,
    };
    final message = _message();
    final button = _button();
    final line = card.kind == CardKind.connected
        ? ConnectionCopy.connectedLine(card)
        : null;
    final side = card.side.name;
    return DecoratedBox(
      key: ValueKey('connect-card-$side'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        border: quiet
            ? Border.all(color: AppColors.divider)
            : Border.all(color: AppColors.outline, width: Dimens.outlineWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ConnectDimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              container: true,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: ConnectDimens.visual,
                    child: Center(child: _Visual(kind: card.kind)),
                  ),
                  const SizedBox(width: Dimens.cardGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ConnectionCopy.foot(card.side),
                          style: AppText.emptyTitle,
                        ),
                        Text(
                          ConnectionCopy.status(card),
                          key: ValueKey('connect-status-$side'),
                          style: AppText.labelStrong.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _statusColor(card.kind),
                          ),
                        ),
                        if (line != null)
                          _ConnectedLine(
                            text: line,
                            low: card.lowBattery,
                            key: ValueKey('connect-line-$side'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: Dimens.cardGap),
              message,
            ],
            if (button != null) ...[
              const SizedBox(height: Dimens.cardGap),
              button,
            ],
          ],
        ),
      ),
    );
  }

  static Color _statusColor(CardKind k) => switch (k) {
    CardKind.notConnected ||
    CardKind.bluetoothOff ||
    CardKind.waitingPermission => AppColors.inkMuted,
    CardKind.searching ||
    CardKind.connecting ||
    CardKind.connected => AppColors.ink,
    CardKind.wrongSide || CardKind.connectedNoData => StatusColors.careful.text,
    CardKind.notFound => StatusColors.noData.text,
  };

  Widget? _message() {
    final side = card.side.name;
    return switch (card.kind) {
      CardKind.connecting => Semantics(
        label: ConnectionCopy.connectingLabel,
        child: _ProgressBar(value: card.progress ?? 0),
      ),
      CardKind.wrongSide => _MessageBox(
        key: ValueKey('connect-message-$side'),
        palette: StatusColors.careful,
        child: Text(
          ConnectionCopy.wrongSideMessage(card),
          style: AppText.secondary.copyWith(color: StatusColors.careful.text),
        ),
      ),
      CardKind.notFound => _MessageBox(
        key: ValueKey('connect-message-$side'),
        palette: StatusColors.noData,
        child: _NumberedLines(
          lines: ConnectionCopy.notFoundSteps,
          color: StatusColors.noData.text,
        ),
      ),
      CardKind.connectedNoData => _MessageBox(
        key: ValueKey('connect-message-$side'),
        palette: StatusColors.careful,
        child: Text(
          ConnectionCopy.noDataMessage,
          style: AppText.secondary.copyWith(color: StatusColors.careful.text),
        ),
      ),
      _ => null,
    };
  }

  Widget? _button() {
    final key = ValueKey('connect-action-${card.side.name}');
    return switch (card.kind) {
      CardKind.notConnected => PrimaryButton(
        key: key,
        label: ConnectionCopy.connectButton(card.side),
        onPressed: onFind,
      ),
      CardKind.searching => SecondaryButton(
        key: key,
        label: ConnectionCopy.stop,
        onPressed: onStop,
      ),
      CardKind.connected => SecondaryButton(
        key: key,
        label: ConnectionCopy.disconnect,
        onPressed: onDisconnect,
      ),
      CardKind.wrongSide || CardKind.notFound => PrimaryButton(
        key: key,
        label: ConnectionCopy.searchAgain,
        onPressed: onFind,
      ),
      CardKind.connectedNoData => PrimaryButton(
        key: key,
        label: ConnectionCopy.reconnect,
        onPressed: onReconnect,
      ),
      CardKind.connecting ||
      CardKind.bluetoothOff ||
      CardKind.waitingPermission => null,
    };
  }
}

/// "แบต {n}% · เฟิร์มแวร์ {version}", in the low-battery style (§5,
/// decision 10) when low.
class _ConnectedLine extends StatelessWidget {
  const _ConnectedLine({super.key, required this.text, required this.low});

  final String text;
  final bool low;

  @override
  Widget build(BuildContext context) {
    if (!low) return Text(text, style: AppText.secondary);
    return Row(
      children: [
        Icon(
          LucideIcons.battery_low,
          size: Dimens.inlineIcon,
          color: StatusColors.careful.icon,
        ),
        const SizedBox(width: Dimens.textGap),
        Flexible(
          child: Text(
            text,
            style: AppText.secondary.copyWith(color: StatusColors.careful.text),
          ),
        ),
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({super.key, required this.palette, required this.child});

  final StatusPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusInner),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimens.smallCardPadding),
        child: child,
      ),
    );
  }
}

/// The not-found checklist: numbered, inside the No-data box.
class _NumberedLines extends StatelessWidget {
  const _NumberedLines({required this.lines, required this.color});

  final List<String> lines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppText.secondary.copyWith(color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: Dimens.tightGap),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grows with large text instead of letting the digit
                // outgrow its circle.
                Container(
                  constraints: BoxConstraints.tightFor(
                    width: MediaQuery.textScalerOf(context)
                        .scale(ConnectDimens.notFoundNumber),
                    height: MediaQuery.textScalerOf(context)
                        .scale(ConnectDimens.notFoundNumber),
                  ),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppText.stepNumber.copyWith(
                      fontSize: AppText.secondary.fontSize,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.buttonGap),
                Expanded(child: Text(lines[i], style: style)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Progress bar, 8 tall, radius 4, `primary` on `track`; follows the real
/// connect steps (§12.2).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: Motion.duration(context, Motion.enterDuration),
      curve: Motion.enter,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(ConnectDimens.progressRadius),
        child: LinearProgressIndicator(
          value: v,
          minHeight: ConnectDimens.progressHeight,
          color: AppColors.primary,
          backgroundColor: AppColors.track,
        ),
      ),
    );
  }
}

/// The 64×64 visual of a card state.
class _Visual extends StatelessWidget {
  const _Visual({required this.kind});

  final CardKind kind;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      CardKind.notConnected => const _Circle(
        fill: AppColors.track,
        icon: LucideIcons.bluetooth,
        iconColor: AppColors.inkMuted,
      ),
      CardKind.searching => const _Ripple(),
      CardKind.connecting => const _Disc(),
      CardKind.connected => const _ConnectedDisc(),
      CardKind.wrongSide || CardKind.connectedNoData => _Circle(
        fill: StatusColors.careful.background,
        icon: LucideIcons.triangle_alert,
        iconColor: StatusColors.careful.icon,
      ),
      CardKind.notFound => _Circle(
        fill: StatusColors.noData.background,
        icon: LucideIcons.search,
        iconColor: StatusColors.noData.icon,
      ),
      CardKind.bluetoothOff || CardKind.waitingPermission => _Circle(
        fill: StatusColors.noData.background,
        icon: LucideIcons.bluetooth_off,
        iconColor: StatusColors.noData.icon,
      ),
    };
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.fill,
    required this.icon,
    required this.iconColor,
  });

  final Color fill;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ConnectDimens.circle,
      height: ConnectDimens.circle,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: ConnectDimens.circleIcon, color: iconColor),
    );
  }
}

/// Radius-20 `primarySoft` disc with `bluetooth` in `primary`.
class _Disc extends StatelessWidget {
  const _Disc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ConnectDimens.disc,
      height: ConnectDimens.disc,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        LucideIcons.bluetooth,
        size: ConnectDimens.circleIcon,
        color: AppColors.primary,
      ),
    );
  }
}

/// Searching: a ring grows from radius 20 to 31 and fades 0.6 → 0, every
/// `pulse` (§12.2). Reduce motion: two still rings (§12.3).
class _Ripple extends StatefulWidget {
  const _Ripple();

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return SizedBox.square(
      dimension: ConnectDimens.visual,
      child: CustomPaint(
        painter: reduced ? const _StillRingsPainter() : _RipplePainter(_c),
        child: const Center(child: _Disc()),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static final _grow =
      Motion.pulseGrow.inMicroseconds / Motion.pulse.inMicroseconds;

  @override
  void paint(Canvas canvas, Size size) {
    final p = (t.value / _grow).clamp(0.0, 1.0);
    if (p >= 1) return;
    final e = Motion.enter.transform(p);
    final r =
        Motion.rippleFromRadius +
        (Motion.rippleToRadius - Motion.rippleFromRadius) * e;
    final opacity = Motion.rippleFromOpacity * (1 - e);
    canvas.drawCircle(
      size.center(Offset.zero),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ConnectDimens.ringWidth
        ..color = AppColors.outline.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}

class _StillRingsPainter extends CustomPainter {
  const _StillRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    for (final ring in Motion.rippleStill) {
      canvas.drawCircle(
        size.center(Offset.zero),
        ring.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ConnectDimens.ringWidth
          ..color = AppColors.outline.withValues(alpha: ring.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_StillRingsPainter old) => false;
}

/// Radius-22 `connected` disc with a white check. When a foot becomes
/// connected while the screen is open: the disc pops (0.6 → 1, `pop`),
/// then the check stroke draws (`enter`, 120 ms after the pop starts). A
/// card already connected when the screen opens shows the end state.
class _ConnectedDisc extends StatefulWidget {
  const _ConnectedDisc();

  @override
  State<_ConnectedDisc> createState() => _ConnectedDiscState();
}

class _ConnectedDiscState extends State<_ConnectedDisc>
    with SingleTickerProviderStateMixin {
  static final _total = Motion.checkDrawDelay + Motion.enterDuration;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final Animation<double> _scale = Tween(begin: Motion.popFrom, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _c,
          curve: Interval(0, _frac(Motion.popDuration), curve: Motion.pop),
        ),
      );
  late final Animation<double> _draw = CurvedAnimation(
    parent: _c,
    curve: Interval(_frac(Motion.checkDrawDelay), 1, curve: Motion.enter),
  );

  static double _frac(Duration d) => d.inMicroseconds / _total.inMicroseconds;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Animate only when this disc replaces another state on screen; the
    // card's first frame (screen just opened) shows it finished.
    final animate =
        !Motion.reduced(context) &&
        _ConnectedEntrance.of(context)?.animate == true;
    if (animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: ConnectDimens.connectedDisc,
        height: ConnectDimens.connectedDisc,
        decoration: const BoxDecoration(
          color: AppColors.connected,
          shape: BoxShape.circle,
        ),
        child: CustomPaint(painter: _CheckPainter(_draw)),
      ),
    );
  }
}

/// Tells the connected disc whether it is appearing on a live screen
/// (animate) or on the screen's first frame (end state).
class ConnectedEntrance extends InheritedWidget {
  const ConnectedEntrance({
    super.key,
    required this.animate,
    required super.child,
  });

  final bool animate;

  @override
  bool updateShouldNotify(ConnectedEntrance old) => old.animate != animate;
}

abstract final class _ConnectedEntrance {
  static ConnectedEntrance? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectedEntrance>();
}

/// Lucide `check` ("M20 6 9 17l-5-5" in a 24 box), drawn up to [t].
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _box = 24.0;
  static const _icon = 24.0;
  static const _stroke = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _icon / _box;
    final o = Offset((size.width - _icon) / 2, (size.height - _icon) / 2);
    // From the short end (bottom left) to the tip, as a hand draws it.
    final path = Path()
      ..moveTo(o.dx + 4 * s, o.dy + 12 * s)
      ..lineTo(o.dx + 9 * s, o.dy + 17 * s)
      ..lineTo(o.dx + 20 * s, o.dy + 6 * s);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.surface;
    if (t.value >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var left = total * t.value;
    for (final PathMetric m in metrics) {
      if (left <= 0) break;
      canvas.drawPath(m.extractPath(0, left.clamp(0, m.length)), paint);
      left -= m.length;
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// Bluetooth off (§9) or not permitted (draft, decision 4A): No-data
/// background, radius 16, padding 20; 44 white circle with
/// `bluetooth-off` 26 + title (20/700) + line (18) + primary button.
class PhonePanelView extends StatelessWidget {
  const PhonePanelView({
    super.key,
    required this.title,
    required this.line,
    required this.button,
    required this.buttonIcon,
    required this.onPressed,
  });

  final String title;
  final String line;
  final String button;
  final IconData? buttonIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = StatusColors.noData;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ConnectDimens.panelPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: Dimens.bannerCircle,
                  height: Dimens.bannerCircle,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.bluetooth_off,
                    size: Dimens.bannerIcon,
                    color: p.icon,
                  ),
                ),
                const SizedBox(width: Dimens.buttonGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AppText.cardTitle.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: Dimens.textGap),
                      Text(line, style: AppText.body.copyWith(color: p.text)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimens.cardGap),
            PrimaryButton(
              key: const ValueKey('phone-panel-button'),
              label: button,
              icon: buttonIcon,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}

/// "เสร็จแล้ว กลับหน้าวันนี้" fades in (`enter`, 200 ms delay).
class DoneButton extends StatefulWidget {
  const DoneButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<DoneButton> createState() => _DoneButtonState();
}

class _DoneButtonState extends State<DoneButton>
    with SingleTickerProviderStateMixin {
  static final _total = Motion.doneButtonDelay + Motion.enterDuration;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Interval(
      Motion.doneButtonDelay.inMicroseconds / _total.inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final animate =
        !Motion.reduced(context) &&
        _ConnectedEntrance.of(context)?.animate == true;
    if (animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: PrimaryButton(
        key: const ValueKey('connect-done'),
        label: ConnectionCopy.done,
        icon: LucideIcons.check,
        onPressed: widget.onPressed,
      ),
    );
  }
}
