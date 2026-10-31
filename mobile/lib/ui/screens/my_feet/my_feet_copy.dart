import 'package:flutter/foundation.dart';

import '../../../ble/ble_protocol.dart';
import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../device/rolling_peaks.dart';
import '../../../rules/alert_code.dart';
import '../../../rules/alert_copy.dart';
import '../../../rules/alert_engine.dart' show deltaAbove;
import '../../../rules/patient_status.dart';
import '../../../rules/pressure_level.dart';
import '../../clock.dart';
import '../../widgets/details_expander.dart';
import '../../widgets/temp_site_map.dart' show TempSiteMark;
import 'my_feet_model.dart';

// My feet copy (DESIGN-SPEC §8). Banner titles and lines from the boards
// are used as given; a pressure rule's banner is its alert copy
// (`alertCopyFor`, DRAFT health copy until the medical expert reviews it,
// Appendix A). Strings marked "S6B draft" are new in S6B part 2 and are
// listed in Appendix A. Plain Thai first: the numbers live only in the
// details rows.

/// A summary banner (§5): its status look, title, line, and either the
/// "ดูสิ่งที่ควรทำ" link or the "เชื่อมต่อแผ่นรองเท้า" button. The link
/// opens the newest stored alert of [linkCode] about the same foot
/// ([linkSide]) and, for a pressure code, zone ([linkChannel]): the key the
/// engine suppresses repeats by (`TEMP_DELTA` is per foot).
@immutable
class BannerView {
  const BannerView({
    required this.level,
    required this.title,
    required this.line,
    this.linkCode,
    this.linkSide,
    this.linkChannel,
    this.connect = false,
  });

  final PatientLevel level;
  final String title;
  final String line;
  final AlertCode? linkCode;
  final FootSide? linkSide;
  final int? linkChannel;
  final bool connect;

  @override
  bool operator ==(Object other) =>
      other is BannerView &&
      other.level == level &&
      other.title == title &&
      other.line == line &&
      other.linkCode == linkCode &&
      other.linkSide == linkSide &&
      other.linkChannel == linkChannel &&
      other.connect == connect;

  @override
  int get hashCode =>
      Object.hash(level, title, line, linkCode, linkSide, linkChannel, connect);
}

const _noDataBanner = BannerView(
  level: PatientLevel.noData,
  title: 'ยังไม่ได้รับข้อมูล',
  line: 'ต้องเชื่อมต่อแผ่นรองเท้าก่อน',
  connect: true,
);

FootSide? _missingOf(bool left, bool right) => !left
    ? FootSide.left
    : !right
    ? FootSide.right
    : null;

String _foot(FootSide s) => 'เท้า${sideTh(s)}';

/// Temperature site i is zone i (DATA-CONTRACT v1.6).
String _siteTh(int site) => footLayout.zones[site].nameTh;

/// Whole number, or one decimal when it has one ("200", "2.2").
String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

String _c(double v) => v.toStringAsFixed(1);

// --- Pressure (§8.1) --------------------------------------------------------

/// The Pressure banner. A level-3 pressure rule wins over a missing foot,
/// as on Home (BACKLOG 38; user decision 2026-10-25).
BannerView pressureBanner(PressureTabView v) {
  if (!v.left.usable && !v.right.usable) return _noDataBanner;
  final cause = v.cause;
  if (cause != null) {
    final copy = alertCopyFor(
      cause.code,
      side: cause.side,
      channel: cause.channel,
    );
    return BannerView(
      level: PatientLevel.careful,
      title: copy.title,
      line: copy.detail,
      linkCode: cause.code,
      linkSide: cause.side,
      linkChannel: cause.channel,
    );
  }
  final missing = _missingOf(v.left.usable, v.right.usable);
  if (missing != null) {
    // S6B draft: one foot missing (no board).
    return BannerView(
      level: PatientLevel.noData,
      title: 'ยังไม่ได้รับข้อมูล${_foot(missing)}',
      line: 'ต้องเชื่อมต่อแผ่นรองเท้า${sideTh(missing)}ก่อน',
      connect: true,
    );
  }
  return const BannerView(
    level: PatientLevel.safe,
    title: 'แรงกดกระจายดีทั้งสองข้าง',
    line: 'ยังไม่มีจุดใดรับน้ำหนักมากเกินไป',
  );
}

