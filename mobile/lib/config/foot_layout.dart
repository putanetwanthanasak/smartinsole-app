import 'dart:ui';

import '../ble/packets.dart';

/// Where each FSR channel and temperature site sits on the foot map.
///
/// Mirrors `shared/sensor_layout.json` (DATA-CONTRACT v1.6 §3.1, user
/// decision 2026-10-29): 8 sites per foot, NTC i next to FSR i, positions
/// in mm. `test/config/foot_layout_test.dart` keeps the two identical, as
/// `model_channels.dart` does for `model_input.json`. This file is the one
/// place that holds the outline, the channel → zone mapping and every
/// position.
///
/// Drawn coordinates are SVG units in a 120×268 view box per foot, top
/// view, big toe on the inner side; a site's mm position is placed with the
/// JSON's display transform ([MmToView]).
class FootLayout {
  const FootLayout({
    required this.viewBox,
    required this.view,
    required this.outlineLeft,
    required this.outlineRight,
    required this.zones,
  });

  final Size viewBox;
  final MmToView view;

  /// SVG path data (absolute M / C / Z only).
  final String outlineLeft;
  final String outlineRight;

  /// Indexed by FSR channel (= temperature site index: NTC i sits with
  /// FSR i, DATA-CONTRACT v1.6).
  final List<FootZone> zones;

  String outline(FootSide side) =>
      side == FootSide.left ? outlineLeft : outlineRight;
}

/// mm (left foot, from the lateral edge and the heel's back edge) → view
/// box units: `x0 + scale·x`, `y0 − scale·y`; the right foot mirrors.
class MmToView {
  const MmToView({required this.scale, required this.x0, required this.y0});

  final double scale;
  final double x0;
  final double y0;
}

/// Coarse part of the foot, for plain-Thai sentences ("ปลายเท้าซ้าย…") and
/// the rule-based gait shares (`sensor_layout.json` `regions`).
enum FootRegion {
  forefoot('ปลายเท้า'),
  lateral('ขอบเท้าด้านนอก'),
  arch('อุ้งเท้า'),
  heel('ส้นเท้า');

  const FootRegion(this.th);
  final String th;
}

class FootZone {
  const FootZone({
    required this.id,
    required this.nameEn,
    required this.nameTh,
    required this.region,
    required this.mm,
  });

  /// Stable id, stored in alerts and capture files (ids 0–5 predate v1.6).
  final String id;
  final String nameEn;
  final String nameTh;
  final FootRegion region;

  /// Left-foot position in mm (`sensor_layout.json` frame).
  final Offset mm;

  Offset get left => Offset(
    footLayout.view.x0 + footLayout.view.scale * mm.dx,
    footLayout.view.y0 - footLayout.view.scale * mm.dy,
  );

  Offset get right => Offset(footLayout.viewBox.width - left.dx, left.dy);

  Offset position(FootSide side) => side == FootSide.left ? left : right;
}

const footLayout = FootLayout(
  viewBox: Size(120, 268),
  view: MmToView(scale: 0.891, x0: 15.3, y0: 264.7),
  outlineLeft:
      'M60 8C32 8 14 32 14 66C12 98 26 120 24 150C22 176 30 200 30 226'
      'C30 246 40 258 56 260C72 262 86 252 90 238C98 214 90 182 86 150'
      'C82 120 104 98 102 66C100 30 86 8 60 8Z',
  outlineRight:
      'M60 8C88 8 106 32 106 66C108 98 94 120 96 150C98 176 90 200 90 226'
      'C90 246 80 258 64 260C48 262 34 252 30 238C22 214 30 182 34 150'
      'C38 120 16 98 18 66C20 30 34 8 60 8Z',
  zones: [
    FootZone(
      id: 'hallux',
      nameEn: 'Hallux',
      nameTh: 'นิ้วหัวแม่เท้า',
      region: FootRegion.forefoot,
      mm: Offset(70, 247),
    ),
    FootZone(
      id: 'meta1',
      nameEn: '1st metatarsal head (MTH1)',
      nameTh: 'โคนนิ้วหัวแม่เท้า',
      region: FootRegion.forefoot,
      mm: Offset(75, 197),
    ),
    FootZone(
      id: 'meta3',
      nameEn: '2nd-3rd metatarsal heads (MTH2-3)',
      nameTh: 'กลางหน้าเท้า',
      region: FootRegion.forefoot,
      mm: Offset(48, 205),
    ),
    FootZone(
      id: 'meta5',
      nameEn: '5th metatarsal head (MTH5)',
      nameTh: 'โคนนิ้วก้อย',
      region: FootRegion.forefoot,
      mm: Offset(22, 197),
    ),
    FootZone(
      id: 'midfoot',
      nameEn: 'Lateral midfoot',
      nameTh: 'ขอบเท้าด้านนอก',
      region: FootRegion.lateral,
      mm: Offset(18, 140),
    ),
    FootZone(
      id: 'heel',
      nameEn: 'Heel centre',
      nameTh: 'กลางส้นเท้า',
      region: FootRegion.heel,
      mm: Offset(43, 38),
    ),
    FootZone(
      id: 'medialArch',
      nameEn: 'Medial arch',
      nameTh: 'อุ้งเท้า',
      region: FootRegion.arch,
      mm: Offset(59, 126),
    ),
    FootZone(
      id: 'lateralHeel',
      nameEn: 'Lateral heel',
      nameTh: 'ส้นเท้าด้านนอก',
      region: FootRegion.heel,
      mm: Offset(22, 82),
    ),
  ],
);

/// Parses the absolute M / C / Z subset of SVG path data used by the
/// placeholder outlines.
Path parseOutline(String d) {
  final path = Path();
  final tokens = RegExp(r'[MCZ]|-?\d*\.?\d+')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  double next() => double.parse(tokens[i++]);
  String? cmd;
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'M' || t == 'C' || t == 'Z') {
      cmd = t;
      i++;
      if (t == 'Z') path.close();
      continue;
    }
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      default:
        throw FormatException('Unsupported path data near "$t"', d);
    }
  }
  return path;
}
