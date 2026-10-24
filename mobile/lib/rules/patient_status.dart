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

  /// Short id for logs and tests.
  String get key => alertKey(code, side, channel: channel, site: site);

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

/// Code + side + zone or site: what the 30-minute repeat suppression
/// (contract §8.5) counts as "the same alert".
String alertKey(
  AlertCode code,
  FootSide? side, {
  int? channel,
  TempSite? site,
}) => '${code.name}|${side?.name ?? ''}|${channel ?? ''}|${site?.name ?? ''}';

/// What Home's status card shows, from the alert engine
/// (`alert_engine.dart`).
class PatientStatus {
  const PatientStatus._(this.level, this.cause, [this.missingSide]);

  static const noData = PatientStatus._(PatientLevel.noData, null);
  static const safe = PatientStatus._(PatientLevel.safe, null);

  /// No data because [side] gives none while the other foot does, and the
  /// other foot has nothing at level 3 or above (BACKLOG 38).
  const PatientStatus.missing(FootSide side)
    : this._(PatientLevel.noData, null, side);

  /// The FLUTTER-PLAN §7 mapping for a triggered rule: level 3 → Be
  /// careful, 4–5 → Rest your feet. Levels 1–2 never change the card.
  factory PatientStatus.from(StatusCause cause) {
    final level = patientLevelFor(cause.code.level);
    if (level == null) {
      throw ArgumentError('level ${cause.code.level} does not set the status');
    }
    return PatientStatus._(level, cause);
  }

  final PatientLevel level;
  final StatusCause? cause;

  /// For No data with one foot reporting: the foot that is missing.
  final FootSide? missingSide;

  @override
  bool operator ==(Object other) =>
      other is PatientStatus &&
      other.level == level &&
      other.cause == cause &&
      other.missingSide == missingSide;

  @override
  int get hashCode => Object.hash(level, cause, missingSide);
}

/// FLUTTER-PLAN §7 for one internal level: 4–5 → Rest your feet, 3 → Be
/// careful; null for 1–2, which never set the status card (level 2 shows
/// as orange dots and notes, `BATTERY_LOW` as the low-battery chip, and
/// `DEVICE_LOST` as No data because its foot gives no data).
PatientLevel? patientLevelFor(int level) {
  if (level < carefulLevel) return null;
  return level < restLevel ? PatientLevel.careful : PatientLevel.rest;
}
