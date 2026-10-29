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
  State<TempDeltaChart> createState() => TempDeltaChartState();
}

class TempDeltaChartState extends State<TempDeltaChart>
    with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: Motion.valueDuration,
  );
  late final _progress = CurvedAnimation(parent: _draw, curve: Motion.value);
  bool _started = false;

  /// How far the lines have drawn in, 0–1.
  @visibleForTesting
  double get drawProgress => _draw.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _drawIn();
    }
  }

  @override
  void didUpdateWidget(TempDeltaChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawInKey != widget.drawInKey) _drawIn();
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
      container: true,
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
      // Left of the band, or right when a gap line would cross it.
      bool crossed(double from) => data.gaps.any((g) {
        final gx = x(g.fromMs);
        return gx >= from - Dimens.textGap &&
            gx <= from + band.width + Dimens.textGap;
      });
      final atLeft = plot.left + Dimens.tightGap;
      final atRight = plot.right - Dimens.tightGap - band.width;
      band.paint(
        canvas,
        Offset(
          crossed(atLeft) && !crossed(atRight) ? atRight : atLeft,
          bandTop + Dimens.textGap / 2,
        ),
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

    // X labels: start, middle, end. With large text the middle one goes
    // first, then the start, rather than overlap.
    if (!data.isEmpty) {
      final mid = data.startMs + (data.endMs - data.startMs) ~/ 2;
      final xs = [data.startMs, mid, data.endMs];
      final placed = <(TextPainter, double)>[];
      for (var i = 0; i < xs.length; i++) {
        final p = label(
          hhmm(DateTime.fromMillisecondsSinceEpoch(xs[i])),
          _axisStyle,
        );
        final cx = x(xs[i]);
        placed.add((
          p,
          switch (i) {
            0 => cx,
            1 => cx - p.width / 2,
            _ => cx - p.width,
          },
        ));
      }
      bool apart((TextPainter, double) a, (TextPainter, double) b) =>
          a.$2 + a.$1.width + Dimens.tightGap <= b.$2;
      final shown = apart(placed[0], placed[1]) && apart(placed[1], placed[2])
          ? placed
          : apart(placed[0], placed[2])
          ? [placed[0], placed[2]]
          : [placed[2]];
      for (final (p, dx) in shown) {
        p.paint(canvas, Offset(dx, plot.bottom + Dimens.tightGap));
      }
    }

    // Connection gaps: a dashed vertical line each; the newest one is
    // labelled "ขาดข้อมูล / ตั้งแต่ HH:mm" while it is open, or
    // "ขาดข้อมูล / HH:mm–HH:mm" once data came back, on a backdrop over
    // the lines.
    void Function()? gapLabel;
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
        // Room beside the line, keeping the backdrop inside the plot.
        final right = plot.right - Dimens.textGap - (gx + Dimens.tightGap);
        final left = gx - Dimens.tightGap - (plot.left + Dimens.textGap);
        var b = label(gapLabelTime(g), _gapStyle);
        double width() => a.width > b.width ? a.width : b.width;
        if (width() > right && width() > left) {
          b = label(gapLabelTime(g, wrapped: true), _gapStyle);
        }
        final w = width();
        // Right of the line, or left of it when there is no room; else
        // left of it as far as the plot's edge allows (never over the
        // axis labels or out of the card).
        final lx = w <= right
            ? gx + Dimens.tightGap
            : w <= left
            ? gx - Dimens.tightGap - w
            : plot.left + Dimens.textGap;
        final ly = (bandBottom + Dimens.textGap).clamp(
          plot.top,
          plot.bottom - a.height - b.height,
        );
        gapLabel = () {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                lx - Dimens.textGap,
                ly,
                w + Dimens.textGap * 2,
                a.height + b.height,
              ),
              const Radius.circular(TempChartColors.gapLabelBackdropRadius),
            ),
            Paint()..color = TempChartColors.gapLabelBackdrop,
          );
          a.paint(canvas, Offset(lx, ly));
          b.paint(canvas, Offset(lx, ly + a.height));
        };
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
    // INTERIM (S8D-1): the first site in the old forefoot style (dashed),
    // the second in the old heel style (solid).
    for (final site in data.sites) {
      final heel = site != data.sites.first;
      final paint = Paint()
        ..color = heel ? TempChartColors.heel : TempChartColors.forefoot
        ..style = PaintingStyle.stroke
        ..strokeWidth = heel
            ? TempChartColors.heelWidth
            : TempChartColors.forefootWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (final run in data.runsOf(site)) {
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
      for (final site in data.sites) {
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
    gapLabel?.call();
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.data != data || old.deltaC != deltaC || old.scaler != scaler;
}

/// Legend: the two line styles with their sites' names (INTERIM, S8D-1:
/// [sites] as the chart's). Hidden from screen readers; the chart has its
/// own summary.
class TempChartLegend extends StatelessWidget {
  const TempChartLegend({super.key, required this.sites});

  final List<int> sites;

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
        children: [
          for (final site in sites.reversed)
            item(site != sites.first, footLayout.zones[site].nameTh),
        ],
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
