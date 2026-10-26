import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Saved photo size (user decision 2026-10-26).
const footPhotoMaxSide = 1600;
const footPhotoJpegQuality = 85;

/// Turns a camera JPEG into the stored foot photo:
/// 1. applies the EXIF rotation (the decoder does) but undoes any EXIF
///    mirror, so the saved photo is the true view of the foot whichever
///    lens took it (decision 1: a left sole looks like a left sole to a
///    doctor). The sensor never mirrors pixels; a camera that mirrors a
///    front photo to match its preview does it only with the EXIF flag
///    (CameraX's `isReversedHorizontal`). On the emulator (S8C) the
///    front camera's JPEG is unmirrored with no flag; the Note 10
///    checkpoint checks a real phone;
/// 2. centre-crops to the viewfinder's [aspect] (width / height), which
///    is what the user saw, since preview and photo share one aspect;
/// 3. shrinks the long side to [footPhotoMaxSide] (never enlarges);
/// 4. encodes JPEG at [footPhotoJpegQuality] with no EXIF, ICC or other
///    metadata (no GPS, no device model; user addition 6).
Uint8List processFootPhoto(Uint8List jpeg, {required double aspect}) {
  img.Image? decoded;
  try {
    decoded = img.decodeJpg(jpeg);
  } on img.ImageException {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('camera photo is not a readable JPEG');
  }
  // The decoder has already applied the whole EXIF orientation; flipping
  // back a mirrored one leaves only its rotation.
  final orientation = img.decodeJpgExif(jpeg)?.imageIfd.orientation;
  var image = _mirrored.contains(orientation)
      ? img.flipHorizontal(decoded)
      : decoded;
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
}) => Isolate.run(() => processFootPhoto(jpeg, aspect: aspect));

/// EXIF orientations that include a horizontal mirror (2, 4, 5, 7: one
/// of each pair AndroidX `ExifInterface.flipHorizontally` swaps).
const _mirrored = {2, 4, 5, 7};

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
