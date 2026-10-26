import 'package:flutter/material.dart' show TimeOfDay;

/// Settings › "ขนาดตัวอักษร" (DESIGN-SPEC §10.1). The factor multiplies the
/// phone's own text scale (§14 proposed default, approved for S8B): the
/// preview line is 18 px, so "ใหญ่" is 22/18 and "ใหญ่มาก" 26/18.
enum TextSizeOption {
  normal('ปกติ', 1.0),
  large('ใหญ่', 22 / 18),
  extraLarge('ใหญ่มาก', 26 / 18);

  const TextSizeOption(this.label, this.factor);

  final String label;
  final double factor;
}

/// What the patient sets in Settings. Persisted by `SettingsStore`; the
/// researcher's "Clear app database (test data)" never touches it.
class AppSettings {
  const AppSettings({
    this.name,
    this.textSize = TextSizeOption.normal,
    this.sound = true,
    this.footCheckReminder = true,
    this.reminderTime = defaultReminderTime,
  });

  /// "ทุกวัน 19:00" on the SettingsD board.
  static const defaultReminderTime = TimeOfDay(hour: 19, minute: 0);

  /// "ชื่อที่ใช้ทักทาย"; null or blank = Home says just "สวัสดี".
  final String? name;

  /// Defaults to "ปกติ" (decision 11).
  final TextSizeOption textSize;

  /// "เสียงแจ้งเตือน". Off makes the evening foot-check reminder silent
  /// (S8C, user decision 2); the in-app alert sound arrives in S9.
  /// Research capture cues ignore it.
  final bool sound;

  /// "เตือนให้ดูเท้าทุกวัน" and its time: the evening notification
  /// (`lib/notify/`, S8C).
  final bool footCheckReminder;
  final TimeOfDay reminderTime;

  /// [name] trimmed, or null when blank.
  String? get greetingName {
    final n = name?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  AppSettings copyWith({
    String? Function()? name,
    TextSizeOption? textSize,
    bool? sound,
    bool? footCheckReminder,
    TimeOfDay? reminderTime,
  }) => AppSettings(
    name: name != null ? name() : this.name,
    textSize: textSize ?? this.textSize,
    sound: sound ?? this.sound,
    footCheckReminder: footCheckReminder ?? this.footCheckReminder,
    reminderTime: reminderTime ?? this.reminderTime,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.name == name &&
      other.textSize == textSize &&
      other.sound == sound &&
      other.footCheckReminder == footCheckReminder &&
      other.reminderTime == reminderTime;

  @override
  int get hashCode =>
      Object.hash(name, textSize, sound, footCheckReminder, reminderTime);
}

/// "19:00": 24-hour, as on the board.
String formatReminderTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';
