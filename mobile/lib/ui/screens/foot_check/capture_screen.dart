import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../footcheck/foot_camera.dart';
import '../../../footcheck/foot_check_flow.dart';
import '../../../footcheck/foot_views.dart';
import '../../../footcheck/footcheck_providers.dart';
import '../../../storage/models.dart';
import '../../motion.dart';
import '../../routes.dart';
import '../../theme/colors.dart';
import '../../theme/dimens.dart';
import '../../theme/typography.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/foot_map.dart';
import 'foot_check_copy.dart';
import 'foot_guide.dart';
import 'photo_tile.dart';

enum _CameraState { opening, ready, denied, failed }

/// Foot check › Capture (DESIGN-SPEC §11.2): full screen, camera colours.
/// Four views in order; soles start on the front camera and tops on the
/// back (user decision 5), "สลับกล้อง" swaps the lens for the rest of this
/// check's views of the same kind. After the 4th photo or skip → Compare;
/// back from Compare returns here at the first view, photos kept.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with SingleTickerProviderStateMixin {
  late final FootCamera _camera = ref.read(footCameraProvider)();
  late final AppLifecycleListener _lifecycle;
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: Motion.valueDuration,
  );

  var _index = 0;
  final _facingFor = <bool, CameraFacing>{}; // by isSole
  CameraFacing? _opened;
  var _state = _CameraState.opening;
  int? _count; // 3, 2, 1 while the self-timer runs
  Timer? _countTimer;
  var _busy = false;
  final _pending = <Future<void>>[];
  var _closed = false;

  // The flying thumbnail (§12.2).
  Uint8List? _flyPhoto;
  Rect? _flyFrom;
  Rect? _flyTo;

  final _stackKey = GlobalKey();
  final _viewfinderKey = GlobalKey();
  final _slotKeys = [for (final _ in FootView.values) GlobalKey()];
  Size? _viewfinderSize;
  var _cameraGen = 0;

  FootView get _view => FootView.values[_index];

  CameraFacing get _wanted => _facingFor[_view.isSole] ?? _view.autoFacing;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: _release,
      onResume: () {
        if (!_closed) unawaited(_openCamera());
      },
    );
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    _closed = true;
    _countTimer?.cancel();
    _lifecycle.dispose();
    _fly.dispose();
    unawaited(_camera.close());
    super.dispose();
  }

  void _release() {
    _cameraGen++;
    _countTimer?.cancel();
    _count = null;
    _opened = null;
    unawaited(_camera.close());
    if (mounted) setState(() => _state = _CameraState.opening);
  }

  Future<void> _openCamera() async {
    if (_closed) return;
    final want = _wanted;
    if (_opened == want && _state == _CameraState.ready) return;
    // Only the latest open (or release) counts: an open that a release or
    // another open overtook while it waited must not mark the camera ready.
    final gen = ++_cameraGen;
    setState(() => _state = _CameraState.opening);
    try {
      final got = await _camera.open(want);
      if (!mounted || gen != _cameraGen) return;
      setState(() {
        _opened = got;
        _state = _CameraState.ready;
      });
    } on CameraUnavailable catch (e) {
      debugPrint('foot camera: $e');
      if (!mounted || gen != _cameraGen) return;
      setState(
        () => _state = e.permissionDenied
            ? _CameraState.denied
            : _CameraState.failed,
      );
    }
  }

  Future<void> _goTo(int index) async {
    if (index >= FootView.values.length) {
      await _toCompare();
      return;
    }
    setState(() => _index = index);
    await _openCamera();
  }

  Future<void> _toCompare() async {
    _countTimer?.cancel();
    setState(() {
      _count = null;
      _busy = true;
    });
    await Future.wait(_pending);
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.pushNamed(context, Routes.footCheckCompare);
    // Back from Compare: start again at the first view, photos kept.
    if (mounted && ref.read(footCheckFlowProvider) != null) {
      setState(() => _index = 0);
      await _openCamera();
    }
  }

  void _switchCamera() {
    final next = (_opened ?? _wanted).other;
    _facingFor[_view.isSole] = next;
    unawaited(_openCamera());
  }

  void _toggleTimer() {
    if (_count != null) {
      _countTimer?.cancel();
      setState(() => _count = null);
      return;
    }
    setState(() => _count = Motion.countdownSeconds);
    _announce('${Motion.countdownSeconds}');
    _countTimer = Timer.periodic(Motion.countdownStep, (t) {
      final next = (_count ?? 1) - 1;
      if (next <= 0) {
        t.cancel();
        setState(() => _count = null);
        unawaited(_shoot());
      } else {
        setState(() => _count = next);
        _announce('$next');
      }
    });
  }

  void _announce(String text) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      TextDirection.ltr,
      assertiveness: Assertiveness.assertive,
    ),
  );

  Future<void> _shoot() async {
    if (_busy || _state != _CameraState.ready) return;
    final view = _view;
    final size = _viewfinderSize;
    setState(() => _busy = true);
    Uint8List bytes;
    try {
      bytes = await _camera.take();
    } catch (e) {
      debugPrint('foot camera: take failed: $e');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    final aspect = size == null
        ? Dimens.viewfinderWidth / Dimens.viewfinderHeight
        : size.width / size.height;
    final job = ref
        .read(footCheckFlowProvider.notifier)
        .putPhoto(view, bytes, aspect: aspect)
        .then<void>(
          (_) {},
          onError: (Object e) {
            debugPrint('foot photo: not saved: $e');
          },
        );
    _pending.add(job);
    unawaited(job.whenComplete(() => _pending.remove(job)));
    _startFly(bytes, view);
    setState(() => _busy = false);
    await _goTo(_index + 1);
  }

  void _startFly(Uint8List bytes, FootView view) {
    if (Motion.reduced(context)) return;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? rectOf(GlobalKey k) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || stack == null) return null;
      return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    }

    final from = rectOf(_viewfinderKey);
    final to = rectOf(_slotKeys[view.index]);
    if (from == null || to == null) return;
    setState(() {
      _flyPhoto = bytes;
      _flyFrom = from;
      _flyTo = to;
    });
    _fly.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _flyPhoto = null);
    });
  }

  Future<void> _cancel() async {
    final run = ref.read(footCheckFlowProvider);
    if (run != null && run.photos.isNotEmpty || _pending.isNotEmpty) {
      final leave = await showConfirmSheet<bool>(
        context,
        Builder(
          builder: (context) => ConfirmSheet(
            title: FootCheckCopy.cancelSheetTitle,
            text: FootCheckCopy.cancelSheetText,
            cancelLabel: FootCheckCopy.cancelSheetKeep,
            confirmLabel: FootCheckCopy.cancelSheetConfirm,
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (leave != true) return;
    }
    await Future.wait(_pending);
    await ref.read(footCheckFlowProvider.notifier).discard();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(footCheckFlowProvider)?.photos ?? const {};
    final reduced = Motion.reduced(context);
    final fade = Motion.duration(context, Motion.viewFade);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Scaffold(
        backgroundColor: CameraColors.background,
        body: SafeArea(
          child: Stack(
            key: _stackKey,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.pagePadding,
                  Dimens.tightGap,
                  Dimens.pagePadding,
                  Dimens.cardGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopRow(
                      counter: FootCheckCopy.counter(_index + 1),
                      onCancel: _cancel,
                      onSwitch: _state == _CameraState.ready && !_busy
                          ? _switchCamera
                          : null,
                    ),
                    const SizedBox(height: Dimens.tightGap),
                    AnimatedSwitcher(
                      duration: fade,
                      child: Text(
                        FootCheckCopy.viewName(_view),
                        key: ValueKey(_view),
                        style: AppText.statusTitle.copyWith(
                          color: AppColors.surface,
                        ),
                      ),
                    ),
                    Text(
                      FootCheckCopy.hint,
                      style: AppText.body.copyWith(color: CameraColors.text2),
                    ),
                    const SizedBox(height: Dimens.cardGap),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: Dimens.viewfinderWidth,
                            maxHeight: Dimens.viewfinderHeight,
                          ),
                          child: AspectRatio(
                            aspectRatio:
                                Dimens.viewfinderWidth /
                                Dimens.viewfinderHeight,
                            child: LayoutBuilder(
                              builder: (context, c) {
                                _viewfinderSize = c.biggest;
                                return _Viewfinder(
                                  key: _viewfinderKey,
                                  camera: _camera,
                                  state: _state,
                                  view: _view,
                                  previewMirrored:
                                      _opened == CameraFacing.front,
                                  count: _count,
                                  busy: _busy,
                                  fade: fade,
                                  reduced: reduced,
                                  onAllow: () async {
                                    await _camera.openSettings();
                                  },
                                  onRetry: () {
                                    _opened = null;
                                    unawaited(_openCamera());
                                  },
                                  onAnswerOnly: () => unawaited(_toCompare()),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Dimens.cardGap),
                    _SlotStrip(
                      current: _index,
                      photos: photos,
                      slotKeys: _slotKeys,
                    ),
                    const SizedBox(height: Dimens.sectionGap),
                    _Controls(
                      counting: _count != null,
                      enabled: _state == _CameraState.ready && !_busy,
                      onTimer: _toggleTimer,
                      onShutter: () => unawaited(_shoot()),
                      onSkip: _busy ? null : () => unawaited(_goTo(_index + 1)),
                    ),
                  ],
                ),
              ),
              if (_flyPhoto != null) _flying(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flying() {
    return AnimatedBuilder(
      animation: _fly,
      builder: (context, child) {
        final t = Motion.value.transform(_fly.value);
        final from = _flyFrom!, to = _flyTo!;
        // Move the centre and scale towards the slot (0.43 of the photo).
        final center = Offset.lerp(from.center, to.center, t)!;
        final scale = 1 + (Motion.thumbFlyScale - 1) * t;
        final w = from.width * scale, h = from.height * scale;
        final ms = _fly.value * Motion.valueDuration.inMilliseconds;
        final fadeStart = Motion.thumbFadeAt.inMilliseconds;
        final opacity = ms < fadeStart
            ? 1.0
            : (1 - (ms - fadeStart) / Motion.thumbFade.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return Positioned(
          left: center.dx - w / 2,
          top: center.dy - h / 2,
          width: w,
          height: h,
          child: IgnorePointer(
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Dimens.radiusViewfinder),
        child: ColoredBox(
          color: CameraColors.slotDone,
          child: Image.memory(
            _flyPhoto!,
            fit: BoxFit.cover,
            cacheWidth: _flyCacheWidth,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }

  static const _flyCacheWidth = 400;
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.counter,
    required this.onCancel,
    required this.onSwitch,
  });

  final String counter;
  final VoidCallback onCancel;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final white = AppText.bodyStrong.copyWith(color: AppColors.surface);
    return Row(
      children: [
        Semantics(
          button: true,
          label: FootCheckCopy.cancel,
          excludeSemantics: true,
          onTap: onCancel,
          child: InkWell(
            key: const ValueKey('capture-cancel'),
            onTap: onCancel,
            borderRadius: BorderRadius.circular(Dimens.radiusInner),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: Dimens.minTouchTarget,
                minWidth: Dimens.minTouchTarget,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.x,
                    size: Dimens.iconButtonIcon,
                    color: AppColors.surface,
                  ),
                  const SizedBox(width: Dimens.textGap),
                  Text(FootCheckCopy.cancel, style: white),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          liveRegion: true,
          child: Text(
            counter,
            key: const ValueKey('capture-counter'),
            style: AppText.secondary.copyWith(color: CameraColors.text2),
          ),
        ),
        const SizedBox(width: Dimens.tightGap),
        // Added in S8C (user decision 5): 48×48, top right.
        IconButton(
          key: const ValueKey('capture-switch'),
          tooltip: FootCheckCopy.switchCamera,
          onPressed: onSwitch,
          constraints: const BoxConstraints(
            minWidth: Dimens.minTouchTarget,
            minHeight: Dimens.minTouchTarget,
          ),
          icon: const Icon(
            LucideIcons.switch_camera,
            size: Dimens.iconButtonIcon,
          ),
          color: AppColors.surface,
          disabledColor: CameraColors.slotTodo,
        ),
      ],
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    super.key,
    required this.camera,
    required this.state,
    required this.view,
    required this.previewMirrored,
    required this.count,
    required this.busy,
    required this.fade,
    required this.reduced,
    required this.onAllow,
    required this.onRetry,
    required this.onAnswerOnly,
  });

  final FootCamera camera;
  final _CameraState state;
  final FootView view;
  final bool previewMirrored;
  final int? count;
  final bool busy;
  final Duration fade;
  final bool reduced;
  final VoidCallback onAllow;
  final VoidCallback onRetry;
  final VoidCallback onAnswerOnly;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusViewfinder),
      child: ColoredBox(
        color: CameraColors.viewfinder,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (state == _CameraState.ready)
              ExcludeSemantics(child: camera.buildPreview()),
            if (state == _CameraState.ready || state == _CameraState.opening)
              Center(
                child: AnimatedSwitcher(
                  duration: fade,
                  child: Semantics(
                    key: ValueKey(view),
                    label:
                        '${FootCheckCopy.guidePrefix} ${FootCheckCopy.viewName(view)}',
                    image: true,
                    child: FootGuide(
                      outline: guideOutlineOf(
                        view,
                        previewMirrored: previewMirrored,
                      ),
                    ),
                  ),
                ),
              ),
            if (state == _CameraState.ready)
              Positioned(
                left: Dimens.cardGap,
                right: Dimens.cardGap,
                bottom: Dimens.cardGap,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: Dimens.camChipPaddingV,
                      horizontal: Dimens.camChipPaddingH,
                    ),
                    decoration: BoxDecoration(
                      color: CameraColors.background.withValues(
                        alpha: _chipAlpha,
                      ),
                      borderRadius: BorderRadius.circular(Dimens.radiusCard),
                    ),
                    child: Text(
                      FootCheckCopy.chip,
                      textAlign: TextAlign.center,
                      style: AppText.secondary.copyWith(
                        color: CameraColors.chipText,
                      ),
                    ),
                  ),
                ),
              ),
            if (count != null)
              Center(
                child: _Countdown(count: count!, reduced: reduced),
              ),
            if (busy)
              const Center(
                child: CircularProgressIndicator(color: CameraColors.guide),
              ),
            if (state == _CameraState.denied)
              _Panel(
                title: FootCheckCopy.cameraDenied,
                text: FootCheckCopy.cameraDeniedText,
                action: FootCheckCopy.cameraAllow,
                onAction: onAllow,
                onAnswerOnly: onAnswerOnly,
              ),
            if (state == _CameraState.failed)
              _Panel(
                title: FootCheckCopy.cameraFailed,
                text: FootCheckCopy.cameraFailedText,
                action: FootCheckCopy.cameraRetry,
                onAction: onRetry,
                onAnswerOnly: onAnswerOnly,
              ),
          ],
        ),
      ),
    );
  }

  /// Overlays (§1): hint chip `camBg` at 85 %.
  static const _chipAlpha = 0.85;
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.count, required this.reduced});

  final int count;
  final bool reduced;

  /// Countdown disc `camBg` at 80 % (§1).
  static const _discAlpha = 0.8;

  @override
  Widget build(BuildContext context) {
    final digit = Text(
      '$count',
      key: ValueKey(count),
      style: AppText.countdown.copyWith(color: AppColors.surface),
    );
    return Container(
      key: const ValueKey('capture-countdown'),
      width: Dimens.countdownDisc,
      height: Dimens.countdownDisc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CameraColors.background.withValues(alpha: _discAlpha),
        shape: BoxShape.circle,
      ),
      child: reduced
          ? digit
          : AnimatedSwitcher(
              duration: Motion.countdownDuration,
              switchInCurve: Motion.enter,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(
                    begin: Motion.countdownFrom,
                    end: 1.0,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: digit,
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
    required this.onAnswerOnly,
  });

  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onAnswerOnly;

  @override
  Widget build(BuildContext context) {
    final white = AppColors.surface;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dimens.cardPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            LucideIcons.camera_off,
            size: Dimens.emptyIcon,
            color: CameraColors.guide,
          ),
          const SizedBox(height: Dimens.cardGap),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.emptyTitle.copyWith(color: white),
          ),
          const SizedBox(height: Dimens.tightGap),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(color: CameraColors.text2),
          ),
          const SizedBox(height: Dimens.cardGap),
          FilledButton(
            key: const ValueKey('capture-camera-action'),
            onPressed: onAction,
            child: Text(action),
          ),
          const SizedBox(height: Dimens.buttonGap),
          OutlinedButton(
            key: const ValueKey('capture-answer-only'),
            onPressed: onAnswerOnly,
            // The theme's outlined button is white-filled; on camera
            // colours it is see-through with white text.
            style: OutlinedButton.styleFrom(
              foregroundColor: white,
              backgroundColor: Colors.transparent,
              side: const BorderSide(
                color: CameraColors.guide,
                width: Dimens.outlineWidth,
              ),
            ),
            child: const Text(
              FootCheckCopy.answerOnly,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotStrip extends StatelessWidget {
  const _SlotStrip({
    required this.current,
    required this.photos,
    required this.slotKeys,
  });

  final int current;
  final Map<FootView, String> photos;
  final List<GlobalKey> slotKeys;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final v in FootView.values)
          Expanded(
            child: _Slot(
              key: ValueKey('capture-slot-${v.name}'),
              boxKey: slotKeys[v.index],
              view: v,
              photo: photos[v],
              current: v.index == current,
            ),
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.boxKey,
    required this.view,
    required this.photo,
    required this.current,
  });

  final GlobalKey boxKey;
  final FootView view;
  final String? photo;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final taken = photo != null;
    final radius = BorderRadius.circular(Dimens.radiusAnswer);
    final state = current
        ? FootCheckCopy.slotCurrent
        : taken
        ? FootCheckCopy.slotDone
        : FootCheckCopy.slotTodo;
    Widget box;
    if (taken) {
      box = Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: SizedBox.square(
              dimension: Dimens.captureSlot,
              child: ColoredBox(
                color: CameraColors.slotDone,
                child: FootPhoto(path: photo!, cacheWidth: _thumbCacheWidth),
              ),
            ),
          ),
          if (current)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: CameraColors.guide,
                    width: Dimens.slotBorder,
                  ),
                ),
              ),
            ),
          const Positioned(
            right: -Dimens.textGap * 1.5,
            top: -Dimens.textGap * 1.5,
            child: SizedBox.square(
              dimension: Dimens.slotBadge,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CameraColors.guide,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.check,
                  size: Dimens.inlineIcon,
                  color: CameraColors.background,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (current) {
      box = Container(
        width: Dimens.captureSlot,
        height: Dimens.captureSlot,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: CameraColors.guide,
            width: Dimens.slotBorder,
          ),
        ),
      );
    } else {
      box = const SizedBox.square(
        dimension: Dimens.captureSlot,
        child: CustomPaint(painter: _TodoSlot()),
      );
    }
    return Semantics(
      label: '${FootCheckCopy.slotName(view)} $state',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox.square(
            key: boxKey,
            dimension: Dimens.captureSlot,
            child: box,
          ),
          const SizedBox(height: Dimens.textGap * 1.5),
          Text(
            FootCheckCopy.slotName(view),
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(
              color: current ? AppColors.surface : CameraColors.text2,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static const _thumbCacheWidth = 180;
}

class _TodoSlot extends CustomPainter {
  const _TodoSlot();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(Dimens.radiusAnswer),
    ).deflate(Dimens.slotBorder / 2);
    final out = dashedPath(Path()..addRRect(rrect), Dimens.slotDash);
    canvas.drawPath(
      out,
      Paint()
        ..color = CameraColors.slotTodo
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dimens.slotBorder,
    );
  }

  @override
  bool shouldRepaint(_TodoSlot old) => false;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.counting,
    required this.enabled,
    required this.onTimer,
    required this.onShutter,
    required this.onSkip,
  });

  final bool counting;
  final bool enabled;
  final VoidCallback onTimer;
  final VoidCallback onShutter;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final label = AppText.secondary.copyWith(
      color: AppColors.surface,
      fontWeight: FontWeight.w600,
    );
    final ring = Motion.duration(context, Motion.pressDuration);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _LabelledControl(
            key: const ValueKey('capture-timer'),
            label: FootCheckCopy.timer,
            style: label,
            onTap: enabled || counting ? onTimer : null,
            child: AnimatedContainer(
              duration: ring,
              curve: Motion.press,
              width: Dimens.captureControl,
              height: Dimens.captureControl,
              decoration: BoxDecoration(
                color: CameraColors.guide,
                shape: BoxShape.circle,
                border: Border.all(
                  color: counting ? AppColors.surface : CameraColors.guide,
                  width: Dimens.timerRing,
                ),
              ),
              child: const Icon(
                LucideIcons.timer,
                size: Dimens.timerIcon,
                color: CameraColors.background,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Semantics(
              button: true,
              enabled: enabled,
              label: FootCheckCopy.shutter,
              excludeSemantics: true,
              onTap: enabled ? onShutter : null,
              child: GestureDetector(
                key: const ValueKey('capture-shutter'),
                onTap: enabled ? onShutter : null,
                child: Container(
                  width: Dimens.shutter,
                  height: Dimens.shutter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surface,
                      width: Dimens.shutterRing,
                    ),
                  ),
                  child: Container(
                    width: Dimens.shutterDisc,
                    height: Dimens.shutterDisc,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AppColors.surface
                          : CameraColors.slotTodo,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _LabelledControl(
            key: const ValueKey('capture-skip'),
            label: FootCheckCopy.skip,
            style: label,
            onTap: onSkip,
            child: Container(
              width: Dimens.captureControl,
              height: Dimens.captureControl,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: _skipAlpha),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.skip_forward,
                size: Dimens.timerIcon,
                color: AppColors.surface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Skip button white at 16 % (§1).
  static const _skipAlpha = 0.16;
}

class _LabelledControl extends StatelessWidget {
  const _LabelledControl({
    super.key,
    required this.label,
    required this.style,
    required this.onTap,
    required this.child,
  });

  final String label;
  final TextStyle style;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            child,
            const SizedBox(height: Dimens.tightGap),
            Text(label, textAlign: TextAlign.center, style: style),
          ],
        ),
      ),
    );
  }
}
