import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'foot_camera.dart';
import 'foot_views.dart';

/// [FootCamera] on the `camera` plugin (CameraX on Android). The only file
/// that imports it.
///
/// - Photos are taken with `takePicture`, which writes a temporary JPEG to
///   the app's cache folder (never MediaStore or the gallery); the bytes
///   are read and the file deleted here.
/// - 16:9 at up to 2160p, so the photo cropped to the viewfinder still has
///   a long side of at least 1600 px. Preview and photo share the aspect.
/// - The front preview is always mirrored (decision 1). The plugin mirrors
///   it only on its ImageReader path; where the engine's surface producer
///   handles crop and rotation (SurfaceTexture, e.g. the emulator's
///   OpenGLES renderer) it does not, so this class mirrors it there. The
///   saved JPEG is never mirrored (see `processFootPhoto`).
/// - Calls run one at a time: the permission dialog makes the app inactive
///   while an open is in progress, and the plugin breaks when a close or a
///   second open overlaps it (seen on the emulator, S8C).
class PluginFootCamera implements FootCamera {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  Future<void> _queue = Future.value();
  CameraFacing? _facing;
  bool? _pluginMirrorsFront;

  static const _previewChannel = MethodChannel('smartinsole/camera_preview');

  /// Whether the plugin mirrors a front preview itself: the same engine
  /// question it asks (`SurfaceProducer.handlesCropAndRotation`, answered
  /// by MainActivity). If asking fails, assume it does (its usual path).
  Future<bool> _askPluginMirrorsFront() async {
    try {
      final handles = await _previewChannel.invokeMethod<bool>(
        'handlesCropAndRotation',
      );
      debugPrint(
        'foot camera: surface producer handles crop and rotation: '
        '$handles',
      );
      return handles != true;
    } on Object catch (e) {
      debugPrint('foot camera: preview path unknown ($e)');
      return true;
    }
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<CameraFacing> open(CameraFacing facing) =>
      _serial(() => _open(facing));

  Future<CameraFacing> _open(CameraFacing facing) async {
    final status = await ph.Permission.camera.request();
    if (!status.isGranted) {
      throw CameraUnavailable(
        permissionDenied: true,
        askAgain: !status.isPermanentlyDenied,
      );
    }
    final cameras = _cameras ??= await availableCameras();
    if (cameras.isEmpty) {
      throw const CameraUnavailable(
        permissionDenied: false,
        detail: 'no camera',
      );
    }
    final want = facing == CameraFacing.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final desc = cameras.firstWhere(
      (c) => c.lensDirection == want,
      orElse: () => cameras.first,
    );
    await _close();
    final controller = CameraController(
      desc,
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
    } on CameraException catch (e) {
      await _dispose(controller);
      throw CameraUnavailable(
        permissionDenied: e.code.contains('AccessDenied'),
        detail: '${e.code}: ${e.description}',
      );
    } catch (e) {
      // The plugin also fails with plain errors (a null check when CameraX
      // could not bind the use cases).
      await _dispose(controller);
      throw CameraUnavailable(permissionDenied: false, detail: '$e');
    }
    _pluginMirrorsFront ??= await _askPluginMirrorsFront();
    _controller = controller;
    return _facing = desc.lensDirection == CameraLensDirection.front
        ? CameraFacing.front
        : CameraFacing.back;
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.expand();
    final size = c.value.previewSize!;
    // previewSize is landscape; the app is portrait. Cover the viewfinder.
    final preview = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: CameraPreview(c),
      ),
    );
    final mirrorHere =
        _facing == CameraFacing.front && _pluginMirrorsFront == false;
    return ClipRect(
      child: mirrorHere ? Transform.flip(flipX: true, child: preview) : preview,
    );
  }

  @override
  Future<Uint8List> take() => _serial(_take);

  Future<Uint8List> _take() async {
    final c = _controller;
    if (c == null) throw StateError('camera not open');
    final shot = await c.takePicture();
    final file = File(shot.path);
    try {
      return await file.readAsBytes();
    } finally {
      try {
        await file.delete();
      } on FileSystemException catch (e) {
        debugPrint('foot camera: temp file not deleted: $e');
      }
    }
  }

  @override
  Future<void> close() => _serial(_close);

  Future<void> _close() async {
    final c = _controller;
    _controller = null;
    _facing = null;
    if (c != null) await _dispose(c);
  }

  static Future<void> _dispose(CameraController c) async {
    try {
      await c.dispose();
    } catch (e) {
      debugPrint('foot camera: dispose failed: $e');
    }
  }

  @override
  Future<void> openSettings() => ph.openAppSettings();
}
