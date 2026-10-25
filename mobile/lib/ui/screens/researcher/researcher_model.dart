import 'dart:io';

import 'package:intl/intl.dart';

import '../../../ble/link_state.dart';
import '../../../ble/packets.dart';
import '../../../capture/capture_protocol.dart';
import '../../../capture/capture_session.dart';
import '../../../device/display_snapshot.dart';

/// One readiness check on the "เก็บข้อมูลวิจัย" card (DESIGN-SPEC §10.2).
class ReadinessCheck {
  const ReadinessCheck(this.text, {required this.ok});

  final String text;
  final bool ok;
}

String _side(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

/// The three checks of §10.2. A failed check gets a reason in brackets
/// (draft); a check that passes reads as on the board. Any failure
/// disables "เริ่มเก็บข้อมูลวิจัย" (§14 proposed default).
List<ReadinessCheck> readinessChecks(
  DisplaySnapshot? snap,
  double? Function(FootSide) rate,
) {
  FootView view(FootSide s) =>
      snap?.of(s) ?? FootView(side: s, connection: FootConnection.notConnected);

  final missing = [
    for (final s in FootSide.values)
      if (!view(s).usable) _side(s),
  ];
  final connected = ReadinessCheck(
    missing.isEmpty
        ? 'เชื่อมต่อแล้วทั้งสองข้าง'
        : 'เชื่อมต่อแล้วทั้งสองข้าง (ยังไม่ได้เชื่อมต่อ: ${missing.join(' · ')})',
    ok: missing.isEmpty,
  );

  const min = CaptureTimings.minBatteryPct;
  String pct(FootSide s) {
    final b = view(s).usable ? view(s).batteryPct : null;
    return '${_side(s)} ${b == null ? '—' : '$b%'}';
  }

  bool batteryOk(FootSide s) {
    final b = view(s).batteryPct;
    return view(s).usable && b != null && b >= min;
  }

  final battery = ReadinessCheck(
    'แบตเตอรี่ $min% ขึ้นไปทั้งสองข้าง '
    '(${pct(FootSide.left)} · ${pct(FootSide.right)})',
    ok: FootSide.values.every(batteryOk),
  );

  final rates = {for (final s in FootSide.values) s: rate(s)};
  final rateOk = FootSide.values.every(
    (s) =>
        view(s).usable &&
        rates[s] != null &&
        rates[s]! >= CaptureTimings.minSampleRateHz,
  );
  final String rateNote;
  if (rateOk) {
    rateNote = '';
  } else if (rates.values.any((r) => r == null)) {
    rateNote = ' (กำลังวัด)';
  } else {
    rateNote =
        ' (${[for (final s in FootSide.values) '${_side(s)} ${rates[s]!.toStringAsFixed(0)}'].join(' · ')})';
  }
  final rateCheck = ReadinessCheck(
    'รับข้อมูลครบ 50 ครั้งต่อวินาทีทั้งสองข้าง$rateNote',
    ok: rateOk,
  );
  return [connected, battery, rateCheck];
}

/// "ล่าสุด S07 · 21 ต.ค. · 6 ไฟล์" for the newest session on the phone.
String exportLine(List<SessionListing> sessions) {
  if (sessions.isEmpty) return 'ยังไม่มีข้อมูลวิจัยในเครื่องนี้';
  final s = sessions.first;
  final code = s.sessionId.split('_').first;
  final date = DateFormat(
    'd MMM',
    'th',
  ).format(DateTime.fromMillisecondsSinceEpoch(s.createdUnixMs));
  final files = s.dir.existsSync()
      ? s.dir.listSync(recursive: true).whereType<File>().length
      : 0;
  return 'ล่าสุด $code · $date · $files ไฟล์';
}

/// "ซ้าย 1.0.3 · ขวา 1.0.3": each foot's value, "—" when unknown.
String perFoot(String? Function(FootSide) value) =>
    [for (final s in FootSide.values) '${_side(s)} ${value(s) ?? '—'}']
        .join(' · ');

/// One value when both feet agree, as on the board ("247", "50
/// ครั้ง/วินาที ต่อข้าง"), else [perFoot] ("ซ้าย 50 · ขวา 31 ครั้ง/วินาที").
/// [unit] follows the value(s); [bothNote] follows only the single value.
String agreedOrPerFoot(
  String? Function(FootSide) value, {
  String unit = '',
  String bothNote = '',
}) {
  final l = value(FootSide.left);
  if (l != null && l == value(FootSide.right)) return '$l$unit$bothNote';
  return '${perFoot(value)}$unit';
}

/// The negotiated MTU of a streaming link.
int? mtuOf(LinkState s) => s is LinkStreaming ? s.mtu : null;
