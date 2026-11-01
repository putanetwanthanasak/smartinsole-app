import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../ble/ble_protocol.dart';
import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../rules/alert_code.dart';
import '../../../rules/alert_copy.dart';
import '../../../rules/gait_note.dart';
import '../../../rules/pressure_level.dart';
import '../../../storage/models.dart';
import '../../clock.dart';
import '../../shell/app_shell.dart';
import '../../theme/colors.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/temp_site_map.dart' show TempSiteMark;
import '../home/home_copy.dart';
import '../home/home_model.dart' show FootMapView;

// What the Alerts list and the alert detail show for one stored alert
// (DESIGN-SPEC §7). Pure functions of the row, the thresholds and the
// time. Health copy comes from `alertCopyFor` (DRAFT until the medical
// expert reviews it, Appendix A); the detail rows' labels follow the
// §7.3 boards, and the PTI / LOAD_CONCENTRATION rows are S6B drafts.

/// Status tag, level word and icon of an alert (§7.1).
class AlertLook {
  const AlertLook({
    required this.palette,
    required this.icon,
    required this.tag,
    required this.levelWord,
  });

  final StatusPalette palette;
  final IconData icon;

  /// List-card tag: "ควรพักเท้า", "ควรระวัง", "อุปกรณ์".
  final String tag;

  /// Detail status card: "ควรพักเท้า", "ควรระวัง", "เรื่องอุปกรณ์".
  final String levelWord;
}

AlertLook lookOf(AlertKind kind) => switch (kind) {
  AlertKind.tempDelta => const AlertLook(
    palette: StatusColors.rest,
    icon: LucideIcons.octagon_alert,
    tag: 'ควรพักเท้า',
    levelWord: 'ควรพักเท้า',
  ),
  AlertKind.deviceLost => const AlertLook(
    palette: StatusColors.noData,
    icon: LucideIcons.bluetooth_off,
    tag: 'อุปกรณ์',
    levelWord: 'เรื่องอุปกรณ์',
  ),
  AlertKind.batteryLow => const AlertLook(
    palette: StatusColors.noData,
    icon: LucideIcons.battery_low,
    tag: 'อุปกรณ์',
    levelWord: 'เรื่องอุปกรณ์',
  ),
  // The pressure codes and the foot-check finding (level-2 codes are
  // never listed, but get the same look if one is ever opened).
  _ => const AlertLook(
    palette: StatusColors.careful,
    icon: LucideIcons.triangle_alert,
    tag: 'ควรระวัง',
    levelWord: 'ควรระวัง',
  ),
};

/// The copy of [a]: `alertCopyFor` for a contract code; the §7.1 board
/// copy for a foot-check finding (which has no detail screen of its own:
/// it opens Foot check › Something found).
AlertCopy copyOf(StoredAlert a) {
  final code = a.kind.code;
  if (code == null) {
    return const AlertCopy(
      title: 'พบสิ่งที่ควรให้แพทย์ดู',
      detail: '',
      steps: [],
      why: '',
      todo: 'ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู',
    );
  }
  return alertCopyFor(
    code,
    side: a.side ?? FootSide.left,
    channel: channelOf(a.zone),
    legacySite: a.legacySite,
    value: a.measuredValue,
    threshold: a.threshold,
  );
}

/// FSR channel of a stored zone id, or null.
int? channelOf(String? zoneId) {
  if (zoneId == null) return null;
  final i = footLayout.zones.indexWhere((z) => z.id == zoneId);
  return i < 0 ? null : i;
}

/// The list card's optional source line (§7.2 item 3).
String? sourceLineOf(StoredAlert a) =>
    a.kind == AlertKind.footCheckFinding ? 'จากการดูเท้าประจำวัน' : null;

/// Where tapping the list card goes (§4 navigation map).
enum AlertTarget { detail, connection, footCheckFound }

AlertTarget targetOf(AlertKind kind) => switch (kind) {
  AlertKind.batteryLow => AlertTarget.connection,
  AlertKind.footCheckFinding => AlertTarget.footCheckFound,
  _ => AlertTarget.detail,
};

DateTime localTimeOf(StoredAlert a) =>
    DateTime.fromMillisecondsSinceEpoch(a.atMs);

