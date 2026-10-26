import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smartinsole/footcheck/photo_processor.dart';

/// A camera-like JPEG: landscape sensor image, red in the left half (as
/// stored), with EXIF orientation, GPS-free but with a device model, and
/// an ICC profile, all of which must be gone after processing.
Uint8List cameraJpeg({
  int width = 3840,
  int height = 2160,
  int orientation = 6,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: width ~/ 2 - 1,
    y2: height - 1,
    color: img.ColorRgb8(255, 0, 0),
  );
  image.exif.imageIfd.orientation = orientation;
  image.exif.imageIfd['Model'] = img.IfdValueAscii('SM-N975F');
  image.exif.imageIfd['Make'] = img.IfdValueAscii('samsung');
  return img.encodeJpg(image, quality: 90);
}

bool isRed(img.Pixel p) => p.r > 200 && p.b < 60;

void main() {
  test('crops to the viewfinder aspect and shrinks the long side to 1600', () {
    final out = processFootPhoto(
      cameraJpeg(),
      aspect: 342 / 416,
      fromFrontCamera: false,
    );
    final image = img.decodeJpg(out)!;
    expect(image.height, footPhotoMaxSide);
    expect(image.width / image.height, closeTo(342 / 416, 0.01));
  });

  test('never enlarges a small photo', () {
    final out = processFootPhoto(
      cameraJpeg(width: 800, height: 600, orientation: 1),
      aspect: 4 / 3,
      fromFrontCamera: false,
    );
    final image = img.decodeJpg(out)!;
    expect([image.width, image.height], [800, 600]);
  });

  test('the saved JPEG carries no EXIF, ICC or comment (no metadata)', () {
    final input = cameraJpeg();
    expect(jpegMarkers(input), contains(0xE1)); // the camera's EXIF
    final out = processFootPhoto(
      input,
      aspect: 342 / 416,
      fromFrontCamera: true,
    );
    final markers = jpegMarkers(out);
    // APP0 (JFIF) is allowed; APP1–APP15 (EXIF, XMP, ICC, …) and COM not.
    expect(markers.where((m) => m >= 0xE1 && m <= 0xEF), isEmpty);
    expect(markers, isNot(contains(0xFE)));
    expect(img.decodeJpg(out)!.exif.isEmpty, isTrue);
    expect(String.fromCharCodes(out), isNot(contains('SM-N975F')));
  });

  test('EXIF rotation is applied; a front photo is un-mirrored', () {
    // Orientation 1, red on the left as stored.
    final plain = cameraJpeg(width: 1200, height: 900, orientation: 1);
    final back = img.decodeJpg(
      processFootPhoto(plain, aspect: 4 / 3, fromFrontCamera: false),
    )!;
    final front = img.decodeJpg(
      processFootPhoto(plain, aspect: 4 / 3, fromFrontCamera: true),
    )!;
    expect(isRed(back.getPixel(10, 450)), isTrue);
    expect(isRed(front.getPixel(10, 450)), isFalse);
    expect(isRed(front.getPixel(1190, 450)), isTrue);

    // Orientation 6 (rotate 90° clockwise): the stored left half becomes
    // the top half, and the image becomes portrait.
    final rotated = img.decodeJpg(
      processFootPhoto(
        cameraJpeg(width: 1200, height: 900),
        aspect: 3 / 4,
        fromFrontCamera: false,
      ),
    )!;
    expect(rotated.height > rotated.width, isTrue);
    expect(isRed(rotated.getPixel(450, 10)), isTrue);
    expect(isRed(rotated.getPixel(450, 1190)), isFalse);
  });

  test('a mirror the camera recorded in EXIF is applied before the '
      'front un-mirror, so the result is the true view', () {
    // Orientation 2 = mirrored as stored (what CameraX writes for a front
    // photo it mirrors to match the preview).
    final mirrored = cameraJpeg(width: 1200, height: 900, orientation: 2);
    final out = img.decodeJpg(
      processFootPhoto(mirrored, aspect: 4 / 3, fromFrontCamera: true),
    )!;
    expect(isRed(out.getPixel(10, 450)), isTrue);
  });

  test('a file that is not a JPEG is refused', () {
    expect(
      () => processFootPhoto(
        Uint8List.fromList([1, 2, 3]),
        aspect: 1,
        fromFrontCamera: false,
      ),
      throwsFormatException,
    );
  });
}
