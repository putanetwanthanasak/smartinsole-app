# lib/notify/

The evening foot-check reminder (S8C, DESIGN-SPEC §11.8): a system
notification while "เตือนให้ดูเท้าทุกวัน" is on.

| File | What |
|---|---|
| `reminder_plan.dart` | Pure: the next 14 reminder times (today skipped once checked), ids `yyyymmdd`, `TZDateTime` in `tz.local` |
| `time_zone.dart` | Sets `tz.local` to the phone's zone (`flutter_timezone`), never UTC; falls back to a fixed offset |
| `reminder_notifier.dart` | `ReminderNotifier` interface (fake in `test/helpers/`) |
| `local_reminder_notifier.dart` | The only `flutter_local_notifications` importer: two channels (normal, silent), one-shot inexact alarms, permission and settings |
| `reminder_providers.dart` | `ReminderService` (start, sync on settings / today's check changes), `notificationsAllowedProvider` |

Rules:
- Recomputed at app start, on resume, after a save, and on any switch, time
  or sound change; the plugin's boot receiver restores them after a reboot
  (not after a force stop: Android sends no boot broadcast to a stopped
  app).
- Sound off → the silent channel (a channel's sound can't change once made).
- Inexact (`inexactAllowWhileIdle`): no exact-alarm permission; Android may
  deliver a few minutes late.
- A tapped reminder, or a launch from one, opens the "ตรวจเท้า" tab.