/// TalkBack label of a list card (§13): status + time + title + read
/// state, then the source line and the advice the card shows (rule 13),
/// e.g. "ควรพักเท้า 14:32 เท้าขวาอุ่นกว่าเท้าซ้าย ยังไม่ได้อ่าน ควรทำ:
/// นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม".
String cardLabel(StoredAlert a) {
  final copy = copyOf(a);
  final source = sourceLineOf(a);
  return [
    lookOf(a.kind).tag,
    hhmm(localTimeOf(a)),
    copy.title,
    a.isRead ? 'อ่านแล้ว' : 'ยังไม่ได้อ่าน',
    ?source,
    'ควรทำ: ${copy.todo}',
  ].join(' ');
}

/// Alerts-list group title for the local date [localDate] (`YYYY-MM-DD`)
/// at [now]: "วันนี้", "เมื่อวาน · อังคาร 20 ต.ค.", or "อังคาร 20 ต.ค.".
String groupTitle(String localDate, DateTime now) {
  final d = DateTime.parse(localDate);
  final rel = relativeDayTh(d, now);
  if (rel == 'วันนี้') return rel!;
  final day = thaiWeekdayDayMonth(d);
  return rel == null ? day : '$rel · $day';
}

/// Detail status-card time: "วันนี้ 14:32", "เมื่อวาน 16:20", or
/// "อังคาร 20 ต.ค. 16:20" for older days.
String detailTime(StoredAlert a, DateTime now) {
  final t = localTimeOf(a);
  return '${relativeDayTh(t, now) ?? thaiWeekdayDayMonth(t)} ${hhmm(t)}';
}

// --- Detail: action ------------------------------------------------------

/// The detail's action button (§4 navigation map): a My feet sub-tab or
/// Connection.
class AlertAction {
  const AlertAction(this.label, {this.myFeetTab});

  final String label;

  /// Null: open Connection.
  final MyFeetTab? myFeetTab;
}

AlertAction? actionOf(AlertKind kind) => switch (kind) {
  AlertKind.tempDelta => const AlertAction(
    'ดูความอุ่นของเท้า',
    myFeetTab: MyFeetTab.temperature,
  ),
  AlertKind.deviceLost => const AlertAction('เชื่อมต่ออีกครั้ง'),
  AlertKind.batteryLow || AlertKind.footCheckFinding => null,
  // Pressure codes.
  _ => const AlertAction('ดูแรงกดที่เท้า', myFeetTab: MyFeetTab.pressure),
};

// --- Detail: the "ตำแหน่งที่พบ" map ----------------------------------------

/// Temperature sites (`TEMP_DELTA`): the warmer foot's site is ringed.
/// Only for alerts stored since the 8 sites (schema v2): an older alert's
/// forefoot / heel site is not one of them, so it shows no map.
class TempMapView {
  const TempMapView({
    required this.warmSide,
    required this.site,
    required this.sites,
    required this.caption,
    required this.sitesLine,
    required this.labels,
  });

  final FootSide warmSide;

  /// Zone index of the site the alert names (ringed).
  final int site;

  /// Every qualifying site on [warmSide] (`details.tempSites`, zone
  /// indexes, [site] included): marked "จุดที่อุ่นกว่า".
  final Set<int> sites;
  final String caption;

  /// Below the caption when 2 or more sites qualified (S8D-2 draft):
  /// "จุดที่อุ่นกว่าบนเท้าขวา: กลางส้นเท้า · ส้นเท้าด้านนอก". Null for one.
  final String? sitesLine;
  final Map<FootSide, String> labels;

  /// The marks for [side]'s map.
  List<TempSiteMark> marksOf(FootSide side) => [
    for (var i = 0; i < footLayout.zones.length; i++)
      side != warmSide || !sites.contains(i)
          ? TempSiteMark.plain
          : i == site
          ? TempSiteMark.warmRinged
          : TempSiteMark.warm,
  ];
}