/// One row of "จุดที่รับน้ำหนักมากที่สุดตอนนี้".
@immutable
class ZoneRow {
  const ZoneRow({required this.channel, required this.level, this.side});

  final int channel;
  final PressureLevel level;

  /// The foot, or null for "ทั้งสองข้าง".
  final FootSide? side;

  String get zoneTh => footLayout.zones[channel].nameTh;
  String get sideText => side == null ? 'ทั้งสองข้าง' : _foot(side!);

  @override
  bool operator ==(Object other) =>
      other is ZoneRow &&
      other.channel == channel &&
      other.level == level &&
      other.side == side;

  @override
  int get hashCode => Object.hash(channel, level, side);
}

/// How many zones the list names (§8.1: "the top 3 zones").
const topZoneCount = 3;

/// The most loaded zones of both feet: ranked by the higher kPa of the two
/// feet; "ทั้งสองข้าง" when both feet's zone is at the same level.
List<ZoneRow> topZones(PressureTabView v) {
  final rows = <(int, ZoneRow)>[];
  final feet = [v.left, v.right].where((f) => f.usable).toList();
  if (feet.isEmpty) return const [];
  for (var c = 0; c < footLayout.zones.length; c++) {
    PressureFootView? best;
    for (final f in feet) {
      if (best == null || f.kpa![c] > best.kpa![c]) best = f;
    }
    final level = best!.map.levels![c];
    final same =
        feet.length == 2 && feet.every((f) => f.map.levels![c] == level);
    rows.add((
      best.kpa![c],
      ZoneRow(channel: c, level: level, side: same ? null : best.side),
    ));
  }
  // Stable: equal loads keep the board's zone order.
  rows.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final r in rows.take(topZoneCount)) r.$2];
}

/// "ซ้าย 132 · ขวา 126 kPa"; with [each], the unit follows each number
/// ("ซ้าย 31% · ขวา 30%"). "—" for a foot without the figure.
String _pair(int? left, int? right, String unit, {bool each = false}) {
  if (left == null && right == null) return '—';
  String v(int? x) => x == null ? '—' : (each ? '$x$unit' : '$x');
  return 'ซ้าย ${v(left)} · ขวา ${v(right)}${each ? '' : unit}';
}

/// The rows under the kPa table (§8.1 "ดูตัวเลขละเอียด").
List<DetailRow> pressureDetailRows(PressureTabView v, Thresholds t) {
  final minutes = walkingPeakWindowMs ~/ Duration.millisecondsPerMinute;
  return [
    DetailRow(
      'แรงกดสูงสุดขณะเดิน ($minutes นาทีล่าสุด)',
      _pair(v.left.walkingPeakKpa, v.right.walkingPeakKpa, ' kPa'),
    ),
    DetailRow(
      'แรงกดสะสม (PTI)',
      _pair(v.left.ptiKpaS, v.right.ptiKpaS, ' kPa·s'),
    ),
    DetailRow(
      'น้ำหนักลงจุดเดียวมากที่สุด',
      _pair(v.left.concentrationPct, v.right.concentrationPct, '%', each: true),
    ),
    DetailRow(
      'เกณฑ์',
      'เฝ้าระวัง ${_n(t.watchKpa)} kPa · เตือน ${_n(t.alertKpa)} kPa ขณะเดิน'
          ' · PTI ${_n(t.ptiKpaS)} kPa·s · จุดเดียว ${_n(t.concentrationPct)}%',
    ),
  ];
}

// --- Temperature (§8.2) -----------------------------------------------------

/// "ตั้งแต่ HH:mm" for a foot that gives no data, or "ยังไม่ได้เชื่อมต่อ"
/// when it gave none today. S6B draft for the second.
String _goneSince(FootSide side, DateTime? since) => since == null
    ? '${_foot(side)}ยังไม่ได้เชื่อมต่อ'
    : '${_foot(side)}หลุดการเชื่อมต่อตั้งแต่ ${hhmm(since)}';

