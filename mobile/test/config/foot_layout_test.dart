import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';

void main() {
  test('six zones in board order fsr0–fsr5 (DESIGN-SPEC §5)', () {
    expect(footLayout.zones.map((z) => z.id), [
      'hallux',
      'meta1',
      'meta3',
      'meta5',
      'midfoot',
      'heel',
    ]);
  });

  test('every position is inside its foot outline', () {
    for (final side in FootSide.values) {
      final path = parseOutline(footLayout.outline(side));
      for (final z in footLayout.zones) {
        expect(path.contains(z.position(side)), isTrue, reason: z.id);
      }
      expect(
        path.getBounds().width,
        lessThanOrEqualTo(footLayout.viewBox.width),
      );
    }
  });

  test('the right foot mirrors the left', () {
    for (final z in footLayout.zones) {
      expect(z.left.dx + z.right.dx, footLayout.viewBox.width, reason: z.id);
      expect(z.left.dy, z.right.dy);
    }
  });
}