TempMapView? tempMapOf(StoredAlert a) {
  final side = a.side;
  final site = channelOf(a.zone);
  if (a.kind != AlertKind.tempDelta || side == null || site == null) {
    return null;
  }
  // The named site first, then the others in stored order (largest |ΔT|
  // first).
  final sites = <int>{
    site,
    for (final e in TempSiteEntry.listOf(a.details)) ?channelOf(e.zone),
  };
  final names = [for (final i in sites) footLayout.zones[i].nameTh];
  final name = names.first;
  final s = sideTh(side);
  final o = sideTh(otherSide(side));
  return TempMapView(
    warmSide: side,
    site: site,
    sites: sites,
    caption: '$name$sอุ่นกว่า$name$o',
    // S8D-2 draft.
    sitesLine: sites.length < 2
        ? null
        : 'จุดที่อุ่นกว่าบนเท้า$s: ${names.join(' · ')}',
    labels: {
      side: 'เท้า$s ${joinTh(names)}อุ่นกว่าเท้า$o',
      // S8D-1 draft (was "ที่หน้าเท้าและส้นเท้า", the 2 sites).
      otherSide(side):
          'เท้า$o จุดวัดความอุ่นทั้ง ${footLayout.zones.length} จุด',
    },
  );
}

/// Pressure zones (pressure codes): the levels at the time the alert was
/// raised, with the zone that triggered ringed.
class PressureMapView {
  const PressureMapView({
    required this.side,
    required this.channel,
    required this.levels,
    required this.caption,
    required this.labels,
    required this.recorded,
  });

  /// The foot and FSR channel that triggered.
  final FootSide side;
  final int channel;

  /// Per foot: a level per channel (a null entry: not recorded), or null
  /// when that foot gave no data then.
  final Map<FootSide, List<PressureLevel?>?> levels;
  final String caption;
  final Map<FootSide, String> labels;

  /// False for an alert stored before S6B, which kept only the triggering
  /// zone's value: every other zone is drawn as "not recorded".
  final bool recorded;
}

PressureMapView? pressureMapOf(StoredAlert a, Thresholds t) {
  final code = a.kind.code;
  final side = a.side;
  final channel = channelOf(a.zone);
  if (code == null ||
      !pressureCodes.contains(code) ||
      side == null ||
      channel == null) {
    return null;
  }
  final zone = footLayout.zones[channel].nameTh;
  final triggerLabel = 'เท้า${sideTh(side)} $zoneรับน้ำหนักมาก';
  final caption = 'จุดที่มีวงล้อม: $zone${sideTh(side)}';
  final map = a.details?['map'];
  if (map is Map) {
    final levels = <FootSide, List<PressureLevel?>?>{};
    final labels = <FootSide, String>{};
    for (final f in FootSide.values) {
      final foot = map[f.name];
      final names = foot is Map ? foot['levels'] : null;
      final kpa = foot is Map ? foot['kpa'] : null;
      // A map stored before the 8 zones (schema v1) has 6 entries: zones
      // 6–7 were not recorded then.
      final list = names is List
          ? [
              for (var c = 0; c < footLayout.zones.length; c++)
                c < names.length ? _levelNamed(names[c]) : null,
            ]
          : null;
      levels[f] = list;
      labels[f] = f == side
          ? triggerLabel
          : mapLabel(_footMapView(f, list, kpa is List ? kpa : null));
    }
    return PressureMapView(
      side: side,
      channel: channel,
      levels: levels,
      caption: caption,
      labels: labels,
      recorded: true,
    );
  }
  // Fallback: only the triggering zone. PEAK's value is kPa, so it has a
  // level; PTI (kPa·s) and LOAD_CONCENTRATION (%) do not, and no level is
  // claimed for them.
  final value = a.measuredValue;
  final level =
      code == AlertCode.pressurePeak || code == AlertCode.pressureWatch
      ? (value == null ? null : pressureLevel(value, t))
      : null;
  final n = footLayout.zones.length;
  return PressureMapView(
    side: side,
    channel: channel,
    levels: {
      for (final f in FootSide.values)
        f: [
          for (var c = 0; c < n; c++) f == side && c == channel ? level : null,
        ],
    },
    caption: caption,
    labels: {
      for (final f in FootSide.values)
        f: f == side ? triggerLabel : 'เท้า${sideTh(f)}',
    },
    recorded: false,
  );
}

PressureLevel? _levelNamed(Object? name) {
  for (final l in PressureLevel.values) {
    if (l.name == name) return l;
  }
  return null;
}

