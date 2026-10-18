/// Why a packet or calibration blob was not accepted. Every parser returns a
/// [ParseResult], so a rejection is never silent: the BLE layer can count
/// and log rejections per foot by reason.
enum RejectReason {
  /// Shorter than the packet's header or fixed size.
  tooShort,

  /// The header's `count` needs more bytes than arrived (MTU not negotiated,
  /// or the wrong FSR count for this insole).
  truncated,

  /// More bytes than the header's `count` accounts for. Most likely the
  /// packet was parsed with the wrong FSR count, which would put readings on
  /// the wrong foot zones.
  lengthMismatch,

  /// Status `foot_side` is not 0 (left) or 1 (right).
  invalidFootSide,

  /// Status `state` is not 0, 1 or 2.
  invalidState,

  /// Temperature `quality` is not 0, 1 or 2.
  invalidQuality,

  calibrationNotJson,
  calibrationNotObject,

  /// A required field is missing or has the wrong type.
  calibrationMissingField,
  calibrationNoChannels,

  /// `r_pulldown_ohm` or `sensor_area_m2` is not positive.
  calibrationInvalidValue,

  /// Channel indexes are not exactly 0..N−1, each once.
  calibrationBadChannelIndex,
}

sealed class ParseResult<T> {
  const ParseResult();
}

final class Parsed<T> extends ParseResult<T> {
  const Parsed(this.value);
  final T value;
}

final class Rejected<T> extends ParseResult<T> {
  const Rejected(
    this.reason,
    this.detail, {
    this.expectedBytes,
    this.actualBytes,
  });

  final RejectReason reason;

  /// Human-readable detail for logs.
  final String detail;

  /// Set for [RejectReason.tooShort], [RejectReason.truncated] and
  /// [RejectReason.lengthMismatch].
  final int? expectedBytes;
  final int? actualBytes;

  @override
  String toString() => 'Rejected(${reason.name}: $detail)';
}
