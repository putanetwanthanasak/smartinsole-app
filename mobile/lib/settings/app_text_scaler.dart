import 'package:flutter/widgets.dart';

/// The phone's own text scaler times the app's "ขนาดตัวอักษร" factor
/// (DESIGN-SPEC §14): the phone's scaling (linear or Android 14's
/// nonlinear curve) is applied first, then the factor. Never clamped.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);

  final TextScaler system;
  final double factor;

  /// [system] unchanged at factor 1, so "ปกติ" is exactly the phone's
  /// own scaling.
  static TextScaler combine(TextScaler system, double factor) =>
      factor == 1.0 ? system : AppTextScaler(system, factor);

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @Deprecated('Use scale() instead.')
  @override
  double get textScaleFactor =>
      // ignore: deprecated_member_use
      system.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);

  @override
  String toString() => 'AppTextScaler($system × $factor)';
}
