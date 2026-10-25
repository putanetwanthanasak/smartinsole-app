import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ble/packets.dart';
import '../../config/foot_layout.dart';
import '../../rules/pressure_level.dart';
import '../motion.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';

/// The dot style of a pressure level, or the no-data style.
FootDotStyle dotStyleOf(PressureLevel? level) => switch (level) {
  PressureLevel.low => FootDotColors.low,
  PressureLevel.medium => FootDotColors.medium,
  PressureLevel.high => FootDotColors.high,
  null => FootDotColors.noData,
};

/// One foot, top view, with a dot per zone (DESIGN-SPEC §1, §5).
///
/// Dots tween fill and size with `enter` when their level changes; the
/// tween retargets from wherever it is, so 10 Hz updates never restart it.
/// "High" dots get the `pulse` ring, painted on its own layer so the pulse
/// keeps its rhythm whatever the data does; under reduce motion the ring
/// is still (§12.3). The whole map is one screen-reader image with
/// [semanticLabel].
///
/// The alert detail (§7.3) draws a past moment: [ringChannel] rings the
/// zone that triggered, [pulse] is off, and a null entry in [levels] is a
/// zone whose level was not recorded (a plain outline circle).
///
/// On My feet a foot with no data also gets a dashed `inkSubtle` outline
/// ([dashOutlineWhenNoData], §5); Home keeps the solid outline.
class FootMap extends StatelessWidget {
  const FootMap({
    super.key,
    required this.side,
    required this.levels,
    required this.semanticLabel,
    required this.width,
    required this.height,
    this.ringChannel,
    this.pulse = true,
    this.dashOutlineWhenNoData = false,
  });

  final FootSide side;

  /// A level per FSR channel, or null when this foot has no data. A null
  /// entry is a zone whose level was not recorded.
  final List<PressureLevel?>? levels;
  final String semanticLabel;
  final double width;
  final double height;

  /// FSR channel to ring (alert detail), or null.
  final int? ringChannel;

  /// Whether "high" dots get the pulse ring (Home, My feet).
  final bool pulse;

  /// My feet: a foot with no data ([levels] null) gets a dashed outline.
  final bool dashOutlineWhenNoData;

  @override
  Widget build(BuildContext context) {
    final zones = footLayout.zones;
    final styles = [
      for (var c = 0; c < zones.length; c++)
        levels == null || c >= levels!.length
            ? FootDotColors.noData
            : levels![c] == null
            ? FootDotColors.notRecorded
            : dotStyleOf(levels![c]),
    ];
    final high = [
      for (var c = 0; c < zones.length; c++)
        pulse &&
            levels != null &&
            c < levels!.length &&
            levels![c] == PressureLevel.high,
    ];
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _AnimatedDots(
                side: side,
                styles: _DotStyles(styles),
                ringChannel: ringChannel,
                dashedOutline: dashOutlineWhenNoData && levels == null,
                // Reduce motion: jump to the end state (rule 16).
                duration: Motion.duration(context, Motion.enterDuration),
              ),
            ),
            if (high.contains(true))
              RepaintBoundary(
                child: _PulseRings(side: side, high: high, styles: styles),
              ),
          ],
        ),
      ),
    );
  }
}

/// The dot styles of one foot, compared by value: the implicit animation
/// only restarts when a target really changes, never because a 10 Hz
/// rebuild made a new list.
@immutable
class _DotStyles {
  const _DotStyles(this.list);

  final List<FootDotStyle> list;

  @override
  bool operator ==(Object other) =>
      other is _DotStyles && listEquals(other.list, list);

  @override
  int get hashCode => Object.hashAll(list);
}

class _DotsTween extends Tween<_DotStyles> {
  _DotsTween({super.begin});

  @override
  _DotStyles lerp(double t) {
    final a = begin!.list;
    final b = end!.list;
    if (a.length != b.length) return end!;
    return _DotStyles([
      for (var i = 0; i < b.length; i++) FootDotStyle.lerp(a[i], b[i], t),
    ]);
  }
}

class _AnimatedDots extends ImplicitlyAnimatedWidget {
  const _AnimatedDots({
    required this.side,
    required this.styles,
    required this.ringChannel,
    required this.dashedOutline,
    required super.duration,
  }) : super(curve: Motion.enter);

  final FootSide side;
  final _DotStyles styles;
  final int? ringChannel;
  final bool dashedOutline;

  @override
  AnimatedWidgetBaseState<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends AnimatedWidgetBaseState<_AnimatedDots> {
  _DotsTween? _styles;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _styles = visitor(
      _styles,
      widget.styles,
      (v) => _DotsTween(begin: v as _DotStyles),
    ) as _DotsTween?;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FootPainter(
        side: widget.side,
        styles: _styles!.evaluate(animation).list,
        ringChannel: widget.ringChannel,
        dashedOutline: widget.dashedOutline,
      ),
    );
  }
}

/// Maps view-box units to the widget, keeping the aspect ratio.
(double, Offset) fitFootViewBox(Size size) {
  final box = footLayout.viewBox;
  final scale = (size.width / box.width) < (size.height / box.height)
      ? size.width / box.width
      : size.height / box.height;
  final dx = (size.width - box.width * scale) / 2;
  final dy = (size.height - box.height * scale) / 2;
  return (scale, Offset(dx, dy));
}

/// The foot outline paths, parsed once.
final footOutlines = {
  for (final s in FootSide.values) s: parseOutline(footLayout.outline(s)),
};

