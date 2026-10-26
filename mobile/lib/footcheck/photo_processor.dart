import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Saved photo size (user decision 2026-10-26).
const footPhotoMaxSide = 1600;
const footPhotoJpegQuality = 85;

/// Turns a camera JPEG into the stored foot photo:
/// 1. applies the EXIF orientation (rotation and any mirror the camera
///    recorded), giving the image as the preview showed it;
/// 2. un-mirrors a front-camera photo ([fromFrontCamera]), so the saved
///    photo is the true view of the foot (decision 1: a left sole looks
///    like a left sole to a doctor, whichever lens took it);
/// 3. centre-crops to the viewfinder's [aspect] (width / height), which
///    is what the user saw, since preview and photo share one aspect;
/// 4. shrinks the long side to [footPhotoMaxSide] (never enlarges);
/// 5. encodes JPEG at [footPhotoJpegQuality] with no EXIF, ICC or other
///    metadata (no GPS, no device model; user addition 6).
///
/// Step 2 assumes the camera mirrors front photos to match the preview,
/// as CameraX does by default; the Note 10 checkpoint checks it.
Uint8List processFootPhoto(
  Uint8List jpeg, {
  required double aspect,
  required bool fromFrontCamera,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeJpg(jpeg);
  } on img.ImageException {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('camera photo is not a readable JPEG');
  }
  var image = img.bakeOrientation(decoded);
  if (fromFrontCamera) image = img.flipHorizontal(image);
  image = _cropToAspect(image, aspect);
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > footPhotoMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: footPhotoMaxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: footPhotoMaxSide,
            interpolation: img.Interpolation.average,
          );
  }
  image
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  return img.encodeJpg(image, quality: footPhotoJpegQuality);
}

/// [processFootPhoto] off the UI isolate.
Future<Uint8List> processFootPhotoInBackground(
  Uint8List jpeg, {
  required double aspect,
  required bool fromFrontCamera,
}) => Isolate.run(
  () =>
      processFootPhoto(jpeg, aspect: aspect, fromFrontCamera: fromFrontCamera),
);

img.Image _cropToAspect(img.Image image, double aspect) {
  final w = image.width, h = image.height;
  if (w / h > aspect) {
    final cw = (h * aspect).round();
    return img.copyCrop(image, x: (w - cw) ~/ 2, y: 0, width: cw, height: h);
  }
  final ch = (w / aspect).round();
  if (ch == h) return image;
  return img.copyCrop(image, x: 0, y: (h - ch) ~/ 2, width: w, height: ch);
}

/// JPEG marker segments (APPn, COM) in [jpeg], for the no-metadata test
/// and the Note 10 check.
List<int> jpegMarkers(Uint8List jpeg) {
  final markers = <int>[];
  var i = 2; // after SOI
  while (i + 4 <= jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    markers.add(marker);
    if (marker == 0xDA) break; // start of scan: no more headers
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    i += 2 + len;
  }
  return markers;
}