/// The Temperature banner. [latestAt] is the newest stored reading today
/// ("วัดล่าสุด"); [since] is when each foot's data stopped.
BannerView tempBanner(
  TempTabView v, {
  required DateTime? latestAt,
  required Map<FootSide, DateTime?> since,
}) {
  if (!v.left.usable && !v.right.usable) return _noDataBanner;
  final missing = _missingOf(v.left.usable, v.right.usable);
  if (missing != null) {
    return BannerView(
      level: PatientLevel.noData,
      title: 'เทียบความอุ่นไม่ได้',
      line: _goneSince(missing, since[missing]),
      connect: true,
    );
  }
  final alert = v.topAlert;
  if (alert != null) {
    final warm = sideTh(alert.warmerSide);
    final other = sideTh(otherSide(alert.warmerSide));
    return BannerView(
      level: PatientLevel.rest,
      title:
          '${_siteTh(alert.site)}$warmอุ่นกว่า$other '
          '${formatDelta(alert.deltaC)}$nbspองศา',
      line: 'ติดต่อกันมาสักพัก',
      linkCode: AlertCode.tempDelta,
      linkSide: alert.warmerSide,
    );
  }
  if (v.noDelta) {
    // Both feet stream but no site has a usable pair (poor contact, sensor
    // fault): never "close" without a number behind it. S6B draft.
    return const BannerView(
      level: PatientLevel.noData,
      title: 'เทียบความอุ่นไม่ได้',
      line: 'ตอนนี้แผ่นรองเท้ายังวัดความอุ่นไม่ได้',
    );
  }
  return BannerView(
    level: PatientLevel.safe,
    title: 'สองข้างอุ่นใกล้เคียงกัน',
    line: latestAt == null ? 'รอผลการวัด' : 'วัดล่าสุด ${hhmm(latestAt)}',
  );
}

/// One temperature site on the Temperature tab (§8.2, layout A): its map
/// dots and, for the top 3, its row in "จุดที่ต่างกันมากที่สุดตอนนี้".
@immutable
class TempSiteView {
  const TempSiteView({
    required this.site,
    this.deltaC,
    this.warmer,
    this.alerting = false,
  });

  /// Zone index.
  final int site;

  /// |ΔT| rounded to 0.1 °C; null when there is no two-foot reading at
  /// this site (rule 4): "ยังวัดไม่ได้", never "close".
  final double? deltaC;

  /// The warmer foot, once one reading is above the threshold (Home's
  /// note rule) or while `TEMP_DELTA` holds; null for "ใกล้เคียงกัน".
  final FootSide? warmer;

  /// `TEMP_DELTA` holds here: the ring on the map, the Rest colour and
  /// icon in the row.
  final bool alerting;

  String get siteTh => _siteTh(site);
  bool get unreadable => deltaC == null;

  /// "เท้าซ้ายอุ่นกว่า" / "ใกล้เคียงกัน" / "ยังวัดไม่ได้". S8D-2 draft.
  String get note => unreadable
      ? 'ยังวัดไม่ได้'
      : warmer == null
      ? 'ใกล้เคียงกัน'
      : '${_foot(warmer!)}อุ่นกว่า';

  /// The dot on [side]'s map.
  TempSiteMark markOn(FootSide side) => unreadable
      ? TempSiteMark.unreadable
      : warmer != side
      ? TempSiteMark.plain
      : alerting
      ? TempSiteMark.warmRinged
      : TempSiteMark.warm;

  /// The row's dot: the warmer foot's.
  TempSiteMark get rowMark => markOn(warmer ?? FootSide.left);

  @override
  bool operator ==(Object other) =>
      other is TempSiteView &&
      other.site == site &&
      other.deltaC == deltaC &&
      other.warmer == warmer &&
      other.alerting == alerting;

  @override
  int get hashCode => Object.hash(site, deltaC, warmer, alerting);
}