/// Home's map view of a stored foot, so the label reads as Home's would.
FootMapView _footMapView(
  FootSide side,
  List<PressureLevel?>? levels,
  List<Object?>? kpa,
) {
  if (levels == null || levels.every((l) => l == null)) {
    return FootMapView(side: side);
  }
  // A null zone in a stored map is one a 6-zone map did not record
  // (zones 6–7, before S8D); it never makes the foot "no data".
  final l = [for (final x in levels) x ?? PressureLevel.low];
  double k(int c) =>
      kpa != null && c < kpa.length ? (kpa[c] as num).toDouble() : 0;
  int? top;
  for (var c = 0; c < l.length; c++) {
    if (l[c] == PressureLevel.low) continue;
    if (top == null ||
        l[c].index > l[top].index ||
        (l[c] == l[top] && k(c) > k(top))) {
      top = c;
    }
  }
  return FootMapView(side: side, levels: l, topChannel: top);
}

// --- Detail: the gait note -------------------------------------------------

String? gaitNoteOf(StoredAlert a, Thresholds t) {
  final code = a.kind.code;
  if (code == null) return null;
  return gaitNoteTh(
    code: code,
    zoneId: a.zone,
    gaitClass: a.gaitClass,
    confidence: a.gaitConfidence,
    thresholds: t,
  );
}

// --- Detail: "ดูตัวเลขละเอียด" rows ----------------------------------------

/// Whole number, or one decimal when it has one ("200", "2.2").
String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

String _c(double v) => v.toStringAsFixed(1);

double? _d(Map<String, Object?>? m, String k) {
  final v = m?[k];
  return v is num ? v.toDouble() : null;
}

