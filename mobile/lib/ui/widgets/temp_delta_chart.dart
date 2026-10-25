import 'package:flutter/material.dart';

import '../../config/foot_layout.dart';
import '../../rules/alert_engine.dart' show deltaAbove;
import '../clock.dart';
import '../motion.dart';
import '../screens/my_feet/temp_chart_model.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import 'foot_map.dart' show dashedPath;

/// "ความต่างของความอุ่นวันนี้" (DESIGN-SPEC §1, §8.2): |ΔT| per site
/// over today, the alert band and dashed line at [deltaC], and connection
/// gaps. One screen-reader image with [semanticLabel] (the summary).
///
/// The lines draw in from left to right (`value`) when the chart first
/// shows and whenever [drawInKey] changes (the tab is opened again); new
/// readings never restart it. Under reduce motion they appear at once.
class TempDeltaChart extends StatefulWidget {
  const TempDeltaChart({
    super.key,
    required this.data,
    required this.deltaC,
    required this.semanticLabel,
    required this.drawInKey,
  });

  final TempChartData data;
  final double deltaC;
  final String semanticLabel;
  final Object drawInKey;

  @override
  State<TempDeltaChart> createState() => _TempDeltaChartState();
}

class _TempDeltaChartState extends State<TempDeltaChart>
    with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: Motion.valueDuration,
  );
  late final _progress = CurvedAnimation(parent: _draw, curve: Motion.value);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _drawIn();
    }
  }

  @override
  void didUpdateWidget(TempDeltaChart old) {
    super.didUpdateWidget(old);
    if (old.drawInKey != widget.drawInKey) _drawIn();
  }

  void _drawIn() {
    if (Motion.reduced(context)) {
      _draw.value = 1;
    } else {
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: scaler.scale(Dimens.chartHeight),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ChartPainter(
              data: widget.data,
              deltaC: widget.deltaC,
              progress: _progress,
              scaler: scaler,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.data,
    required this.deltaC,
    required this.progress,
    required this.scaler,
  }) : super(repaint: progress);

  final TempChartData data;
  final double deltaC;
  final Animation<double> progress;
  final TextScaler scaler;

  static final _axisStyle = AppText.secondary.copyWith(
    color: TempChartColors.axisLabel,
  );
  static final _bandStyle = AppText.labelStrong.copyWith(
    color: TempChartColors.bandLabel,
  );
  static final _gapStyle = AppText.secondary.copyWith(
    color: TempChartColors.gapLabel,
  );

  /// Grid lines and their labels, °C (§8.2: "0°" "1°" "2°" "3°").
  static const _ticks = [0, 1, 2, 3];

  @override
  void paint(Canvas canvas, Size size) {
    final made = <TextPainter>[];
    TextPainter text(String s, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      made.add(p);
      return p;
    }

    _paint(canvas, size, text);
    for (final p in made) {
      p.dispose();
    }
  }

  void _paint(
    Canvas canvas,
    Size size,
    TextPainter Function(String, TextStyle) label,
  ) {
    final yLabels = [for (final t in _ticks) label('$t°', _axisStyle)];
    final yLabelW = yLabels.fold<double>(
      0,
      (m, p) => p.width > m ? p.width : m,
    );
    final xLabelH = label('00:00', _axisStyle).height;
    final left = yLabelW + Dimens.tightGap;
    final top = yLabels.last.height / 2;
    final bottom = size.height - xLabelH - Dimens.tightGap;
    final right = size.width;
    final plot = Rect.fromLTRB(left, top, right, bottom);

    double y(double c) =>
        plot.bottom - (c.clamp(0, chartMaxC) / chartMaxC) * plot.height;
    final span = (data.endMs - data.startMs).clamp(
      Duration.millisecondsPerMinute,
      double.maxFinite.toInt(),
    );
    double x(int ms) => plot.left + (ms - data.startMs) / span * plot.width;

    // Band from the threshold up, its label, then the grid.
    final bandTop = plot.top;
    final bandBottom = y(deltaC);
    canvas.drawRect(
      Rect.fromLTRB(plot.left, bandTop, plot.right, bandBottom),
      Paint()..color = TempChartColors.band,
    );
    for (var i = 0; i < _ticks.length; i++) {
      final ty = y(_ticks[i].toDouble());
      if (_ticks[i] > 0) {
        canvas.drawLine(
          Offset(plot.left, ty),
          Offset(plot.right, ty),
          Paint()
            ..color = TempChartColors.grid
            ..strokeWidth = Dimens.dividerWidth,
        );
      }
      final p = yLabels[i];
      p.paint(canvas, Offset(yLabelW - p.width, ty - p.height / 2));
    }
    final band = label('ระดับที่ควรระวัง', _bandStyle);
    if (bandBottom - bandTop >= band.height) {
      band.paint(
        canvas,
        Offset(plot.left + Dimens.tightGap, bandTop + Dimens.textGap / 2),
      );
    }
    canvas
      ..drawPath(
        dashedPath(
          Path()
            ..moveTo(plot.left, bandBottom)
            ..lineTo(plot.right, bandBottom),
          TempChartColors.thresholdDash,
        ),
        Paint()
          ..color = TempChartColors.threshold
          ..style = PaintingStyle.stroke
          ..strokeWidth = TempChartColors.thresholdWidth,
      )
      ..drawLine(
        Offset(plot.left, plot.bottom),
        Offset(plot.right, plot.bottom),
        Paint()
          ..color = TempChartColors.baseline
          ..strokeWidth = Dimens.dividerWidth,
      );

    // X labels: start, middle, end.
    if (!data.isEmpty) {
      final mid = data.startMs + (data.endMs - data.startMs) ~/ 2;
      final xs = [data.startMs, mid, data.endMs];
      for (var i = 0; i < xs.length; i++) {
        final p = label(
          hhmm(DateTime.fromMillisecondsSinceEpoch(xs[i])),
          _axisStyle,
        );
        final cx = x(xs[i]);
        final dx = switch (i) {
          0 => cx,
          1 => cx - p.width / 2,
          _ => cx - p.width,
        };
        p.paint(canvas, Offset(dx, plot.bottom + Dimens.tightGap));
      }
    }

    // Connection gaps: a dashed vertical line each; the newest one is
    // labelled "ขาดข้อมูล / ตั้งแต่ HH:mm".
    for (var i = 0; i < data.gaps.length; i++) {
      final g = data.gaps[i];
      final gx = x(g.fromMs);
      canvas.drawPath(
        dashedPath(
          Path()
            ..moveTo(gx, plot.top)
            ..lineTo(gx, plot.bottom),
          TempChartColors.gapDash,
        ),
        Paint()
          ..color = TempChartColors.gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = TempChartColors.gapWidth,
      );
      if (i == data.gaps.length - 1) {
        final a = label('ขาดข้อมูล', _gapStyle);
        final b = label(
          'ตั้งแต่ ${hhmm(DateTime.fromMillisecondsSinceEpoch(g.fromMs))}',
          _gapStyle,
        );
        final w = a.width > b.width ? a.width : b.width;
        // Right of the line, or left of it when there is no room.
        final lx = gx + Dimens.tightGap + w <= plot.right
            ? gx + Dimens.tightGap
            : gx - Dimens.tightGap - w;
        final ly = (bandBottom + Dimens.textGap).clamp(
          plot.top,
          plot.bottom - a.height - b.height,
        );
        a.paint(canvas, Offset(lx, ly));
        b.paint(canvas, Offset(lx, ly + a.height));
      }
    }

    // The lines, revealed from the left.
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          0,
          0,
          plot.left +
              plot.width * progress.value +
              TempChartColors.lastDotRadius * 2,
          size.height,
        ),
      );
    for (final site in [TempSite.forefoot, TempSite.heel]) {
      final heel = site == TempSite.heel;
      final paint = Paint()
        ..color = heel ? TempChartColors.heel : TempChartColors.forefoot
        ..style = PaintingStyle.stroke
        ..strokeWidth = heel
            ? TempChartColors.heelWidth
            : TempChartColors.forefootWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (final run in data.runs[site]!) {
        final path = Path()..moveTo(x(run.first.atMs), y(run.first.deltaC));
        for (final p in run.skip(1)) {
          path.lineTo(x(p.atMs), y(p.deltaC));
        }
        if (run.length == 1) {
          path.lineTo(x(run.first.atMs) + 0.01, y(run.first.deltaC));
        }
        canvas.drawPath(
          heel ? path : dashedPath(path, TempChartColors.forefootDash),
          paint,
        );
      }
    }
    if (progress.value >= 1) {
      for (final site in [TempSite.forefoot, TempSite.heel]) {
        final last = data.last(site);
        if (last == null) continue;
        final c = Offset(x(last.atMs), y(last.deltaC));
        canvas
          ..drawCircle(
            c,
            TempChartColors.lastDotRadius + TempChartColors.lastDotRing,
            Paint()..color = AppColors.surface,
          )
          ..drawCircle(
            c,
            TempChartColors.lastDotRadius,
            Paint()
              ..color = deltaAbove(last.deltaC, deltaC)
                  ? TempChartColors.lastDotAlert
                  : TempChartColors.lastDot,
          );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.data != data || old.deltaC != deltaC || old.scaler != scaler;
}

/// Legend "ส้นเท้า" / "หน้าเท้า": the two line styles. Hidden from screen
/// readers; the chart has its own summary.
class TempChartLegend extends StatelessWidget {
  const TempChartLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(bool heel, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(Dimens.iconButtonIcon, Dimens.smallCardIcon),
          painter: _LegendLine(heel: heel),
        ),
        const SizedBox(width: Dimens.tightGap),
        Text(label, style: AppText.secondary),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Dimens.cardGap,
        runSpacing: Dimens.tightGap,
        children: [item(true, 'ส้นเท้า'), item(false, 'หน้าเท้า')],
      ),
    );
  }
}

class _LegendLine extends CustomPainter {
  _LegendLine({required this.heel});

  final bool heel;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    canvas.drawPath(
      heel ? path : dashedPath(path, TempChartColors.forefootDash),
      Paint()
        ..color = heel ? TempChartColors.heel : TempChartColors.forefoot
        ..style = PaintingStyle.stroke
        ..strokeWidth = heel
            ? TempChartColors.heelWidth
            : TempChartColors.forefootWidth,
    );
  }

  @override
  bool shouldRepaint(_LegendLine old) => old.heel != heel;
}