/// Each of the 8 sites, in zone order. With a foot missing every site is
/// unreadable (rule 4).
List<TempSiteView> tempSites(TempTabView v, Thresholds t) => [
  for (var i = 0; i < footLayout.zones.length; i++) _tempSite(v, i, t),
];

TempSiteView _tempSite(TempTabView v, int site, Thresholds t) {
  final d = v.bothUsable ? v.delta(site) : null;
  if (d == null) return TempSiteView(site: site);
  final alert = v.alerts[site];
  // The same rule as Home's note: warmer once one reading is above the
  // threshold; the ring only while TEMP_DELTA holds (2 readings).
  final warmer =
      alert?.warmerSide ??
      (deltaAbove(d, t.deltaC)
          ? (d > 0 ? FootSide.left : FootSide.right)
          : null);
  return TempSiteView(
    site: site,
    deltaC: d.abs(),
    warmer: warmer,
    alerting: alert != null,
  );
}

/// How many sites "จุดที่ต่างกันมากที่สุดตอนนี้" names (layout A).
const topSiteCount = 3;

/// The rows of "จุดที่ต่างกันมากที่สุดตอนนี้": sites where `TEMP_DELTA`
/// holds first, then the largest |ΔT|; equal ones keep zone order. Only
/// sites with a two-foot reading; none unless both feet stream.
List<TempSiteView> topSites(TempTabView v, Thresholds t) {
  final sites = [
    for (final s in tempSites(v, t))
      if (!s.unreadable) s,
  ];
  // Stable: List.sort is not, so the zone index breaks ties.
  sites.sort((a, b) {
    if (a.alerting != b.alerting) return a.alerting ? -1 : 1;
    final d = b.deltaC!.compareTo(a.deltaC!);
    return d != 0 ? d : a.site.compareTo(b.site);
  });
  return sites.take(topSiteCount).toList();
}

/// Instead of the top rows when there are none: "ต้องเชื่อมต่อทั้งสองข้าง"
/// with a foot missing, "ยังวัดไม่ได้" when no site can be compared.
/// S8D-2 draft.
String? topSitesEmptyLine(TempTabView v) => !v.bothUsable
    ? 'ต้องเชื่อมต่อทั้งสองข้าง'
    : v.noDelta
    ? 'ยังวัดไม่ได้'
    : null;

/// A map's TalkBack label (S8D-2 draft): "เท้าซ้าย กลางส้นเท้าและส้นเท้า
/// ด้านนอกอุ่นกว่าเท้าขวา", "เท้าซ้าย ใกล้เคียงกับเท้าขวาทุกจุด", or
/// "เท้าซ้าย ยังวัดความอุ่นไม่ได้".
String tempMapLabel(FootSide side, List<TempSiteView> sites) {
  final o = _foot(otherSide(side));
  if (sites.every((s) => s.unreadable)) {
    return '${_foot(side)} ยังวัดความอุ่นไม่ได้';
  }
  final warm = [
    for (final s in sites)
      if (!s.unreadable && s.warmer == side) s.siteTh,
  ];
  final unreadable = sites.where((s) => s.unreadable).length;
  final rest = unreadable == 0 ? '' : ' ยังวัดไม่ได้ $unreadable จุด';
  if (warm.isEmpty) return '${_foot(side)} ใกล้เคียงกับ$oทุกจุดที่วัดได้$rest';
  return '${_foot(side)} ${joinTh(warm)}อุ่นกว่า$o$rest';
}

/// "Lavery et al. (2004)" → "Lavery et al., 2004", to sit inside the
/// threshold row's brackets; any other form is kept as stored.
String citation(String source) {
  final m = RegExp(r'^(.*) \((\d{4})\)$').firstMatch(source);
  return m == null ? source : '${m[1]}, ${m[2]}';
}

String _tempThresholdRow(Thresholds t) {
  final source = t.sourceOf('TEMP_DELTA');
  return 'ผลต่าง ${_n(t.deltaC)} °C ติดกัน ${t.consecutiveReadings} ครั้ง'
      '${source == null ? '' : ' (${citation(source)})'}';
}