/// Draws [side]'s outline (fill `bg`, stroke `divider` 2.5) on a canvas
/// already in view-box units (DESIGN-SPEC §5). [dashed]: My feet with no
/// data, `inkSubtle` dashed 6 5.
void paintFootOutline(Canvas canvas, FootSide side, {bool dashed = false}) {
  final outline = footOutlines[side]!;
  final stroke = Paint()
    ..color = dashed ? AppColors.inkSubtle : AppColors.divider
    ..style = PaintingStyle.stroke
    ..strokeWidth = _outlineWidth;
  canvas
    ..drawPath(outline, Paint()..color = AppColors.bg)
    ..drawPath(dashed ? dashedPath(outline, _outlineDash) : outline, stroke);
}

/// Outline stroke, view-box units (DESIGN-SPEC §5).
const _outlineWidth = 2.5;
const _outlineDash = [6.0, 5.0];

/// [source] cut into dashes of [pattern] (on, off, …).
Path dashedPath(Path source, List<double> pattern) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var on = true;
    var i = 0;
    while (d < metric.length) {
      final len = pattern[i % pattern.length];
      if (on) out.addPath(metric.extractPath(d, d + len), Offset.zero);
      d += len;
      on = !on;
      i++;
    }
  }
  return out;
}

class _FootPainter extends CustomPainter {
  _FootPainter({
    required this.side,
    required this.styles,
    this.ringChannel,
    this.dashedOutline = false,
  });

  final FootSide side;
  final List<FootDotStyle> styles;
  final int? ringChannel;
  final bool dashedOutline;

  static const _dash = [4.0, 3.0];

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    paintFootOutline(canvas, side, dashed: dashedOutline);

    for (var c = 0; c < styles.length; c++) {
      final style = styles[c];
      final center = footLayout.zones[c].position(side);
      canvas.drawCircle(center, style.radius, Paint()..color = style.fill);
      final stroke = Paint()
        ..color = style.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = FootDotColors.outlineWidth;
      if (style.dashed) {
        canvas.drawPath(
          dashedPath(
            Path()
              ..addOval(Rect.fromCircle(center: center, radius: style.radius)),
            _dash,
          ),
          stroke,
        );
      } else {
        canvas.drawCircle(center, style.radius, stroke);
      }
    }
    final ring = ringChannel;
    if (ring != null && ring < styles.length) {
      canvas.drawCircle(
        footLayout.zones[ring].position(side),
        styles[ring].radius + FootDotColors.triggerRingExtra,
        Paint()
          ..color = FootDotColors.triggerRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = FootDotColors.triggerRingWidth,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FootPainter old) =>
      old.side != side ||
      old.dashedOutline != dashedOutline ||
      old.ringChannel != ringChannel ||
      !listEquals(old.styles, styles);
}

/// The ring on "high" dots: grows from radius + 1 to + 12 while fading
/// 0.5 → 0 over 1.4 s of every 1.6 s (`pulse`, `enter` curve). Reduce
/// motion: a still ring at radius + 5, opacity 0.6.
class _PulseRings extends StatefulWidget {
  const _PulseRings({
    required this.side,
    required this.high,
    required this.styles,
  });

  final FootSide side;
  final List<bool> high;
  final List<FootDotStyle> styles;

  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PulsePainter(
        side: widget.side,
        high: widget.high,
        styles: widget.styles,
        progress: _controller,
        still: Motion.reduced(context),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.side,
    required this.high,
    required this.styles,
    required this.progress,
    required this.still,
  }) : super(repaint: progress);

  final FootSide side;
  final List<bool> high;
  final List<FootDotStyle> styles;
  final Animation<double> progress;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final double extra;
    final double opacity;
    if (still) {
      extra = Motion.pulseStillRadius;
      opacity = Motion.pulseStillOpacity;
    } else {
      final grow =
          Motion.pulseGrow.inMicroseconds / Motion.pulse.inMicroseconds;
      final t = progress.value / grow;
      if (t >= 1) return;
      final p = Motion.enter.transform(t);
      extra = ui.lerpDouble(Motion.pulseFromRadius, Motion.pulseToRadius, p)!;
      opacity = Motion.pulseFromOpacity * (1 - p);
    }
    final (scale, offset) = fitFootViewBox(size);
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    final paint = Paint()
      ..color = FootDotColors.pulseRing.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = FootDotColors.pulseRingWidth;
    for (var c = 0; c < high.length; c++) {
      if (!high[c]) continue;
      canvas.drawCircle(
        footLayout.zones[c].position(side),
        FootDotColors.high.radius + extra,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.still != still || old.side != side || !listEquals(old.high, high);
}

/// Legend "น้อย" / "ปานกลาง" / "มาก" (DESIGN-SPEC §1: radii 5 / 7 / 9 with a
/// 1.5 px `inkMuted` outline). Hidden from screen readers: the maps carry
/// their own labels.
class PressureLegend extends StatelessWidget {
  const PressureLegend({super.key, required this.textStyle});

  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Dimens.cardGap,
        runSpacing: Dimens.tightGap,
        children: [
          for (final level in PressureLevel.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendDot(style: dotStyleOf(level)),
                const SizedBox(width: Dimens.tightGap),
                Text(level.th, style: textStyle),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.style});

  final FootDotStyle style;

  @override
  Widget build(BuildContext context) {
    final d = style.legendRadius * 2;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: style.fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.inkMuted,
          width: FootDotColors.legendOutlineWidth,
        ),
      ),
    );
  }
}
