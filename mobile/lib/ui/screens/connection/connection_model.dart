import '../../../ble/foot_connector.dart';
import '../../../ble/link_state.dart';
import '../../../ble/packets.dart';
import '../../../device/display_snapshot.dart';

/// The states of one foot card on Connection (DESIGN-SPEC §9).
enum CardKind {
  notConnected,
  searching,
  connecting,
  connected,

  /// Rule 8: the insole found reports the other foot.
  wrongSide,
  notFound,

  /// "เชื่อมต่อแล้ว แต่ยังไม่ได้รับข้อมูล": MTU too small, calibration
  /// rejected, or streaming but stale (user decision 5A).
  connectedNoData,

  /// "รอเปิดบลูทูธ".
  bluetoothOff,

  /// Bluetooth not permitted (user decision 4A, draft copy).
  waitingPermission,
}

/// What the screen shows above the cards instead of the info box.
enum PhonePanel { none, bluetoothOff, permission, permissionSettings }

class FootCardState {
  const FootCardState({
    required this.side,
    required this.kind,
    this.progress,
    this.reportedSide,
    this.batteryPct,
    this.firmware,
    this.lowBattery = false,
  });

  final FootSide side;
  final CardKind kind;

  /// [CardKind.connecting]: share of the connect sequence done (0–1), one
  /// step per FLUTTER-PLAN §5 step.
  final double? progress;

  /// [CardKind.wrongSide]: the side the insole reported.
  final FootSide? reportedSide;

  /// [CardKind.connected]: from the insole's status.
  final int? batteryPct;
  final String? firmware;
  final bool lowBattery;

  @override
  bool operator ==(Object other) =>
      other is FootCardState &&
      other.side == side &&
      other.kind == kind &&
      other.progress == progress &&
      other.reportedSide == reportedSide &&
      other.batteryPct == batteryPct &&
      other.firmware == firmware &&
      other.lowBattery == lowBattery;

  @override
  int get hashCode => Object.hash(
    side,
    kind,
    progress,
    reportedSide,
    batteryPct,
    firmware,
    lowBattery,
  );
}

/// The phone-level panel for [readiness]. The emulator without Bluetooth
/// hardware ([BleReadiness.unavailable]) is shown as Bluetooth off.
PhonePanel panelOf(BleReadiness readiness) => switch (readiness) {
  BleReadiness.bluetoothOff ||
  BleReadiness.unavailable => PhonePanel.bluetoothOff,
  BleReadiness.needsPermission => PhonePanel.permission,
  BleReadiness.permissionDenied => PhonePanel.permissionSettings,
  BleReadiness.checking || BleReadiness.ready => PhonePanel.none,
};

/// Share of the connect sequence done once [step] has started.
double progressOf(ConnectStep step) =>
    (step.index + 1) / (ConnectStep.values.length + 1);

/// One foot's card, from the phone's readiness, the finder, the foot's
/// link and its 10 Hz view (connection derived at read time, rule 2).
FootCardState cardStateOf({
  required FootSide side,
  required BleReadiness readiness,
  required FinderState finder,
  required LinkState link,
  required FootView view,
  required double batteryLowPct,
}) {
  FootCardState of(CardKind kind, {double? progress, FootSide? reported}) =>
      FootCardState(
        side: side,
        kind: kind,
        progress: progress,
        reportedSide: reported,
      );

  switch (panelOf(readiness)) {
    case PhonePanel.bluetoothOff:
      return of(CardKind.bluetoothOff);
    case PhonePanel.permission || PhonePanel.permissionSettings:
      return of(CardKind.waitingPermission);
    case PhonePanel.none:
      break;
  }

  switch (finder) {
    case FinderWrongSide(:final reportedSide):
      return of(CardKind.wrongSide, reported: reportedSide);
    case FinderNotFound():
      return of(CardKind.notFound);
    case FinderSearching():
      return link is LinkConnecting
          ? of(CardKind.connecting, progress: progressOf(link.step))
          : of(CardKind.searching);
    case FinderIdle():
      break;
  }

  return switch (link) {
    LinkIdle() => of(CardKind.notConnected),
    LinkBlocked(reason: BleReadiness.bluetoothOff) => of(CardKind.bluetoothOff),
    // An automatic reconnect waiting for the insole (user decision 5A).
    LinkBlocked() ||
    LinkSearching() ||
    LinkRetryWait() => of(CardKind.searching),
    LinkConnecting(:final step) => of(
      CardKind.connecting,
      progress: progressOf(step),
    ),
    LinkStreaming() => switch (view.connection) {
      FootConnection.streaming => FootCardState(
        side: side,
        kind: CardKind.connected,
        batteryPct: view.batteryPct,
        firmware: view.firmware,
        lowBattery: view.batteryPct != null && view.batteryPct! < batteryLowPct,
      ),
      FootConnection.stale => of(CardKind.connectedNoData),
      // Started, first sample not here yet: the sequence's last step.
      _ => of(CardKind.connecting, progress: 1),
    },
    LinkProblem(kind: ProblemKind.wrongSide, :final reportedSide) => of(
      CardKind.wrongSide,
      reported: reportedSide,
    ),
    LinkProblem(kind: ProblemKind.mtuTooSmall) ||
    LinkProblem(
      kind: ProblemKind.calibrationInvalid,
    ) => of(CardKind.connectedNoData),
    LinkProblem() => of(CardKind.notFound),
  };
}

