import '../ble/packets.dart';
import '../config/foot_layout.dart';
import 'alert_code.dart';

/// The four things a patient can see (FLUTTER-PLAN §7, DESIGN-SPEC §6).
enum PatientLevel { noData, safe, careful, rest }

/// The rule behind a Be-careful or Rest status: alert code + foot side +
/// zone or site, so Home can say in plain Thai what happened.
class StatusCause {
  const StatusCause({
    required this.code,
    required this.side,
    this.channel,
    this.site,
    this.deltaC,
  });

  final AlertCode code;

  /// The foot the rule is about (for `TEMP_DELTA`, the warmer foot).
  final FootSide side;

  /// FSR channel (index into `footLayout.zones`) for pressure codes.
  final int? channel;

  /// Temperature site for `TEMP_DELTA`.
  final TempSite? site;

  /// |ΔT| in °C for `TEMP_DELTA`.
  final double? deltaC;

  @override
  bool operator ==(Object other) =>
      other is StatusCause &&
      other.code == code &&
      other.side == side &&
      other.channel == channel &&
      other.site == site &&
      other.deltaC == deltaC;

  @override
  int get hashCode => Object.hash(code, side, channel, site, deltaC);
}

/// What Home's status card shows. S7's rules engine produces this; until
/// then `interim_status.dart` does (see there for what it checks).
class PatientStatus {
  const PatientStatus._(this.level, this.cause);

  static const noData = PatientStatus._(PatientLevel.noData, null);
  static const safe = PatientStatus._(PatientLevel.safe, null);

  /// The FLUTTER-PLAN §7 mapping for a triggered rule: level 3 → Be
  /// careful, 4–5 → Rest your feet. Levels 1–2 never change the card.
  factory PatientStatus.from(StatusCause cause) {
    final level = cause.code.level;
    if (level >= 4) return PatientStatus._(PatientLevel.rest, cause);
    if (level == 3) return PatientStatus._(PatientLevel.careful, cause);
    throw ArgumentError('level ${cause.code.level} does not set the status');
  }

  final PatientLevel level;
  final StatusCause? cause;

  @override
  bool operator ==(Object other) =>
      other is PatientStatus && other.level == level && other.cause == cause;

  @override
  int get hashCode => Object.hash(level, cause);
}