/// The details-expander rows of [a] (§7.3). Values come from the stored
/// row; the threshold stored with it wins over today's `thresholds.json`.
List<DetailRow> detailRowsOf(StoredAlert a, Thresholds t) {
  final code = a.kind.code;
  if (code == null) return const [];
  final d = a.details;
  final rows = <DetailRow>[DetailRow('รหัส', a.kind.wireName)];
  final value = a.measuredValue;
  final threshold = a.threshold;
  final side = a.side;
  final s = side == null ? '' : sideTh(side);
  final channel = channelOf(a.zone);
  final zone = channel == null ? '' : footLayout.zones[channel].nameTh;
  final level = DetailRow('ระดับภายในระบบ', '${a.level} จาก $maxLevel');
  final at = DetailRow('เวลาที่พบ', thaiDateTimeBE(localTimeOf(a)));
  final source = t.sourceOf(a.kind.wireName);
  final sourceRow = source == null ? null : DetailRow('ที่มาของเกณฑ์', source);
  const walking = DetailRow('ขณะนั้น', 'กำลังเดิน (ตรวจจากความเร่ง)');
  final gaitClass = a.gaitClass;
  final confidence = a.gaitConfidence;
  final gait = gaitClass == null
      ? null
      : DetailRow(
          'รูปแบบการเดิน',
          '${gaitClassTh[gaitClass] ?? gaitClass}'
              '${confidence == null ? '' : ' · ความมั่นใจ ${(confidence * 100).round()}%'}',
        );

  switch (code) {
    case AlertCode.tempDelta:
      // The site the alert names: a zone since the 8 sites, forefoot /
      // heel for an alert stored before (whose details also had the other
      // site's ΔT).
      final legacy = a.legacySite;
      final name = channel != null
          ? footLayout.zones[channel].nameTh
          : legacy == null
          ? ''
          : legacyTempSiteTh(legacy);
      final otherName = legacy == null
          ? null
          : legacyTempSiteTh(
              LegacyTempSite.values.firstWhere((x) => x != legacy),
            );
      final leftC = _d(d, 'leftC');
      final rightC = _d(d, 'rightC');
      final consecutive = _d(d, 'consecutive');
      final other = _d(d, 'otherSiteDeltaC');
      // Every site that qualified (largest |ΔT| first, later ones after).
      final sites = TempSiteEntry.listOf(d);
      String siteName(String id) {
        final i = channelOf(id);
        return i == null ? id : footLayout.zones[i].nameTh;
      }
      rows.addAll([
        if (leftC != null && rightC != null)
          DetailRow(name, 'ซ้าย ${_c(leftC)} °C · ขวา ${_c(rightC)} °C'),
        if (value != null)
          DetailRow(
            'ผลต่างที่$name',
            '${_c(value)} °C'
                '${threshold == null ? '' : ' (เกณฑ์ ${_n(threshold)} °C)'}',
          ),
        if (consecutive != null)
          DetailRow(
            'วัดเกินเกณฑ์ติดกัน',
            '${consecutive.round()} ครั้ง (เกณฑ์ ${t.consecutiveReadings} ครั้ง '
                'วัดทุก ${TempLayout.notifyPeriod.inSeconds} วินาที)',
          ),
        if (otherName != null)
          DetailRow(
            'ผลต่างที่$otherName',
            other == null ? '—' : '${_c(other)} °C',
          ),
        // S8D-1 draft.
        if (sites.length > 1)
          DetailRow(
            'จุดที่เกินเกณฑ์',
            '${[for (final e in sites) '${siteName(e.zone)} ${_c(e.deltaC)}'].join(' · ')} °C',
          ),
        level,
        at,
        ?sourceRow,
      ]);
    case AlertCode.pressurePeak:
    case AlertCode.pressureWatch:
      rows.addAll([
        if (value != null)
          DetailRow('ค่าที่วัดได้', '${value.round()} kPa ที่$zone$s'),
        if (threshold != null)
          DetailRow(
            'เกณฑ์',
            code == AlertCode.pressurePeak
                ? '${_n(threshold)} kPa ขณะเดิน'
                : '${_n(threshold)} kPa',
          ),
        if (d?['walking'] == true) walking,
        ?gait,
        level,
        at,
        ?sourceRow,
      ]);
    case AlertCode.pressurePti:
      final steps = _d(d, 'steps');
      final window = _d(d, 'windowMin');
      rows.addAll([
        if (value != null)
          DetailRow(
            'ค่าที่วัดได้',
            '${value.round()} kPa·s เฉลี่ยต่อก้าว ที่$zone$s',
          ),
        if (threshold != null)
          DetailRow('เกณฑ์', '${_n(threshold)} kPa·s เฉลี่ยต่อก้าว ขณะเดิน'),
        if (steps != null && window != null)
          DetailRow(
            'จำนวนก้าวที่ใช้',
            '${steps.round()} ก้าว ใน ${window.round()} นาทีล่าสุด',
          ),
        walking,
        ?gait,
        level,
        at,
        ?sourceRow,
      ]);
    case AlertCode.loadConcentration:
      final steps = _d(d, 'steps');
      rows.addAll([
        if (value != null)
          DetailRow(
            'ค่าที่วัดได้',
            '${value.round()}% ของแรงกดทั้งฝ่าเท้า ที่$zone$s',
          ),
        if (threshold != null)
          DetailRow(
            'เกณฑ์',
            '${_n(threshold)}% ติดกัน ${t.concentrationSteps} ก้าว',
          ),
        if (steps != null)
          DetailRow('จำนวนก้าวที่ใช้', '${steps.round()} ก้าวติดกัน'),
        walking,
        ?gait,
        level,
        at,
        ?sourceRow,
      ]);
    case AlertCode.deviceLost:
      final last = _d(d, 'lastDataAtMs');
      final battery = _d(d, 'lastBatteryPct');
      rows.addAll([
        if (last != null)
          DetailRow(
            'เชื่อมต่อได้ครั้งล่าสุด',
            thaiDateTimeBE(DateTime.fromMillisecondsSinceEpoch(last.round())),
          ),
        if (value != null)
          DetailRow(
            'หลุดการเชื่อมต่อนาน',
            // Raised just past the boundary: whole minutes, rounded up.
            '${value.ceil()} นาที'
                '${threshold == null ? '' : ' (เกณฑ์ ${_n(threshold)} นาที)'}',
          ),
        if (battery != null)
          DetailRow('แบตเตอรี่ครั้งล่าสุด', '${battery.round()}%'),
        level,
      ]);
    case AlertCode.batteryLow:
    case AlertCode.asymmetryPeak:
      rows.addAll([
        if (value != null) DetailRow('ค่าที่วัดได้', _n(value)),
        level,
        at,
        ?sourceRow,
      ]);
  }
  return rows;
}
