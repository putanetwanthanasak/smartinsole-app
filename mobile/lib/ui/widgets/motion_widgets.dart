import 'package:flutter/material.dart';

import '../motion.dart';

/// A number that counts to its new value (`value`: 400 ms). The tween
/// retargets from wherever it is, so 10 Hz updates never restart it; under
/// reduce motion the new value appears at once.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    required this.style,
  });

  final double value;
  final String Function(double) format;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: Motion.duration(context, Motion.valueDuration),
      curve: Motion.value,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Children rise 12 px and fade in, one after another (`stagger`: 40 ms
/// apart, each `enter`), once when this widget is first built. Under
/// reduce motion they are simply there.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.children,
    required this.gap,
  });

  final List<Widget> children;
  final double gap;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late List<Animation<double>> _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final n = widget.children.length;
    final controller = _controller = AnimationController(
      vsync: this,
      duration: Motion.enterDuration + Motion.stagger * (n - 1),
    );
    final total = controller.duration!.inMicroseconds;
    final enter = Motion.enterDuration.inMicroseconds;
    final step = Motion.stagger.inMicroseconds;
    _items = [
      for (var i = 0; i < n; i++)
        CurvedAnimation(
          parent: controller,
          curve: Interval(
            i * step / total,
            (i * step + enter) / total,
            curve: Motion.enter,
          ),
        ),
    ];
    if (Motion.reduced(context)) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    for (final a in _items) {
      (a as CurvedAnimation).dispose();
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          _Rise(
            // Keyed like its child, so a row inserted later (a new alert)
            // does not take over another row's state.
            key: widget.children[i].key == null
                ? null
                : ValueKey(widget.children[i].key),
            animation: i < _items.length ? _items[i] : kAlwaysCompleteAnimation,
            child: widget.children[i],
          ),
        ],
      ],
    );
  }
}

/// Always the same widget structure, so children keep their state when the
/// entrance ends.
class _Rise extends AnimatedWidget {
  const _Rise({
    super.key,
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value.clamp(0.0, 1.0);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, Motion.staggerRise * (1 - t)),
        child: child,
      ),
    );
  }
}
