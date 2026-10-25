# lib/settings/

Patient settings (S8B, DESIGN-SPEC §10.1) and each foot's remembered insole.

- `AppSettings`: greeting name, text size ("ปกติ" / "ใหญ่" / "ใหญ่มาก",
  factors 1, 22/18, 26/18 times the phone's own scale), alert sound,
  foot-check reminder on/off and time. Sound and reminder are stored only
  until S8C/S9 use them.
- `SettingsStore`: `PrefsSettingsStore` (Android SharedPreferences, the app's
  private `shared_prefs/`) on the phone, `MemorySettingsStore` in tests and
  fake-BLE runs. Not in the drift database, so the researcher's "Clear app
  database (test data)" never resets settings. Never rename a key in
  `SettingsKeys`.
- `AppTextScaler`: applied once in `MaterialApp.builder`; never clamped.
