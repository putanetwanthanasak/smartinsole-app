# lib/storage/

Local storage (S6A): SQLite through drift, schema v1, behind one repository
interface per area. Screens and services use the providers in
`storage_providers.dart` and the plain models in `models.dart`; nothing
outside this folder imports drift or `database.dart`'s row types.

| File | What |
|---|---|
| `database.dart` | Tables, `AppDatabase` (file in app-private support dir, or in memory) |
| `models.dart` | `AlertKind` (8 contract codes + foot-check finding, `patientVisible`), models, `retentionPeriod`, `captureStampOf` |
| `local_date.dart` | UTC ms → local `YYYY-MM-DD` |
| `alert_repository.dart` | `AlertRepository`: add, list/unread (one visibility rule), mark read, per capture |
| `temperature_repository.dart` | `TemperatureRepository`: every 30 s reading per foot |
| `daily_summary_repository.dart` | `DailySummaryRepository`: max ΔT, alert counts, foot-check flag, activity (S8A) |
| `foot_check_repository.dart` | `FootCheckRepository`: save (result decided here, rule 14) |
| `retention.dart` | 30-day retention + its daily schedule |
| `temperature_recorder.dart` | `DeviceManager.temps` → database |
| `storage_host.dart` | Keeps the recorder and retention running; resume hook |

Rules:
- Times are UTC ms plus the local date at that moment; group by `local_date`.
- Enums are stored by name and alert codes by contract name: renaming one
  is a schema migration.
- No names or subject codes. A research capture is linked by its time stamp
  only (`captureStampOf`), and retention never deletes those alerts.
- Mock and fake-BLE runs use an in-memory database, never the phone's file.
- Schema change: bump `schemaVersion`, then from `mobile/` run
  `dart run build_runner build` and `dart run drift_dev make-migrations`
  (dumps `drift_schemas/`, writes migration steps and tests in `test/drift/`).