String _cOr(double? v) => v == null ? '—' : _c(v);

String _qualityTh(TempQuality q) => switch (q) {
  TempQuality.normal => 'ดี',
  TempQuality.poorContact => 'สัมผัสไม่ดี',
  TempQuality.sensorFault => 'เซนเซอร์ผิดปกติ',
};

/// The Temperature details rows (§8.2) under the table "อุณหภูมิตอนนี้
/// (°C)" ([TempTableRow]). [latestAt] is the newest stored reading today;
/// [since] is when each foot's data stopped.
List<DetailRow> tempDetailRows(
  TempTabView v,
  Thresholds t, {
  required DateTime? latestAt,
  required Map<FootSide, DateTime?> since,
}) {
  final threshold = DetailRow('เกณฑ์', _tempThresholdRow(t));
  String gone(FootSide s) {
    final at = since[s];
    return at == null ? 'ยังไม่ได้เชื่อมต่อ' : 'ไม่มีข้อมูลตั้งแต่ ${hhmm(at)}';
  }

  if (!v.bothUsable) {
    return [
      for (final f in [v.left, v.right])
        if (!f.usable) DetailRow(_foot(f.side), gone(f.side)),
      threshold,
    ];
  }

  final period = TempLayout.notifyPeriod.inSeconds;
  final latest = latestAt == null ? '' : ' · ล่าสุด ${hhmmss(latestAt)}';
  // "ดีทั้ง 16 จุด" only when every site of both feet has a normal
  // reading; a foot with no reading yet, or a site the sensor could not
  // read, is named (rule 5: no data never reads as good).
  final bad = [
    for (final f in [v.left, v.right])
      if (f.quality.isEmpty)
        '${_foot(f.side)} ยังวัดไม่ได้'
      else
        for (var i = 0; i < f.quality.length; i++)
          if (f.quality[i] != TempQuality.normal)
            '${_foot(f.side)} ${_siteTh(i)} ${_qualityTh(f.quality[i])}'
          else if (f.at(i) == null)
            '${_foot(f.side)} ${_siteTh(i)} ยังวัดไม่ได้',
  ];
  final counted = [
    for (final a in v.alerts.values)
      if (a.consecutive != null) a,
  ];
  return [
    if (counted.isNotEmpty)
      DetailRow(
        'วัดเกินเกณฑ์ติดกัน',
        [
          for (final a in counted)
            '${_siteTh(a.site)} ${a.consecutive} ครั้ง '
                '(เกณฑ์ ${t.consecutiveReadings} ครั้ง)',
        ].join(' · '),
      ),
    DetailRow('วัดทุก', '$period วินาที$latest'),
    threshold,
    DetailRow(
      'คุณภาพสัญญาณ',
      bad.isEmpty
          ? 'ดีทั้ง ${FootSide.values.length * TempLayout.siteCount} จุด'
          : bad.join(' · '),
    ),
  ];
}

/// One row of the table "อุณหภูมิตอนนี้ (°C)" (§8.2): จุด / ซ้าย / ขวา /
/// ต่าง, "—" where a value is missing ("ต่าง" needs both feet, rule 4).
@immutable
class TempTableRow {
  const TempTableRow(this.site, this.left, this.right, this.delta);

  final String site;
  final String left;
  final String right;
  final String delta;

  @override
  bool operator ==(Object other) =>
      other is TempTableRow &&
      other.site == site &&
      other.left == left &&
      other.right == right &&
      other.delta == delta;

  @override
  int get hashCode => Object.hash(site, left, right, delta);
}

/// The 8 table rows; empty when neither foot streams.
List<TempTableRow> tempTable(TempTabView v) => !v.left.usable && !v.right.usable
    ? const []
    : [
        for (var i = 0; i < footLayout.zones.length; i++)
          TempTableRow(
            _siteTh(i),
            _cOr(v.left.at(i)),
            _cOr(v.right.at(i)),
            v.bothUsable ? _cOr(v.delta(i)?.abs()) : '—',
          ),
      ];
