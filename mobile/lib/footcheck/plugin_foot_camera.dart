import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
/// - The plugin mirrors the front preview itself.
class PluginFootCamera implements FootCamera {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  @override
  Future<CameraFacing> open(CameraFacing facing) async {
    final status = await ph.Permission.camera.request();
    if (!status.isGranted) {
      throw const CameraUnavailable(permissionDenied: true);
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
    await close();
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
      await controller.dispose();
      throw CameraUnavailable(
        permissionDenied: e.code.contains('AccessDenied'),
        detail: '${e.code}: ${e.description}',
      );
    }
    _controller = controller;
    return desc.lensDirection == CameraLensDirection.front
        ? CameraFacing.front
        : CameraFacing.back;
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.expand();
    final size = c.value.previewSize!;
    // previewSize is landscape; the app is portrait. Cover the viewfinder.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(c),
        ),
      ),
    );
  }

  @override
  Future<Uint8List> take() async {
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
  Future<void> close() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
  }

  @override
  Future<void> openSettings() => ph.openAppSettings();
}
