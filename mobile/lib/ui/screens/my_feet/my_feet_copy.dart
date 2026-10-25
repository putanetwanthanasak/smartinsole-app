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
import 'my_feet_model.dart';

// My feet copy (DESIGN-SPEC §8). Banner titles and lines from the boards
// are used as given; a pressure rule's banner is its alert copy
// (`alertCopyFor`, DRAFT health copy until the medical expert reviews it,
// Appendix A). Strings marked "S6B draft" are new in S6B part 2 and are
// listed in Appendix A. Plain Thai first: the numbers live only in the
// details rows.

/// A summary banner (§5): its status look, title, line, and either the
/// "ดูสิ่งที่ควรทำ" link (to the newest alert of [linkCode]) or the
/// "เชื่อมต่อแผ่นรองเท้า" button.
@immutable
class BannerView {
  const BannerView({
    required this.level,
    required this.title,
    required this.line,
    this.linkCode,
    this.connect = false,
  });

  final PatientLevel level;
  final String title;
  final String line;
  final AlertCode? linkCode;
  final bool connect;

  @override
  bool operator ==(Object other) =>
      other is BannerView &&
      other.level == level &&
      other.title == title &&
      other.line == line &&
      other.linkCode == linkCode &&
      other.connect == connect;

  @override
  int get hashCode => Object.hash(level, title, line, linkCode, connect);
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

String _siteTh(TempSite site) =>
    footLayout.tempSites.firstWhere((t) => t.site == site).nameTh;

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
    );
  }
  if (v.deltaForefootC == null && v.deltaHeelC == null) {
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

/// One site card (§8.2).
@immutable
class SiteCardView {
  const SiteCardView({
    required this.site,
    required this.note,
    this.deltaC,
    this.alerting = false,
  });

  final TempSite site;

  /// |ΔT| rounded to 0.1 °C; null shows "—" (rule 4).
  final double? deltaC;

  /// `TEMP_DELTA` holds here: the Rest colour, icon and red site dot.
  final bool alerting;
  final String note;

  String get siteTh => _siteTh(site);
  bool get missing => deltaC == null;

  @override
  bool operator ==(Object other) =>
      other is SiteCardView &&
      other.site == site &&
      other.deltaC == deltaC &&
      other.alerting == alerting &&
      other.note == note;

  @override
  int get hashCode => Object.hash(site, deltaC, alerting, note);
}

SiteCardView siteCard(TempTabView v, TempSite site, Thresholds t) {
  final d = v.bothUsable ? v.delta(site) : null;
  if (d == null) {
    return SiteCardView(
      site: site,
      // S6B draft: both feet stream but this site cannot be compared.
      note: v.bothUsable ? 'ยังวัดไม่ได้' : 'ต้องเชื่อมต่อทั้งสองข้าง',
    );
  }
  final alert = v.alerts[site];
  final warmer = d > 0 ? FootSide.left : FootSide.right;
  // The same rule as Home's note: warmer once one reading is above the
  // threshold; the Rest look only while TEMP_DELTA holds (2 readings).
  final over = deltaAbove(d, t.deltaC);
  return SiteCardView(
    site: site,
    deltaC: d.abs(),
    alerting: alert != null,
    note: alert != null
        ? '${sideTh(alert.warmerSide)}อุ่นกว่า'
        : over
        ? '${sideTh(warmer)}อุ่นกว่า'
        : 'ใกล้เคียงกัน',
  );
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

/// The Temperature details rows (§8.2). [latestAt] is the newest stored
/// reading today; [since] is when each foot's data stopped.
List<DetailRow> tempDetailRows(
  TempTabView v,
  Thresholds t, {
  required DateTime? latestAt,
  required Map<FootSide, DateTime?> since,
}) {
  final threshold = DetailRow('เกณฑ์', _tempThresholdRow(t));
  if (!v.bothUsable) {
    String gone(FootSide s) {
      final at = since[s];
      return at == null
          ? 'ยังไม่ได้เชื่อมต่อ'
          : 'ไม่มีข้อมูลตั้งแต่ ${hhmm(at)}';
    }

    return [
      for (final f in [v.left, v.right])
        f.usable
            ? DetailRow(
                'อุณหภูมิล่าสุด (${_foot(f.side)})',
                'หน้าเท้า ${_cOr(f.forefootC)} · ส้นเท้า ${_cOr(f.heelC)} °C',
              )
            : DetailRow(_foot(f.side), gone(f.side)),
      threshold,
    ];
  }
  String sites(TempSite s) {
    double? at(TempFootView f) =>
        s == TempSite.forefoot ? f.forefootC : f.heelC;
    return 'ซ้าย ${_cOr(at(v.left))} · ขวา ${_cOr(at(v.right))} °C';
  }

  String delta(TempSite s) {
    final d = v.delta(s);
    return '${_siteTh(s)} ${d == null ? '—' : '${_c(d.abs())} °C'}';
  }

  final period = TempLayout.notifyPeriod.inSeconds;
  final latest = latestAt == null ? '' : ' · ล่าสุด ${hhmmss(latestAt)}';
  final bad = [
    for (final f in [v.left, v.right])
      if (f.quality != null && f.quality != TempQuality.normal)
        '${_foot(f.side)} ${_qualityTh(f.quality!)}',
  ];
  return [
    DetailRow('หน้าเท้าตอนนี้', sites(TempSite.forefoot)),
    DetailRow('ส้นเท้าตอนนี้', sites(TempSite.heel)),
    DetailRow(
      'ผลต่าง',
      '${delta(TempSite.forefoot)} · ${delta(TempSite.heel)}',
    ),
    if (v.alerts.isNotEmpty)
      DetailRow(
        'วัดเกินเกณฑ์ติดกัน',
        [
          for (final a in v.alerts.values)
            '${_siteTh(a.site)} ${a.consecutive} ครั้ง '
                '(เกณฑ์ ${t.consecutiveReadings} ครั้ง)',
        ].join(' · '),
      ),
    DetailRow('วัดทุก', '$period วินาที$latest'),
    threshold,
    DetailRow(
      'คุณภาพสัญญาณ',
      bad.isEmpty
          ? 'ดีทั้ง ${FootSide.values.length * TempSite.values.length} จุด'
          : bad.join(' · '),
    ),
  ];
}
