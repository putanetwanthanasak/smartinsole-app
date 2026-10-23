import 'dart:ui';

import '../ble/packets.dart';

/// Where each FSR channel and temperature site sits on the foot map.
///
/// **Placeholder geometry** from DESIGN-SPEC §5, until
/// `shared/sensor_layout.json` exists (hardware; DESIGN-SPEC decision 3).
/// This file is the one place that holds it: the outline, the channel →
/// zone mapping and every position. When the JSON arrives, it replaces
/// [footLayout] and nothing else changes.
///
/// Coordinates are SVG units in a 120×268 view box per foot, top view,
/// big toe on the inner side.
class FootLayout {
  const FootLayout({
    required this.viewBox,
    required this.outlineLeft,
    required this.outlineRight,
    required this.zones,
    required this.tempSites,
  });

  final Size viewBox;

  /// SVG path data (absolute M / C / Z only).
  final String outlineLeft;
  final String outlineRight;

  /// Indexed by FSR channel.
  final List<FootZone> zones;
  final List<TempSiteLayout> tempSites;

  String outline(FootSide side) =>
      side == FootSide.left ? outlineLeft : outlineRight;
}

/// Coarse part of the foot, for plain-Thai sentences ("ปลายเท้าซ้าย…").
enum FootRegion {
  forefoot('ปลายเท้า'),
  lateral('ขอบเท้าด้านนอก'),
  heel('ส้นเท้า');

  const FootRegion(this.th);
  final String th;
}

class FootZone {
  const FootZone({
    required this.id,
    required this.nameTh,
    required this.region,
    required this.left,
    required this.right,
  });

  final String id;
  final String nameTh;
  final FootRegion region;
  final Offset left;
  final Offset right;

  Offset position(FootSide side) => side == FootSide.left ? left : right;
}

enum TempSite { forefoot, heel }

class TempSiteLayout {
  const TempSiteLayout({
    required this.site,
    required this.nameTh,
    required this.left,
    required this.right,
  });

  final TempSite site;
  final String nameTh;
  final Offset left;
  final Offset right;
}

const footLayout = FootLayout(
  viewBox: Size(120, 268),
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
      nameTh: 'นิ้วหัวแม่เท้า',
      region: FootRegion.forefoot,
      left: Offset(80, 36),
      right: Offset(40, 36),
    ),
    FootZone(
      id: 'meta1',
      nameTh: 'โคนนิ้วหัวแม่เท้า',
      region: FootRegion.forefoot,
      left: Offset(80, 88),
      right: Offset(40, 88),
    ),
    FootZone(
      id: 'meta3',
      nameTh: 'กลางหน้าเท้า',
      region: FootRegion.forefoot,
      left: Offset(54, 80),
      right: Offset(66, 80),
    ),
    FootZone(
      id: 'meta5',
      nameTh: 'โคนนิ้วก้อย',
      region: FootRegion.forefoot,
      left: Offset(30, 96),
      right: Offset(90, 96),
    ),
    FootZone(
      id: 'midfoot',
      nameTh: 'ขอบเท้าด้านนอก',
      region: FootRegion.lateral,
      left: Offset(36, 152),
      right: Offset(84, 152),
    ),
    FootZone(
      id: 'heel',
      nameTh: 'ส้นเท้า',
      region: FootRegion.heel,
      left: Offset(58, 224),
      right: Offset(62, 224),
    ),
  ],
  tempSites: [
    TempSiteLayout(
      site: TempSite.forefoot,
      nameTh: 'หน้าเท้า',
      left: Offset(62, 92),
      right: Offset(58, 92),
    ),
    TempSiteLayout(
      site: TempSite.heel,
      nameTh: 'ส้นเท้า',
      left: Offset(58, 222),
      right: Offset(62, 222),
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
