import 'packets.dart';
import 'parse_result.dart';

/// Where one foot's connection is. Each state is a plain value, so the debug
/// screen (and later the Connection screen) can render it directly.
sealed class LinkState {
  const LinkState();

  /// The insole this foot is bound to, once one has been chosen.
  String? get deviceId;
}

/// Not connected and not trying (nothing chosen yet, or the user
/// disconnected).
final class LinkIdle extends LinkState {
  const LinkIdle({this.deviceId});

  @override
  final String? deviceId;
}

/// Wants to connect, but Bluetooth is off or not permitted.
final class LinkBlocked extends LinkState {
  const LinkBlocked(this.reason, {this.deviceId});

  final BleReadiness reason;

  @override
  final String? deviceId;
}

/// Waiting for the bound insole's advertisement.
final class LinkSearching extends LinkState {
  const LinkSearching({required this.deviceId});

  @override
  final String deviceId;
}

final class LinkConnecting extends LinkState {
  const LinkConnecting({required this.deviceId, required this.step});

  @override
  final String deviceId;
  final ConnectStep step;
}

final class LinkStreaming extends LinkState {
  const LinkStreaming({
    required this.deviceId,
    required this.mtu,
    required this.samplesPerPacket,
    required this.fsrCount,
    required this.since,
  });

  @override
  final String deviceId;
  final int mtu;

  /// 8 normally; 4 when the MTU only fits the contract's fallback packet.
  final int samplesPerPacket;
  final int fsrCount;

  /// Phone time `START_STREAM` was acknowledged.
  final DateTime since;
}

/// A connect attempt failed (or the link dropped); the next attempt is at
/// [retryAt].
final class LinkRetryWait extends LinkState {
  const LinkRetryWait({
    required this.deviceId,
    required this.attempt,
    required this.retryAt,
    required this.lastError,
  });

  @override
  final String deviceId;

  /// Consecutive failed attempts so far (1 = the first failure).
  final int attempt;
  final DateTime retryAt;
  final String lastError;
}

/// Stopped on purpose because connecting again would not help. No automatic
/// reconnect; the user has to act (choose another insole, or retry).
final class LinkProblem extends LinkState {
  const LinkProblem({
    required this.deviceId,
    required this.kind,
    required this.detail,
    this.reportedSide,
    this.mtu,
    this.minMtu,
    this.rejectReason,
  });

  @override
  final String deviceId;
  final ProblemKind kind;

  /// English, for the log and the debug screen.
  final String detail;

  /// [ProblemKind.wrongSide]: the side the insole reported.
  final FootSide? reportedSide;

  /// [ProblemKind.mtuTooSmall]: the negotiated MTU and the smallest usable.
  final int? mtu;
  final int? minMtu;

  /// [ProblemKind.calibrationInvalid]: why the blob was rejected.
  final RejectReason? rejectReason;
}

enum ProblemKind {
  /// Status `foot_side` is the other foot (rule 8).
  wrongSide,

  /// Even the 4-sample fallback packet does not fit; the device would send
  /// nothing at all (report 023), so the app stops instead of waiting.
  mtuTooSmall,

  /// The calibration blob was rejected; there is no safe default curve.
  calibrationInvalid,

  /// Advertised the service UUID but the GATT service is missing.
  notAnInsole,

  /// The other foot is already bound to this insole.
  inUseByOtherFoot,
}

enum ConnectStep {
  connect,
  mtu,
  priority,
  discover,
  status,
  calibration,
  subscribe,
  syncTime,
  start,
}

/// Whether the phone can do BLE at all right now (shared by both feet).
enum BleReadiness {
  checking,
  needsPermission,

  /// Denied with "don't ask again": only the system settings page can fix it.
  permissionDenied,
  bluetoothOff,

  /// No Bluetooth hardware (the Android emulator).
  unavailable,
  ready,
}
