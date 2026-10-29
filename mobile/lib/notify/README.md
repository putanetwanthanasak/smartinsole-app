# lib/notify/

The evening foot-check reminder (S8C, DESIGN-SPEC §11.8): a system
notification while "เตือนให้ดูเท้าทุกวัน" is on.

| File | What |
|---|---|
| `reminder_plan.dart` | Pure: the next 14 reminder times (today skipped once checked), ids `yyyymmdd`, `TZDateTime` in `tz.local` |
| `time_zone.dart` | Sets `tz.local` to the phone's zone (`flutter_timezone`), never UTC; falls back to a fixed offset |
| `reminder_notifier.dart` | `ReminderNotifier` interface (fake in `test/helpers/`) |
| `local_reminder_notifier.dart` | The only `flutter_local_notifications` importer: two channels (normal, silent) created in `init`, one-shot inexact alarms; `NotificationAccess` on MainActivity's `smartinsole/notifications` channel (status, the app's notification settings page) |
| `notification_access.dart` | Pure: whether a reminder would show, on every API level (app switch, Android 13+ permission, app-op); prompt only on 13+ |
| `android_resources.dart` | Resource names looked up at runtime (kept in release builds) |
| `reminder_providers.dart` | `ReminderService` (start, sync on settings / today's check changes), `notificationsAllowedProvider` |

Rules:
- Recomputed at app start, on resume, after a save, and on any switch, time
  or sound change; the plugin's boot receiver restores them after a reboot
  (not after a force stop: Android sends no boot broadcast to a stopped
  app).
- Sound off → the silent channel (a channel's sound can't change once made).
- Inexact (`inexactAllowWhileIdle`): no exact-alarm permission. Alarms set
  a day or more ahead get a window of up to 1 hour (Note 10: +1 h), so
  19:00 may come as late as 20:00 (DESIGN-SPEC §11.8; accepted for now).
- Blocked = the phone would not show it, on any API level
  (`notificationsAllowedProvider`, the one state Settings, Saved and the
  service read). Re-checked on resume and at each sync. Reminders stay
  scheduled while blocked. Each check is logged
  (`reminder: notifications allowed|blocked (sdk=… enabled=… …)`).
- A tapped reminder, or a launch from one, opens the "ตรวจเท้า" tab.
- The small icon `ic_stat_foot_check` is looked up by name, so it is a
  constant in `android_resources.dart` and kept in
  `android/app/src/main/res/raw/keep.xml`; the release build's resource
  shrinker drops it otherwise (S8C, Note 10). See "Release resources" in
  `mobile/CLAUDE.md`.
