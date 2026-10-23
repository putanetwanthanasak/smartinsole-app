import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../ble/packets.dart';
import '../../../capture/capture_protocol.dart';
import '../../../device/display_snapshot.dart';
import '../../motion.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';

/// A button that acts only after being held for
/// [CaptureTimings.holdToAct], so a touch through a pocket can't trigger
/// it. A ring fills while held; under reduce motion (rule 16) there is no
/// ring, only the label "Keep holding…". The action itself always runs on
/// a timer of the hold time, never on the ring.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onHeld,
    this.palette = StatusColors.noData,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onHeld;
  final StatusPalette palette;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  // The ring's length is the hold time itself (a protocol value), not a
  // styling choice, so it isn't in motion.dart.
  late final _ring = AnimationController(
    vsync: this,
    duration: CaptureTimings.holdToAct,
  );
  Timer? _timer;
  bool _holding = false;
  Offset? _downAt;

  void _down(PointerDownEvent e) {
    if (widget.onHeld == null || _timer != null) return;
    _downAt = e.position;
    setState(() => _holding = true);
    if (!Motion.reduced(context)) _ring.forward(from: 0);
    _timer = Timer(CaptureTimings.holdToAct, () {
      HapticFeedback.heavyImpact();
      _reset();
      widget.onHeld?.call();
    });
  }

  /// A finger (or a pocket) sliding off is not a hold.
  void _move(PointerMoveEvent e) {
    final at = _downAt;
    if (at != null && (e.position - at).distance > kTouchSlop) _reset();
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _downAt = null;
    // The action can replace this button; the finger lifts afterwards.
    if (!mounted) return;
    _ring.reset();
    setState(() => _holding = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final enabled = widget.onHeld != null;
    final reduced = Motion.reduced(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${widget.label} (hold 2 seconds)',
      // Raw pointer events: a tap recognizer inside a scroll view reports
      // the touch late, which would make the hold longer than 2 s.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (_) => _reset(),
        onPointerCancel: (_) => _reset(),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: Dimens.buttonHeight + 16,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: BorderRadius.circular(Dimens.radiusCard),
              border: Border.all(color: p.icon, width: 2),
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!reduced)
                        AnimatedBuilder(
                          animation: _ring,
                          builder: (context, _) => CircularProgressIndicator(
                            value: _ring.value,
                            strokeWidth: 4,
                            color: p.icon,
                            backgroundColor: p.icon.withValues(alpha: 0.2),
                          ),
                        ),
                      Icon(widget.icon, color: p.icon, size: 22),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: AppText.bodyStrong.copyWith(color: p.text),
                      ),
                      Text(
                        _holding ? 'Keep holding…' : 'Hold 2 s',
                        style: AppText.secondary.copyWith(color: p.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width coloured strip: icon + text + colour (never colour alone).
class CaptureBanner extends StatelessWidget {
  const CaptureBanner({
    super.key,
    required this.palette,
    required this.icon,
    required this.text,
  });

  final StatusPalette palette;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppText.bodyStrong.copyWith(color: palette.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// One foot's link for the researcher: connection, battery, firmware.
class FootLinkRow extends StatelessWidget {
  const FootLinkRow({super.key, required this.view, this.issues});

  final FootView view;

  /// Pre-check issues; null when not checking.
  final List<String>? issues;

  @override
  Widget build(BuildContext context) {
    final ok = issues == null ? view.usable : issues!.isEmpty;
    final p = ok ? StatusColors.safe : StatusColors.noData;
    final side = view.side == FootSide.left ? 'Left' : 'Right';
    final detail = [
      view.connection.name,
      if (view.batteryPct != null) 'battery ${view.batteryPct} %',
      if (view.firmware != null) 'fw ${view.firmware}',
    ].join(' · ');
    return Container(
      key: ValueKey('capture-foot-${view.side.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? LucideIcons.circle_check : LucideIcons.circle_alert,
            color: p.icon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$side foot',
                  style: AppText.bodyStrong.copyWith(color: p.text),
                ),
                Text(detail, style: AppText.secondary.copyWith(color: p.text)),
                if (issues != null && issues!.isNotEmpty)
                  Text(
                    issues!.join(' · '),
                    style: AppText.secondary.copyWith(
                      color: p.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `2:59`, `0:07`.
String mmss(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String sideName(FootSide s) => s == FootSide.left ? 'left' : 'right';