/// Both feet connected: the info box hides and "เสร็จแล้ว กลับหน้าวันนี้"
/// appears (§9).
bool bothConnected(FootCardState l, FootCardState r) =>
    l.kind == CardKind.connected && r.kind == CardKind.connected;

/// The info box shows until both feet are connected, except while
/// Bluetooth is off or a wrong-side message is showing (§9).
bool showInfoBox(PhonePanel panel, FootCardState l, FootCardState r) =>
    panel == PhonePanel.none &&
    !bothConnected(l, r) &&
    l.kind != CardKind.wrongSide &&
    r.kind != CardKind.wrongSide;

// --- Copy (DESIGN-SPEC §9; the permission panel is draft, decision 4A) -----

abstract final class ConnectionCopy {
  static const title = 'เชื่อมต่อแผ่นรองเท้า';
  static const subtitle = 'เชื่อมต่อทีละข้าง ซ้ายและขวา';
  static const info =
      'เปิดสวิตช์ที่กล่องอุปกรณ์บนส้นรองเท้า ให้ไฟติด แล้ววางโทรศัพท์ไว้ใกล้ ๆ';
  static const done = 'เสร็จแล้ว กลับหน้าวันนี้';

  static const btOffTitle = 'บลูทูธของโทรศัพท์ปิดอยู่';
  static const btOffLine = 'เปิดบลูทูธก่อน แล้วค่อยเชื่อมต่อแผ่นรองเท้า';
  static const btOffButton = 'เปิดบลูทูธ';

  // Draft (not on the boards; user decision 4A, S8B).
  static const permissionTitle = 'แอปยังไม่ได้รับอนุญาตให้ใช้บลูทูธ';
  static const permissionLine =
      'อนุญาตให้แอปค้นหาอุปกรณ์ใกล้เคียง แล้วค่อยเชื่อมต่อแผ่นรองเท้า';
  static const permissionButton = 'อนุญาตให้ใช้บลูทูธ';
  static const permissionSettingsButton = 'เปิดการตั้งค่า';
  static const waitingPermission = 'รออนุญาตให้ใช้บลูทูธ';

  static String foot(FootSide s) => s == FootSide.left ? 'เท้าซ้าย' : 'เท้าขวา';
  static String side(FootSide s) => s == FootSide.left ? 'ซ้าย' : 'ขวา';

  static String status(FootCardState c) => switch (c.kind) {
    CardKind.notConnected => 'ยังไม่ได้เชื่อมต่อ',
    CardKind.searching => 'กำลังค้นหา…',
    CardKind.connecting => 'พบแล้ว กำลังเชื่อมต่อ…',
    CardKind.connected => 'เชื่อมต่อแล้ว',
    CardKind.wrongSide => 'แผ่นที่พบเป็นของ${foot(c.reportedSide!)}',
    CardKind.notFound => 'ไม่พบแผ่นรองเท้า',
    CardKind.connectedNoData => 'เชื่อมต่อแล้ว แต่ยังไม่ได้รับข้อมูล',
    CardKind.bluetoothOff => 'รอเปิดบลูทูธ',
    CardKind.waitingPermission => waitingPermission,
  };

  /// "แบต {n}% · เฟิร์มแวร์ {version}"; the parts not known yet are left out.
  static String? connectedLine(FootCardState c) {
    final parts = [
      if (c.batteryPct != null) 'แบต ${c.batteryPct}%',
      if (c.firmware != null) 'เฟิร์มแวร์ ${c.firmware}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String wrongSideMessage(FootCardState c) =>
      'ใส่แผ่นนี้ที่รองเท้าข้าง${side(c.reportedSide!)} '
      'หรือเปิดแผ่นของ${foot(c.side)}แล้วค้นหาอีกครั้ง';

  static const notFoundSteps = [
    'ตรวจว่าไฟที่กล่องอุปกรณ์ติดอยู่',
    'ถ้าไฟไม่ติด ให้ชาร์จแบตเตอรี่ก่อน',
    'วางโทรศัพท์ไว้ใกล้แผ่นรองเท้า',
  ];

  static const noDataMessage =
      'ลองยกเลิกการเชื่อมต่อ แล้วเชื่อมต่อใหม่อีกครั้ง';

  static String connectButton(FootSide s) => 'เชื่อมต่อ${foot(s)}';
  static const stop = 'หยุดค้นหา';
  static const disconnect = 'ยกเลิกการเชื่อมต่อ';
  static const searchAgain = 'ค้นหาอีกครั้ง';
  static const reconnect = 'เชื่อมต่อใหม่';
  static const connectingLabel = 'กำลังเชื่อมต่อ';
}
