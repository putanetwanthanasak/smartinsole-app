import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/config/foot_layout.dart';

void main() {
  final json = jsonDecode(
    File('../shared/sensor_layout.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final sites = (json['sites']! as List).cast<Map<String, Object?>>();

  test('8 zones in wire order, identical to shared/sensor_layout.json', () {
    expect(footLayout.zones.map((z) => z.id), [
      'hallux',
      'meta1',
      'meta3',
      'meta5',
      'midfoot',
      'heel',
      'medialArch',
      'lateralHeel',
    ]);
    expect(sites, hasLength(footLayout.zones.length));
    for (var i = 0; i < sites.length; i++) {
      final s = sites[i];
      final z = footLayout.zones[i];
      expect(s['index'], i);
      expect(s['id'], z.id);
      expect(s['nameEn'], z.nameEn);
      expect(s['nameTh'], z.nameTh);
      expect(s['region'], z.region.name);
      expect(s['mm'], [z.mm.dx, z.mm.dy]);
    }
  });

  test('regions and the display transform match the JSON', () {
    final regions = json['regions']! as Map<String, Object?>;
    for (final r in FootRegion.values) {
      expect(regions[r.name], [
        for (var i = 0; i < footLayout.zones.length; i++)
          if (footLayout.zones[i].region == r) i,
      ], reason: r.name);
    }
    final display = json['display']! as Map<String, Object?>;
    expect(display['viewBox'], [
      footLayout.viewBox.width,
      footLayout.viewBox.height,
    ]);
    expect(display['scale'], footLayout.view.scale);
    expect(display['x0'], footLayout.view.x0);
    expect(display['y0'], footLayout.view.y0);
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

  test('positions follow the anatomy: toes at the top, medial inside', () {
    final hallux = footLayout.zones[0].left;
    final heel = footLayout.zones[5].left;
    final mth5 = footLayout.zones[3].left;
    expect(hallux.dy, lessThan(heel.dy));
    // Left foot: the big toe side (medial) is at larger x.
    expect(footLayout.zones[1].left.dx, greaterThan(mth5.dx));
  });
}
