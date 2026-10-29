# lib/footcheck/

Daily foot check (S8C, DESIGN-SPEC §11): camera, private photo storage,
the check in progress, and the queries the screens show. Screens are in
`lib/ui/screens/foot_check/`; checks are stored through
`FootCheckRepository` (`lib/storage/`), which decides the result (rule 14).

| File | What |
|---|---|
| `foot_views.dart` | `CameraFacing`; per view: sole/top, side, automatic camera, file stem |
| `foot_camera.dart` | `FootCamera` interface (open, preview, take, close, settings) and `CameraUnavailable` |
| `plugin_foot_camera.dart` | The only `camera` importer: CameraX, 16:9 up to 2160p, calls serialized, front preview always mirrored (asks MainActivity which preview path the plugin uses) |
| `photo_processor.dart` | Camera JPEG → stored photo: EXIF rotation kept, any EXIF mirror undone (true view), crop to the viewfinder aspect, 1600 px, q85, no metadata; runs in an isolate |
| `photo_session.dart` | One check's photos under `foot_photos/<stamp>/` until saved or discarded |
| `foot_check_flow.dart` | `footCheckFlowProvider`: begin, put photo, answer, save, discard |
| `footcheck_providers.dart` | Camera factory, today (midnight rollover + resume refresh), today's / 7-day / history checks, compare source |
| `compare_source.dart` | The earlier photo to compare a view with (yesterday / earlier / none) |
| `history.dart` | Grouping by day, latest check per day, findings |
| `orphan_sweep.dart` | At app start: photos no saved check refers to, and the camera's temp files |

Rules:
- Photos stay in the app's private folder (rule 15): never MediaStore, the
  gallery or a share sheet. The camera's temp file is deleted at once.
- The saved photo is the true view whichever lens took it (decision 1); the
  front preview is mirrored and the guide is drawn to match the preview.
- The latest check of a day is that day's result; every finding keeps its
  own alert.
- Photos are relative paths under `footPhotoDirProvider`; deleting them all
  is Settings' "ลบรูปถ่ายเท้าทั้งหมด". Retention keeps 30 days.
