# Study-day fallback: retired (one phone only)

> **User decision 2026-10-31 (BACKLOG 63): the study uses one phone only,
> the Note 10. There is no laptop fallback.** The frozen web app reads
> only DATA-CONTRACT v1.5, so it cannot capture from the 8-sensor boards
> (v1.6): it refuses the 8-channel calibration, and past that would read
> wrong numbers with no error (report 037). Its code is left untouched;
> it is simply no longer part of the study-day plan.

The study-day procedure is `docs/STUDY-CAPTURE.md`. What replaces the
fallback:

## If the phone fails in the middle of a session

1. **Stop the session.** Do not try to finish it on another device.
2. On paper: the time, the trial that was running, and what failed.
3. Keep whatever the phone already saved. If the app still opens, export
   it as usual (`docs/STUDY-CAPTURE.md`, "Export"); the partial session is
   kept, never deleted.
4. **Reschedule that participant** for another day inside the IRB window
   (1–30 Nov 2026). The new session gets a new attempt on the same
   subject code; tell the study lead.

## How the risk is kept small

- **Export after every participant**, and run
  `python3 tools/capture/load_capture.py check <session folder>` on the
  laptop copy **before the next participant starts**. A problem found then
  costs one participant, not a day.
- **Bring every study day:** the phone charged, a charged power bank, and
  a spare USB cable (for the export and for charging).

## The old laptop procedure

The step-by-step laptop capture (web app on Chrome, checked in S3B against
the 6-FSR simulator, report 025) is in this file's git history before
2026-11-01. It only works with v1.5 boards (6 FSR, 12-byte temperature),
which the study no longer uses.
