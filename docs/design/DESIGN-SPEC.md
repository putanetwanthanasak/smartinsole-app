# DESIGN-SPEC — SmartInsole App (Flutter) — v2 (style D, all screens)

> v2 · 2026-10-22 · Source: the style D boards on the "SmartInsole App Design" canvas (claude.ai); Appendix B maps every board to a section. v1 (2026-10-17) used a teal IBM Plex style; replaced.
> Status: all screens are designed in style D and approved by the user (2026-10-22) ✅ · Home (S5) · Alerts and the Temperature tab of My feet (S6B) · Gait tab of My feet (S8A) · Connection and Settings (S8B) · Daily foot check (S8C).
> Primary user: people with diabetes, possibly poor eyesight, not tech-savvy → large, clear, simple, friendly.
> Thai text in quotes is the exact UI copy to use. `{…}` inside quoted copy is filled in at run time; names, times and numbers taken from the boards are sample data. Everything else in this file is English.
> ⚠️ Health advice and explanation copy is a draft until the medical expert reviews it (FLUTTER-PLAN §11: before 2026-11-05). Appendix A lists all of it for that review.

### What changed in this update (2026-10-22)

- Status card radius is **20**. The "28" in the Home-only v2 was the radius of the 56 px icon circle (user decision).
- Foot-map dots have a 2 px `inkMuted` outline, as on every board (the Home-only v2 said "white ring"). No-data dots are white with a dashed `inkSubtle` outline; the unused `#D3DDE1` is removed. On Home the foot outline stays solid `divider` when there is no data (the Home-only v2 said dashed); only My feet dashes the outline.
- Motion curves are given as exact `Cubic(...)` values: Flutter's named `Curves.easeInCubic` / `Curves.easeOutCubic` use different control points from the boards.
- Home wording: "never show kPa / ΔT / PAI" now reads "never show the terms or units", since the ΔT card does show the difference as a number.
- New sections: navigation map (§4), shared components (§5), Alerts (§7), My feet (§8), Connection (§9), Settings (§10). Daily foot check (§11) is now in style D, with a new "saved" screen and a 7-day history.
- Motion (§12) now gives every duration and curve, screen by screen.
- Decisions, proposed defaults and open items: §14. Draft health copy: Appendix A. Board index: Appendix B.
- Later the same day the user confirmed five of the proposed behaviours (decisions 7–11) and clarified decision 4: PTI is display-only, and the `PRESSURE_PTI` alert is still raised.

---

## 1. Colour tokens (style D)

The whole app uses style D ("แบบ D" on the design canvas). Theme files in `lib/ui/theme/` are replaced with these values in S5.

| Token | Hex | Use |
|---|---|---|
| `bg` | `#ECFEFF` | Page background (very light cyan); foot-map fill; inner boxes on white cards |
| `surface` | `#FFFFFF` | Cards, foot chips, settings button, bottom bar, sheets |
| `ink` | `#164E63` | Primary text, headings, big numbers, back link |
| `inkMuted` | `#475569` | Secondary text, inactive tab icons and labels, dot outlines |
| `inkSubtle` | `#64748B` | Disconnected and no-data outlines, missed days |
| `primary` | `#155E75` | Primary buttons, selected tab, selected segment, links ("ดูเพิ่ม"), heel line, left part of the balance bar |
| `primarySoft` | `#CFFAFE` | Selected-tab pill, icon circles, step-number circles, selected "ไม่มี" answer |
| `outline` | `#0891B2` | 1.5 px borders on foot chips, settings button, secondary buttons, emphasised cards; small card icons; scanning ripple |
| `divider` | `#A5F3FC` | Card borders, nav top border, row dividers, chart baseline, sheet handle |
| `track` | `#E8F1F6` | Empty bar tracks, chart grid lines, empty confidence segments |
| `accentLight` | `#67E8F9` | Right part of the balance bar |
| `connected` | `#059669` | Foot-chip dot when connected (filled); connected disc on Connection; disconnected = hollow ring `#64748B` |
| `badge` | `#991B1B` | Alerts count badge (white text, 2 px white ring) |

### Status colours (always icon + text + colour; never colour alone)

| Status | Background | Text | Icon colour | Icon (Lucide name) |
|---|---|---|---|---|
| Safe | `#E2F2E8` | `#1B5536` | `#2E7D4F` | `circle-check` |
| Be careful | `#FFF0D2` | `#5E3E00` | `#A86A00` | `triangle-alert` |
| Rest your feet | `#FBE3DF` | `#7F1D12` | `#B42318` | `octagon-alert` |
| No data | `#E9EEF0` | `#33444B` | `#55666E` | `bluetooth-off` |

The status colours also drive summary banners, alert tags, message and warning boxes and the selected "มี / ไม่แน่ใจ" answer. Device alerts (connection, battery) use the No-data colours with their own icon (`bluetooth-off`, `battery-low`).

### Foot-map dots (differ in hue, lightness and size)

| Level | Fill | Radius (SVG units, 120-wide foot) | Word |
|---|---|---|---|
| Low | `#BFE2EB` | 8 | "น้อย" |
| Medium | `#F0B340` | 11 | "ปานกลาง" |
| High | `#C2410C` | 14 | "มาก" |
| No data | `#FFFFFF` | 10 | — |

Every dot has a 2 px `inkMuted` outline; a no-data dot has a 2 px dashed (4 3) `inkSubtle` outline instead. Legend dots: radius 5 / 7 / 9 with a 1.5 px `inkMuted` outline. Level boundaries come from `thresholds.json` (on the boards: low below `watchKpa`, medium from `watchKpa`, high from `alertKpa`); never hardcode them.

### Temperature chart

- Alert band from the ΔT threshold upwards: `#FBE3DF` with the label "ระดับที่ควรระวัง" (16/600, `#7F1D12`)
- Threshold line `#B42318`, 1.5 px, dashed 5 4 · grid lines `track` · baseline `divider` · axis labels 16 `inkMuted`
- Heel line `primary`, 3.5 px solid · forefoot line `inkMuted`, 2.5 px dashed 6 5 (the two lines differ in colour, width and dash)
- Last-reading dot radius 5.5 with a 2 px white ring: `primary`, or `#B42318` while the heel or forefoot ΔT is above the threshold

### Camera screen (foot check)

| Token | Value | Use |
|---|---|---|
| `camBg` | `#0F1D22` | Screen background; base colour of overlays |
| `camViewfinder` | `#22353B` | Viewfinder; photo placeholders on Compare |
| `camGuide` | `#7FD3E3` | Dashed foot guide, current-slot border, self-timer button, check badge |
| `camText2` | `#C9DCE1` | Secondary text |
| `camChipText` | `#E3F1F4` | Text of the hint chip inside the viewfinder |
| `camSlotDone` | `#33505A` | Taken slot; the thumbnail that flies into it |
| `camSlotTodo` | `#4A6670` | Dashed border of slots not taken yet |

Overlays: hint chip `camBg` at 85 % · countdown disc `camBg` at 80 % · skip button white at 16 % · bottom-sheet scrim `camBg` at 60 %.

---

## 2. Typography (style D)

- **Headings and big numbers:** `Figtree` (Latin digits and symbols) with `Noto Sans Thai` for Thai glyphs, 600/700
- **Body:** `Noto Sans` with `Noto Sans Thai Looped` for Thai glyphs (looped Thai reads better for older users), 400/500/600/700
- **Numbers that change** (ΔT, balance, steps, kPa tables, percentages) use tabular figures so they do not jump
- **Bundled** in `assets/fonts/` (all OFL); never downloaded at runtime. The IBM Plex fonts from v1 are removed in S5.

| Use | Size | Weight | Font |
|---|---|---|---|
| Countdown digit (camera) | 72 | 700 | heading |
| Big numbers (ΔT, balance, temperature sites) | 36 | 700 | heading |
| Home status title (h1); camera view name; steps today | 32 | 700 | heading |
| Page title (h1), greeting, alert-detail title, foot-check result titles | 28 | 700 | heading |
| Gait class name | 26 | 700 | heading |
| Bottom-sheet title; current activity on the Gait tab | 24 | 700 | heading |
| Empty-state title; insole name on Connection; "no gait result" title | 22 | 700 | heading |
| Card title (h2) | 20 | 600 | heading |
| Main body, status detail, advice, steps, questions; list-row titles (600); buttons (700) | 18 | 400–700 | body |
| Secondary text, labels, tags, tab labels, Settings group labels (700) | 16 | 400–700 | body |
| Smallest (badge count) | 14 | 700 | heading |

Line height 1.3–1.35 for headings, 1.5–1.6 for body. Nothing is smaller than 16 except the badge. Must survive large system text without clipping: text wraps, and screen titles live in the page body, not the `AppBar` (FLUTTER-PLAN §2).

## 3. Size, spacing, radius (style D)

- Reference screen 390 wide; every screen scrolls except the camera; the bottom bar stays fixed
- Page padding 24 at the sides · top 24 on tab screens, 8 on pushed screens (the back link row) · bottom 104 with the bar (80 + 24), 32 without
- Gap between sections 24 · inside cards 16 (8–12 in tight groups) · two-column grids 16 · stacked buttons 12
- Radius:
  - 20: status-type cards (Home status card, alert-detail status card, foot-check result and saved cards)
  - 56 px icon circle in status cards (radius 28, a full circle)
  - 24: camera viewfinder; top corners of bottom sheets
  - 16: cards, buttons, foot chips, settings button, segmented-control frame, banners, info boxes
  - 14: answer buttons (foot check), capture slots
  - 12: inner boxes (advice, messages, link rows), segment options, text-size options
  - 999: pills (status tags, "ใหม่" chip, estimate chip)
  - Bars: balance 5 (Home, 10 tall) or 6 (My feet, 12 tall); progress and probability bars 4
- **Minimum touch target 48 × 48** · primary and secondary buttons 56 high · list rows 72 · foot chips 72 · foot-check card 88 · text-size options 52 · capture controls 64 (shutter 80) · "ดูเพิ่ม" row 48
- No shadows; separation comes from borders (`outline` 1.5 px or `divider` 1 px)

## 4. App structure and navigation

- **Bottom bar, 4 tabs** (height 80, white, `divider` top border, padding 8): **"วันนี้"** (Home, `house`), **"เท้าของฉัน"** (My feet: pressure, temperature and gait as sub-tabs, `footprints`), **"ตรวจเท้า"** (Daily foot check, `camera`), **"แจ้งเตือน"** (Alerts, `bell` + badge).
  - Selected tab: icon in a 64×32 pill (`primarySoft`, radius 16); icon and label `primary`, label 16/700. Inactive: `inkMuted`, 16/500.
  - Badge = number of unread alerts: min 24×24, radius 12, `badge` fill, 2 px white ring, 14/700 white, at top −6 / right 2 of the icon pill; hidden at 0 and hidden from screen readers. The tab's screen-reader label carries the count: "แจ้งเตือน มี {n} รายการที่ยังไม่ได้อ่าน" (just "แจ้งเตือน" when there are none).
  - The old separate Gait and Temperature tabs are merged into "เท้าของฉัน" (§8).
- **Screens with the bar:** Home, My feet, Alerts, Foot check › Start, Foot check › Saved.
- **Pushed screens** (no bar, back link "กลับ" at the top): Alert detail, Connection, Settings, Researcher, Foot check › Compare & answer. Foot check › Capture is full screen with "ยกเลิก". Foot check › Something found has no back link and leaves through its two buttons.
- **Settings:** 48×48 button, radius 16, `outline` border, top right of Home (screen-reader label "ตั้งค่า").
- **Research capture (S4C):** researcher-only, reached from Settings › "ส่วนผู้วิจัย" (2-second long press), never a tab.
- No fake status bar.

### Navigation map

| From | Element | Goes to |
|---|---|---|
| Home | Settings button | Settings |
| Home | Foot chip | Connection: the search view when the insoles are not connected (No data), otherwise the connected view |
| Home | "เชื่อมต่อแผ่นรองเท้า" (No data) | Connection |
| Home | Foot-check card | Foot check › Start |
| Home | "ดูเพิ่ม" | My feet › "แรงกด" |
| Alerts | Alert card | Alert detail; `BATTERY_LOW` → Connection; foot-check finding → Foot check › Something found |
| Alert detail | Action button | `TEMP_DELTA` "ดูความอุ่นของเท้า" → My feet › "อุณหภูมิ" · pressure codes "ดูแรงกดที่เท้า" → My feet › "แรงกด" · `DEVICE_LOST` "เชื่อมต่ออีกครั้ง" → Connection |
| My feet | Banner link "ดูสิ่งที่ควรทำ" | The matching alert detail |
| My feet | "เชื่อมต่อแผ่นรองเท้า" | Connection |
| Connection | "กลับ" / "เสร็จแล้ว กลับหน้าวันนี้" | The previous screen / Home |
| Settings | "เชื่อมต่อแผ่นรองเท้า" row | Connection |
| Settings | "ส่วนผู้วิจัย" (long press 2 s) | Researcher |
| Researcher | TARE row | TARE confirmation sheet |
| "ตรวจเท้า" tab | — | Start until today's check is saved, then Saved (decision 8) |
| Foot check › Start | "เริ่มถ่ายรูป" / "ไม่ถ่ายรูป ตอบคำถามอย่างเดียว" | Capture / Compare & answer (questions only) |
| Capture | "ยกเลิก" / after the 4th photo | Start / Compare & answer |
| Compare & answer | "บันทึก" | Something found (any "มี / ไม่แน่ใจ") or Saved |
| Something found | "เข้าใจแล้ว กลับหน้าหลัก" | Home |
| Something found, Saved | "ดูรูปที่บันทึกไว้" | Photo history (not designed, §14) |

---

## 5. Shared components

- **Page title:** 28/700 heading font, `ink`, in the page body. Optional line under it: 16 `inkMuted`.
- **Back link:** `chevron-left` 24 (stroke 2.25) + "กลับ" 18/600 `ink`, min height 48, at the top left; returns to the previous screen.
- **Card:** white, `divider` 1 px, radius 16, padding 24 (16 for small cards), gap 16; card title 20/600. An **emphasised card** (the action list on alert details and the found result, an unread alert, a connection card that needs action) has an `outline` 1.5 px border.
- **Status card:** status background, radius 20, padding 24, gap 8; 56 white circle (radius 28) with the 32 px status icon. Used on Home, alert details and foot-check results.
- **Summary banner** (My feet): status background, radius 16, padding 16 20, gap 12; 44 white circle with a 26 px status icon; title 18/700 and line 16, both in the status text colour. Optional link row inside (white, radius 12, min height 48, padding 0 16, 18/700 `ink` + `chevron-right` 22) or a primary button.
- **Buttons** (full width): primary = height 56, radius 16, `primary` fill, white 18/700, optional 24 px icon, gap 8. Secondary = min height 56, radius 16, white, `outline` 1.5 px border, `ink` 18/700.
- **List row** (Settings): min height 72, padding 12 16, gap 16; 40 circle (`primarySoft` with a 22 px `primary` icon); title 18/600 over value 16 `inkMuted`; `chevron-right` 22 `ink`; rows in one card are split by `divider` lines.
- **Numbered steps:** 32 circle `primarySoft` with the number (18/700 heading font, `ink`); text 18, line height 1.55; gap 12; 16 between steps (12 in the TARE sheet).
- **Info box:** white, `divider` border, radius 16, padding 16, gap 12; 24 px `info` (or `lightbulb` for tips) in `primary`; text 16 `ink`.
- **Warning box:** Be-careful background, radius 12–16, padding 16; `triangle-alert` in `#A86A00`; text 16 `#5E3E00`.
- **Urgent box:** Rest background, radius 16, padding 20; `octagon-alert` 26 `#B42318`; text 18/600 `#7F1D12`.
- **Status tag** (pill): radius 999, padding 4 10, gap 6; status background, 18 px status icon (stroke 2.25), status text 16/700.
- **"ใหม่" chip:** `primary` fill, white 16/700, padding 2 10, radius 999.
- **Segmented control:** white frame, `outline` 1.5 px, radius 16, padding 4, gap 4; options min height 48, radius 12; selected = `primary` fill + white 700, others transparent + `ink` 600. On My feet a sliding `primary` indicator moves between options (§12).
- **Details expander** ("ดูตัวเลขละเอียด"): white card, `divider`, radius 16. Header button: min height 56, padding 12 24, 18/600 `primary`, `chevron-down` 24 that turns 180° when open; label changes to "ซ่อนตัวเลขละเอียด"; expanded state exposed to screen readers. Rows: label 16 `inkMuted` over value 16/600 `ink`, padding 12 0, `divider` top border. Thai words always come first on a screen; numbers live here (user decision).
- **Disclaimer line** under health advice: "คำแนะนำนี้ไม่ใช่การวินิจฉัยโรค ถ้าไม่แน่ใจ ให้ปรึกษาแพทย์หรือพยาบาล" (16 `inkMuted`).
- **Bottom sheet** (confirmations): scrim `camBg` 60 %; white sheet, top corners 24, padding 12 24 32, gap 16; handle 40×4 `divider`; title 24/700; text 16 `inkMuted`; numbered steps; warning box; two buttons side by side, gap 12: secondary (cancel) left, primary (confirm) right.
- **Switch:** state word 16/700 left of a 52×32 track (radius 16). On = "เปิด", `primary` track, 24 white knob on the right. Off is not on the boards; proposed in §14.
- **Partial data:** when one foot is missing, everything about that foot uses the No-data style, and two-foot values (ΔT, balance) show "—" in `inkMuted` with "ต้องเชื่อมต่อทั้งสองข้าง" (FLUTTER-PLAN rule 4).
- **Low battery** (decision 10; no board shows it): when an insole reports a low battery (`BATTERY_LOW`, below 15 % in DATA-CONTRACT §8.3; not in `thresholds.json` yet, BACKLOG 30), its battery text turns `#5E3E00` and gets a 16 px `battery-low` icon in `#A86A00`. This is the plan's "orange" (FLUTTER-PLAN §7); plain `#A86A00` text would fail contrast (4.4:1 on white). Used on the Home foot chips and the Connection cards.

### Foot map geometry (placeholder until `shared/sensor_layout.json` exists)

Top view, big toe on the inner side, one foot per 120×268 view box. Outline: fill `bg`, stroke `divider` 2.5 (on My feet with no data: `inkSubtle`, dashed 6 5).

```
Left:  M60 8C32 8 14 32 14 66C12 98 26 120 24 150C22 176 30 200 30 226C30 246 40 258 56 260C72 262 86 252 90 238C98 214 90 182 86 150C82 120 104 98 102 66C100 30 86 8 60 8Z
Right: M60 8C88 8 106 32 106 66C108 98 94 120 96 150C98 176 90 200 90 226C90 246 80 258 64 260C48 262 34 252 30 238C22 214 30 182 34 150C38 120 16 98 18 66C20 30 34 8 60 8Z
```

| Board order | Zone | Name in the UI | Left (x, y) | Right (x, y) |
|---|---|---|---|---|
| fsr0 | Hallux | "นิ้วหัวแม่เท้า" | 80, 36 | 40, 36 |
| fsr1 | 1st metatarsal head | "โคนนิ้วหัวแม่เท้า" | 80, 88 | 40, 88 |
| fsr2 | Central forefoot | "กลางหน้าเท้า" | 54, 80 | 66, 80 |
| fsr3 | 5th metatarsal head | "โคนนิ้วก้อย" | 30, 96 | 90, 96 |
| fsr4 | Lateral midfoot | "ขอบเท้าด้านนอก" | 36, 152 | 84, 152 |
| fsr5 | Heel | "ส้นเท้า" | 58, 224 | 62, 224 |

Temperature sites: forefoot "หน้าเท้า" (left 62, 92 · right 58, 92) and heel "ส้นเท้า" (left 58, 222 · right 62, 222). Rendered sizes: Home and alert detail 84×188 (feet 48 apart); My feet 108×241 (40 apart); CoP 60×134; temperature-site icon 22×48. The channel-to-zone mapping and positions must come from `sensor_layout.json` once it exists (user decision: placeholders are fine until then).

---

## 6. Home (style D, 4 states)

Top to bottom (gap 24):
1. **Header:** date (16, `inkMuted`) over "สวัสดี คุณ{name}" (28/700, `ink`; just "สวัสดี" when no name is set) + settings button.
2. **Foot chips** (2 columns, gap 16, min height 72, white, `outline` 1.5 px, radius 16, padding 12 16; each chip is a link to Connection): 12 px dot (filled `connected` when connected, hollow `#64748B` ring when not) + "เท้าซ้าย"/"เท้าขวา" (18/600) over "แบต {n}%" or "ไม่ได้เชื่อมต่อ" (16, `inkMuted`, indented 20). Low battery: the low-battery style (§5).
3. **Status card** (status background, radius 20, padding 24, gap 8; a polite live region): icon in a 56 white circle (radius 28, 32 px icon) → title (32/700, status text colour) → detail (18) → advice box for Be careful and Rest your feet only (white, radius 12, padding 16: "สิ่งที่ควรทำตอนนี้" 16/700 + advice 18) → button "เชื่อมต่อแผ่นรองเท้า" for No data only (primary, with `bluetooth`; opens Connection).
4. **Foot-check card** (only while today's check is not done; the whole card is one link to Foot check › Start; min height 88, white, `outline` 1.5 px, radius 16, padding 16 20): camera icon in a 48 `primarySoft` circle + "วันนี้ยังไม่ได้ดูเท้า" (18/600) + "ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที" (16, `inkMuted`) + chevron.
5. **Pressure card** (white, `divider` border, radius 16, padding 24 24 8 24): "น้ำหนักที่เท้ารับอยู่ตอนนี้" (20/600) → left and right foot maps (84×188, gap 48, §5 geometry; labels "ซ้าย"/"ขวา" 16/600 `inkMuted`) → one-line caption in plain Thai (16/600; `ink`, or the Be-careful text colour with a warning icon when a zone is high) → legend "น้อย" / "ปานกลาง" / "มาก" → full-width row link "ดูเพิ่ม" + chevron (16/600 `primary`, min height 48, `divider` top border; opens My feet › "แรงกด").
6. **Two small cards** (2 columns, gap 16, white, `divider` border, radius 16, padding 16, gap 8):
   - "ความอุ่นของเท้า" (`thermometer` 20 `outline`, 16/600) → difference "{x.x}°" (36/700) → "ต่างกันซ้าย–ขวา" (16, `inkMuted`) → plain-Thai note (16/600; Rest-your-feet text colour with an `octagon-alert` icon when ΔT triggers).
   - "การลงน้ำหนัก" (`scale` 20 `outline`, 16/600) → "{L} : {R}" (36/700) → bar (10 tall, radius 5: left share `primary`, right share `accentLight`, track `track`, 2×16 centre tick `ink`) with "ซ้าย"/"ขวา" under its ends → plain-Thai note (Be-careful colour + icon when uneven).
   - No data: "—" in `inkMuted` and "ต้องเชื่อมต่อทั้งสองข้าง".

The page scrolls; the bottom bar stays fixed. The status card, foot map and small cards follow the 3-level mapping (FLUTTER-PLAN §7): level 2 shows Safe with orange dots / orange notes only.

### Copy per status

| Status | Title | Detail (example) | Advice |
|---|---|---|---|
| Safe | "ตอนนี้เท้าปลอดภัย" | "น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ" | — |
| Be careful | "ควรระวัง" | "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" | "ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่" |
| Rest your feet | "ควรพักเท้าตอนนี้" | "เท้าขวาอุ่นกว่าเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก" | "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์" |
| No data | "ยังไม่ได้รับข้อมูล" | "ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่" | (connect button) |

Board captions and screen-reader labels for the maps, e.g. caption "ปลายเท้าซ้ายรับน้ำหนักมาก", map labels "เท้าซ้าย ปลายเท้ารับน้ำหนักมาก" / "เท้าขวา แรงกดกระจายดี"; notes "สองข้างอุ่นใกล้เคียงกัน", "เท้าขวาอุ่นกว่าปกติ", "ซ้ายและขวาพอ ๆ กัน", "ลงน้ำหนักเท้าซ้ายมากกว่า".

The real detail text is generated from the rule that caused the status (alert code + foot side + zone) in plain Thai. Never show the terms or units kPa, ΔT or PAI on Home; the temperature difference appears only as "{x.x}°".

---

## 7. Alerts (S6B; rules and copy from S7)

### 7.1 What appears in the list

Codes follow DATA-CONTRACT v1.5 §8.3: **8 codes** (user decision; an earlier "9" in the plan was an error, fixed in S6A). Level-2 events are not listed (user decision); they show only as orange dots and notes on Home and My feet.

| Code (level) | Patient sees | In the list | Tag | Board example: title / "ควรทำ" | Opens |
|---|---|---|---|---|---|
| `TEMP_DELTA` (4) | Rest your feet | Yes | "ควรพักเท้า" | "เท้าขวาอุ่นกว่าเท้าซ้าย" / "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม" | Alert detail |
| `PRESSURE_PEAK` (3) | Be careful | Yes | "ควรระวัง" | "ปลายเท้าซ้ายรับน้ำหนักมากตอนเดิน" / "ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่" | Alert detail |
| `PRESSURE_PTI` (3) | Be careful | Yes | "ควรระวัง" | No board example; same pattern, copy written in S7 (§14) | Alert detail |
| `LOAD_CONCENTRATION` (3) | Be careful | Yes | "ควรระวัง" | "น้ำหนักลงที่ส้นเท้าขวาจุดเดียวมากเกินไป" / "ลองยืนให้น้ำหนักลงทั้งฝ่าเท้า หรือเปลี่ยนท่ายืน" | Alert detail |
| `PRESSURE_WATCH` (2) | Safe + orange dot | No | — | — | — |
| `ASYMMETRY_PEAK` (2) | Safe + orange balance note | No | — | — | — |
| `DEVICE_LOST` (1) | No data | Yes | "อุปกรณ์" (`bluetooth-off`) | "แผ่นรองเท้าซ้ายหลุดการเชื่อมต่อ" / "ตรวจว่าแผ่นรองเท้าเปิดอยู่ แล้วเชื่อมต่อใหม่" | Alert detail |
| `BATTERY_LOW` (1) | Status unchanged; low-battery style (§5) | Yes | "อุปกรณ์" (`battery-low`) | "แบตเตอรี่แผ่นรองเท้าขวาเหลือน้อย" / "ชาร์จแบตเตอรี่ก่อนใช้ครั้งต่อไป" | Connection |
| Foot-check finding (not a contract code) | — | Yes | "ควรระวัง" | "พบสิ่งที่ควรให้แพทย์ดู" + line "จากการดูเท้าประจำวัน" / "ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู" | Foot check › Something found |

The board examples above are the design's; the app's copy is `alertCopyFor` and follows Appendix A where S7 changed it (`LOAD_CONCENTRATION`'s ควรทำ is now the walking advice "ลองเดินช้าลงให้น้ำหนักลงทั้งฝ่าเท้า หรือนั่งพักสักครู่"; §7.3's `PRESSURE_PEAK` detail is "…รับแรงกดสูงมากตอนเดิน"). Where they differ, Appendix A wins.

### 7.2 Alerts list

- Title "แจ้งเตือน" with "ยังไม่ได้อ่าน {n} รายการ" under it (16 `inkMuted`, polite live region).
- An alert becomes read once the user opens it: its detail, Connection for `BATTERY_LOW`, or the result screen for a foot-check finding (decision 7). A read card loses the "ใหม่" chip and its `outline` border; the badge counts unread alerts.
- Grouped by day, newest first. Group titles 20/600, 16 above the first card: "วันนี้", "เมื่อวาน · อังคาร 20 ต.ค." (format: "เมื่อวาน · " + weekday + day + short month); older days use weekday + day + short month.
- **Alert card** (the whole card is one link): white, radius 16, padding 16, gap 12, 16 between cards. Unread: `outline` 1.5 px border and the "ใหม่" chip; read: `divider` 1 px. Content column (gap 8):
  1. Status tag + time "HH:mm" (16 `inkMuted`) + "ใหม่" chip when unread (wraps if needed)
  2. Title 18/600
  3. Optional source line 16 `inkMuted` (foot-check findings: "จากการดูเท้าประจำวัน")
  4. "ควรทำ: " (16/700) + advice (16, `ink`)
  - `chevron-right` 24 `primary` at the right edge.
- TalkBack label of a card (S6B): "{tag} {HH:mm} {title} ยังไม่ได้อ่าน|อ่านแล้ว", then the source line if any and "ควรทำ: {advice}", so the advice is heard too (rule 13).
- Footer "แสดงย้อนหลัง 30 วัน" (16 `inkMuted`, centred), matching the 30-day retention in S6A.
- **Empty:** 88 circle `primarySoft` with `bell` 40 `primary`; "ยังไม่มีการแจ้งเตือน" (22/700); "เมื่อแอปพบเรื่องที่ควรระวัง จะแสดงที่นี่ พร้อมคำแนะนำว่าควรทำอะไร" (18 `inkMuted`, max width 300); centred, 96 below the title (24 page gap + 72).

### 7.3 Alert detail

Top to bottom (gap 24):
1. Back link (→ the previous screen: Alerts or My feet).
2. **Status card** (radius 20): row of the 56 white circle with the 32 px icon + level word (16/700) over the time (16), both in the status text colour → title (28/700) → detail (18).
   - Level words: "ควรพักเท้า" (Rest your feet), "ควรระวัง" (Be careful), "เรื่องอุปกรณ์" (device). Time: "วันนี้ {HH:mm}" or "เมื่อวาน {HH:mm}".
3. **"สิ่งที่ควรทำ"** (emphasised card): numbered steps.
4. **"ตำแหน่งที่พบ"** (temperature and pressure codes only): both feet (84×188, gap 48, labels "ซ้าย"/"ขวา"), caption (16/600, status text colour), legend.
   - Temperature: 2 sites per foot, radius 15. The warmer site: fill `#FBE3DF`, 2 px `#B42318`, plus a 3 px `#B42318` ring at radius 23. Other sites: white, 2 px `inkMuted`. Legend "จุดที่อุ่นกว่า" / "จุดวัดอื่น".
   - Pressure: level dots; the zone that triggered gets a 3 px `#C2410C` ring at radius + 7. Legend "น้อย" / "ปานกลาง" / "มาก".
5. **"ทำไมแอปถึงเตือน"**: text 18. For `PRESSURE_PEAK`, `PRESSURE_PTI` and `LOAD_CONCENTRATION`, a gait note may follow (box `bg`, radius 12, padding 16, `footprints` 24 `primary`, text 16): the text from DATA-CONTRACT §8.3.1, only when Model A's class matches the zone with confidence ≥ `minConfidence`. It never changes the level.
6. **Details expander** (§5) with the numbers.
7. Disclaimer line.
8. **Action button** (primary + `chevron-right`, see the navigation map).

Board copy (⚠️ draft, Appendix A):

| Part | `TEMP_DELTA` | `PRESSURE_PEAK` | `DEVICE_LOST` |
|---|---|---|---|
| Level / time | "ควรพักเท้า" / "วันนี้ 14:32" | "ควรระวัง" / "วันนี้ 11:05" | "เรื่องอุปกรณ์" / "เมื่อวาน 16:20" |
| Title | "เท้าขวาอุ่นกว่าเท้าซ้าย" | "ปลายเท้าซ้ายรับน้ำหนักมากตอนเดิน" | "แผ่นรองเท้าซ้ายหลุดการเชื่อมต่อ" |
| Detail | "ส้นเท้าขวาอุ่นกว่าส้นเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก" | "โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงมากหลายก้าวติดกัน" | "ขาดการเชื่อมต่อนานกว่า 5 นาที ระหว่างนี้แอปยังบอกไม่ได้ว่าเท้าซ้ายปลอดภัยหรือไม่" |
| Step 1 | "นั่งพักเท้า" | "ลองเดินช้าลง และก้าวให้สั้นลง" | "ตรวจว่าสวิตช์ที่กล่องอุปกรณ์เปิดอยู่" |
| Step 2 | "ตรวจดูว่ามีรอยแดงหรือแผลไหม" | "นั่งพักสักครู่ แล้วขยับเท้าเปลี่ยนท่า" | "วางโทรศัพท์ไว้ใกล้ ๆ" |
| Step 3 | "ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์" | "ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า" | "กด \"เชื่อมต่ออีกครั้ง\" ด้านล่าง" |
| Map caption | "ส้นเท้าขวาอุ่นกว่าส้นเท้าซ้าย" | "จุดที่มีวงล้อม: โคนนิ้วหัวแม่เท้าซ้าย" | (no map) |
| Map labels | "เท้าซ้าย จุดวัดความอุ่นที่หน้าเท้าและส้นเท้า" / "เท้าขวา ส้นเท้าอุ่นกว่าเท้าซ้าย" | "เท้าซ้าย โคนนิ้วหัวแม่เท้ารับน้ำหนักมาก" / "เท้าขวา แรงกดกระจายดี" | — |
| Why | "เมื่อเท้าข้างหนึ่งอุ่นกว่าอีกข้างที่ตำแหน่งเดียวกันต่อเนื่อง อาจเป็นสัญญาณเริ่มต้นของการอักเสบใต้ผิวหนัง ซึ่งมักเกิดก่อนจะเห็นแผล" | "แรงกดที่สูงมากซ้ำ ๆ ที่จุดเดิมขณะเดิน อาจทำให้ผิวบริเวณนั้นช้ำและเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง" | "แอปต้องได้รับข้อมูลจากแผ่นรองเท้าทั้งสองข้าง จึงจะเทียบน้ำหนักและความอุ่นของเท้าได้" |
| Gait note | — | "ตรวจพบรูปแบบเดินเขย่งปลายเท้า ซึ่งอาจเพิ่มแรงกดบริเวณปลายเท้า" (§8.3.1, toe walking) | — |
| Action | "ดูความอุ่นของเท้า" | "ดูแรงกดที่เท้า" | "เชื่อมต่ออีกครั้ง" |

Details rows (label / board value). Thresholds come from `thresholds.json`; the internal level is shown for expert review:

| Code | Rows |
|---|---|
| `TEMP_DELTA` | "รหัส" `TEMP_DELTA` · "ส้นเท้า" "ซ้าย 31.4 °C · ขวา 34.0 °C" · "ผลต่างที่ส้นเท้า" "2.6 °C (เกณฑ์ 2.2 °C)" · "วัดเกินเกณฑ์ติดกัน" "3 ครั้ง (เกณฑ์ 2 ครั้ง วัดทุก 30 วินาที)" · "ผลต่างที่หน้าเท้า" "0.4 °C" · "ระดับภายในระบบ" "4 จาก 5" · "เวลาที่พบ" "21 ต.ค. 2569 14:32:10" · "ที่มาของเกณฑ์" "Lavery et al. (2004)" |
| `PRESSURE_PEAK` | "รหัส" `PRESSURE_PEAK` · "ค่าที่วัดได้" "236 kPa ที่โคนนิ้วหัวแม่เท้าซ้าย" · "เกณฑ์" "200 kPa ขณะเดิน" · "ขณะนั้น" "กำลังเดิน (ตรวจจากความเร่ง)" · "รูปแบบการเดิน" "เดินเขย่งปลายเท้า · ความมั่นใจ 78%" · "ระดับภายในระบบ" "3 จาก 5" · "เวลาที่พบ" "21 ต.ค. 2569 11:05:42" · "ที่มาของเกณฑ์" "Owings et al. (2009)" |
| `DEVICE_LOST` | "รหัส" `DEVICE_LOST` · "เชื่อมต่อได้ครั้งล่าสุด" "20 ต.ค. 2569 16:14:05" · "หลุดการเชื่อมต่อนาน" "6 นาที (เกณฑ์ 5 นาที)" · "แบตเตอรี่ครั้งล่าสุด" "43%" · "ระดับภายในระบบ" "1 จาก 5" |
| `PRESSURE_PTI` (S6B, draft) | "รหัส" `PRESSURE_PTI` · "ค่าที่วัดได้" "92 kPa·s เฉลี่ยต่อก้าว ที่โคนนิ้วหัวแม่เท้าซ้าย" · "เกณฑ์" "80 kPa·s เฉลี่ยต่อก้าว ขณะเดิน" · "จำนวนก้าวที่ใช้" "24 ก้าว ใน 60 นาทีล่าสุด" · "ขณะนั้น" "กำลังเดิน (ตรวจจากความเร่ง)" · "รูปแบบการเดิน" (only with a stored class) · "ระดับภายในระบบ" "3 จาก 5" · "เวลาที่พบ" · "ที่มาของเกณฑ์" "Waaijman et al. (2014)" (BACKLOG 43) |
| `LOAD_CONCENTRATION` (S6B, draft) | "รหัส" `LOAD_CONCENTRATION` · "ค่าที่วัดได้" "46% ของแรงกดทั้งฝ่าเท้า ที่ส้นเท้าขวา" · "เกณฑ์" "40% ติดกัน 20 ก้าว" · "จำนวนก้าวที่ใช้" "20 ก้าวติดกัน" · "ขณะนั้น" · "รูปแบบการเดิน" (only with a stored class) · "ระดับภายในระบบ" "3 จาก 5" · "เวลาที่พบ" · "ที่มาของเกณฑ์" "ตัวชี้วัดของโครงงาน" |

How the rows are filled (S6B): values come from the stored alert; the threshold stored with it wins over today's `thresholds.json`. kPa, kPa·s and % are whole numbers; °C one decimal; thresholds without a trailing ".0". "ที่มาของเกณฑ์" is `thresholds.json` `sources` for the code and is hidden when it is "—" (as on the `DEVICE_LOST` board). "ขณะนั้น" and "รูปแบบการเดิน" appear only when the alert stored them. "หลุดการเชื่อมต่อนาน" rounds the stored minutes up. Dates use the Buddhist year. The detail time for days before yesterday is "{weekday d MMM} HH:mm" (e.g. "อังคาร 20 ต.ค. 16:20").

**Pressure map (S6B).** The map shows the levels at the moment the alert was raised: the alert engine stores both feet's 2 s rolling-peak map with every pressure alert (`details.map`, the same rule as Home's map). A foot that was not usable then is drawn as No data; its label is Home's ("เท้าขวา แรงกดกระจายดี" etc.). Alerts stored before S6B have no map: only the ringed zone is filled (`PRESSURE_PEAK`: its kPa level; `PRESSURE_PTI` / `LOAD_CONCENTRATION`: a plain outline, since their values are not kPa) and every other zone is a plain outline circle (`inkMuted` 2 px, no fill, no dashes) that means "not recorded", never the No-data style.

`PRESSURE_PTI` and `LOAD_CONCENTRATION` follow the `PRESSURE_PEAK` layout (map with the ringed zone, action "ดูแรงกดที่เท้า"). Until S7 settles what PTI means (BACKLOG 31), PTI values appear only in the details (decision 4); the `PRESSURE_PTI` alert itself is raised as the contract defines it (decision 1).

---

## 8. My feet (S6B: Temperature tab · S8A: Gait tab)

- Title "เท้าของฉัน" with "อัปเดตเมื่อสักครู่" right-aligned on the same line (16 `inkMuted`; "ยังไม่มีข้อมูล" when nothing is connected).
- **Sub-tabs** (segmented control, screen-reader tab list "เรื่องที่ดู"; options 18): "แรงกด" / "อุณหภูมิ" / "การเดิน". "ดูเพิ่ม" on Home opens "แรงกด"; the `TEMP_DELTA` action opens "อุณหภูมิ".
- Pressure and Temperature start with a summary banner (§5); Gait does not. Every tab ends with the details expander (except Pressure with no data).
- Plain Thai words first; numbers only in "ดูตัวเลขละเอียด" (user decision).

### 8.1 Pressure ("แรงกด")

Banner by state:

| State | Banner (title / line) | Extra |
|---|---|---|
| Safe (also level 2: orange dots allowed) | "แรงกดกระจายดีทั้งสองข้าง" / "ยังไม่มีจุดใดรับน้ำหนักมากเกินไป" | — |
| Be careful | "ปลายเท้าซ้ายรับน้ำหนักมาก" / "โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงต่อเนื่อง" | Link "ดูสิ่งที่ควรทำ" → the alert detail |
| No data | "ยังไม่ได้รับข้อมูล" / "ต้องเชื่อมต่อแผ่นรองเท้าก่อน" | Primary button "เชื่อมต่อแผ่นรองเท้า" |

- **Card "น้ำหนักที่เท้ารับอยู่ตอนนี้"**: both feet at 108×241 (gap 40, labels "ซ้าย"/"ขวา"), legend, then "จุดที่รับน้ำหนักมากที่สุดตอนนี้" (16/700 `inkMuted`) with the top 3 zones. Each row (padding 12 0, `divider` top border): dot (level radius × 0.8) + zone name (18/600) over side (16 `inkMuted`: "เท้าซ้าย", "เท้าขวา" or "ทั้งสองข้าง") + level word on the right (16/700: "น้อย" / "ปานกลาง" / "มาก"; "มาก" in `#5E3E00` with `triangle-alert` 18).
- **No data:** dashed outlines and white dots, the text "ยังไม่มีข้อมูล ต้องเชื่อมต่อแผ่นรองเท้าก่อน" (16/600 `inkMuted`, centred), no zone list, no details expander.
- **Details:** table "แรงกดตอนนี้ (kPa)" with columns "จุด" / "ซ้าย" / "ขวา" (6 zones, numbers right-aligned in 64 px columns, tabular figures), then rows:
  - "แรงกดสูงสุดขณะเดิน (5 นาทีล่าสุด)" — "ซ้าย 132 · ขวา 126 kPa"
  - "แรงกดสะสม (PTI)" — "ซ้าย 41 · ขวา 39 kPa·s"
  - "น้ำหนักลงจุดเดียวมากที่สุด" — "ซ้าย 31% · ขวา 30%"
  - "เกณฑ์" — "เฝ้าระวัง 75 kPa · เตือน 200 kPa ขณะเดิน · PTI 80 kPa·s · จุดเดียว 40%" (values from `thresholds.json`)

### 8.2 Temperature ("อุณหภูมิ")

Banner by state:

| State | Banner (title / line) | Extra |
|---|---|---|
| Close | "สองข้างอุ่นใกล้เคียงกัน" / "วัดล่าสุด {HH:mm}" | — |
| Rest your feet | "ส้นเท้าขวาอุ่นกว่าซ้าย 2.6 องศา" / "ติดต่อกันมาสักพัก" | Link "ดูสิ่งที่ควรทำ" → `TEMP_DELTA` detail. Keep a non-breaking space before "องศา" |
| One foot missing (No-data colours) | "เทียบความอุ่นไม่ได้" / "เท้าขวาหลุดการเชื่อมต่อตั้งแต่ 12:10" | Primary button "เชื่อมต่อแผ่นรองเท้า" |

- **Two site cards** (2 columns, gap 16; card padding 16, gap 8): foot icon 22×48 with the site dot (`primary`; `#B42318` when that site alerts; `inkSubtle` when missing) + site name "หน้าเท้า" / "ส้นเท้า" (18/600) → difference "{x.x}°" (36/700; Rest text colour when alerting; "—" in `inkMuted` when missing) → "ต่างกันซ้าย–ขวา" (16 `inkMuted`) → note (16/600): "ใกล้เคียงกัน", or "ขวาอุ่นกว่า" / "ซ้ายอุ่นกว่า" in the Rest text colour with `octagon-alert` 20, or "ต้องเชื่อมต่อทั้งสองข้าง".
- **Card "ความต่างของความอุ่นวันนี้"**: chart 294×220 (colours in §1). Y axis 0–3.5 °C with labels "0°" "1°" "2°" "3°"; X axis = today from the first reading to now with three time labels (start, middle, end). Band and dashed line at the ΔT threshold (`deltaC`). A connection gap draws a dashed vertical line (`inkMuted` 1.5, dash 3 4) with "ขาดข้อมูล" / "ตั้งแต่ 12:10" (16, `#33444B`), and no line after it. Legend "ส้นเท้า" / "หน้าเท้า". Note under the chart: "แอปจะเตือนเมื่อเส้นขึ้นไปถึงแถบสีแดงติดกัน 2 ครั้ง" (the count comes from `consecutiveReadings`).
  - Screen-reader summary of the chart, e.g. "กราฟความต่างของความอุ่นวันนี้ ส้นเท้าขึ้นถึงระดับที่ควรระวังตั้งแต่ราว 13:45 ตอนนี้ 2.6 องศา หน้าเท้าต่ำกว่า 0.5 องศาตลอด".
- **Details** (Rest example): "หน้าเท้าตอนนี้" "ซ้าย 30.8 · ขวา 31.2 °C" · "ส้นเท้าตอนนี้" "ซ้าย 31.4 · ขวา 34.0 °C" · "ผลต่าง" "หน้าเท้า 0.4 °C · ส้นเท้า 2.6 °C" · "วัดเกินเกณฑ์ติดกัน" "ส้นเท้า 3 ครั้ง (เกณฑ์ 2 ครั้ง)" (only while above the threshold) · "วัดทุก" "30 วินาที · ล่าสุด 14:30:20" · "เกณฑ์" "ผลต่าง 2.2 °C ติดกัน 2 ครั้ง (Lavery et al., 2004)" · "คุณภาพสัญญาณ" "ดีทั้ง 4 จุด". One foot missing: "อุณหภูมิล่าสุด (เท้าซ้าย)" "หน้าเท้า 30.7 · ส้นเท้า 31.3 °C" · "เท้าขวา" "ไม่มีข้อมูลตั้งแต่ 12:10" · "เกณฑ์".

### 8.3 Gait ("การเดิน")

- **Two small cards** (2 columns): "ตอนนี้" (`activity` 20 `outline`) with "กำลังเดิน" or "ยืนหรือนั่งอยู่" (24/700); "ก้าววันนี้" (`footprints` 20 `outline`) with the step count, e.g. "2,340" (32/700, tabular).
- **Card "ท่าเดินที่ระบบประเมิน"**:
  - Chip "ค่าประมาณ ไม่ใช่การวินิจฉัย" (`info` 18 `primary`; `bg` fill, `divider` border, radius 999, padding 6 12, 16/600).
  - Result: 56 `primarySoft` circle with `footprints` 28 `primary` + class name (26/700) over a short description (16 `inkMuted`).
  - Model result (confidence ≥ `minConfidence`): "ความมั่นใจ" + 3 segments (36×10, radius 5, gap 4; filled `primary`, empty `track`) + word: 2 segments "ปานกลาง" (below 0.85), 3 segments "สูง" (0.85 and up). Results below `minConfidence` are not shown; the rules take over (S8A).
  - Rule-based result: "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม" (16 `inkMuted`).
  - Not walking: 56 circle `#E9EEF0` with `circle-pause` 28 `#55666E` + "ยังไม่มีผลตอนนี้" (22/700) + "ระบบจะประเมินท่าเดินเมื่อคุณเดินต่อเนื่องสักครู่" (16 `inkMuted`) + last result "ผลล่าสุด 10:58 · เดินปกติ" (16/600).
  - Footer (padding-top 12, `divider` top border): "ท่าเดินใช้ประกอบคำแนะนำเท่านั้น ไม่ได้ใช้ตัดสินว่าเท้าปลอดภัยหรือไม่" (16 `inkMuted`; FLUTTER-PLAN rule 11).
- **Class names** (Model A): `normal` "เดินปกติ" ("เดินตามธรรมชาติ"), `toe_walking` "เดินเขย่งปลายเท้า" ("ส้นเท้าแตะพื้นน้อยหรือไม่แตะ"), `antalgic` "เดินกะเผลก", `heel_walking` "เดินลงส้นเท้า", `rotated_foot` "เดินบิดปลายเท้า". Descriptions for the last three are not on the boards (§14).
- **Balance card**: title "การลงน้ำหนักซ้าย–ขวา" ("การลงน้ำหนักซ้าย–ขวา ขณะยืน" when not walking) → "{L} : {R}" (36/700) → bar 12 tall, radius 6: `accentLight` track, left share `primary` growing from the left, 2×18 centre tick `ink` → "ซ้าย" / "ขวา" under the ends → note 16/600, e.g. "ซ้ายและขวาพอ ๆ กัน", "ลงน้ำหนักเท้าซ้ายมากกว่าเล็กน้อย". The board has no warning version of this card (proposed in §14).
- **Details**:
  - "ความไม่สมดุลของแรงกด (PAI)" "4% (เฝ้าระวังเมื่อเกิน 15%)" · "ความไม่สมดุลของแรงกดสะสม" "6% (เฝ้าระวังเมื่อเกิน 20%)" · "ความมั่นใจของผลประเมิน" "78% (ใช้ผลเมื่อ 60% ขึ้นไป)" (model only) · "ประเมินโดย" "กฎพื้นฐาน (โมเดล AI ยังไม่พร้อม)" or "โมเดล AI (Model A)" · "ข้อมูลที่ใช้" "ช่วงละ 2 วินาที ประเมินทุก 1 วินาที"
  - Model only: "ความน่าจะเป็นของแต่ละท่า" with 5 rows (name + "{n}%", bar 8 tall, radius 4, `primary` on `track`; the top class in bold)
  - "เส้นทางของแรงกดในก้าวล่าสุด (CoP)": both feet at 60×134 with the path in `primary` (7 SVG units); labels "เท้าซ้าย เส้นทางของแรงกด" / "เท้าขวา เส้นทางของแรงกด"
  - Not walking: "ผลประเมินล่าสุด" "10:58 · เดินปกติ (กฎพื้นฐาน)" · "ความไม่สมดุลของแรงกดขณะยืน" "2%"

### 8.5 Built in S8A (decisions and defaults not on the boards)

User decisions 2026-10-25 and the defaults approved with the plan; report 034.

- **Where the estimate comes from:** Model A when its slot holds a valid model and the result is at or above `model.minConfidence`; otherwise the provisional rule-based classifier (DATA-CONTRACT §7.5). Strides are 1 s of sample time over a 2 s window (`shared/model_input.json`), never a timer. A result needs both feet usable and both walking (a walking step, S7's step detector with the §8.3.2 gate, ended within `steps.maxStanceMs`), and the rules need `gait.ruleSteps` steps per foot. With a model loaded, a stride with no model answer (no gap-free window yet, or a failed run) also shows the rules, with the "ยังไม่พร้อม" line. The rules never say `rotated_foot`.
- **Release builds have no model yet** (`mobile/assets/models/` holds only a README until Model A is trained after data collection (late Nov)), so they show the rules with "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่พร้อม". A model below `minConfidence` shows the rules with "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่มั่นใจพอ" (draft); "ประเมินโดย" then reads "กฎพื้นฐาน (โมเดล AI ยังไม่มั่นใจพอ)".
- **Confidence:** 2 segments "ปานกลาง" from `minConfidence`, 3 segments "สูง" from `model.highConfidence` (0.85, a new key).
- **"ตอนนี้":** "กำลังเดิน" while either usable foot is walking (as above; it starts at the first walking step and lasts up to `steps.maxStanceMs` after the last); "ยืนหรือนั่งอยู่" otherwise; "—" in `inkMuted` when no foot is usable.
- **"ก้าววันนี้":** both feet's walking steps (the engine's step detector) added together, stored in `daily_summary.steps` at most every 30 s, on a day change and on stop, and carried over a restart. It still shows today's number with no insole connected.
- **No result now:** walking but too few steps yet uses the not-walking layout ("ยังไม่มีผลตอนนี้"). "ผลล่าสุด HH:mm · {ท่า}" shows the newest earlier result of this run (memory only) and is hidden when there is none, and while a foot is not usable (no data shows no data; user decision 2026-10-25).
- **No data or one foot missing** (rule 4): the estimate card uses the not-walking layout with `bluetooth-off`, "ยังไม่มีข้อมูล" / "ต้องเชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน" (draft) and "เชื่อมต่อแผ่นรองเท้า"; the balance card shows "—" with "ต้องเชื่อมต่อทั้งสองข้าง".
- **Balance card:** the same share, note and deadband as Home's balance card (Home's view model), so the two screens always agree. While `ASYMMETRY_PEAK` holds, the number and note are `#5E3E00` with `triangle-alert` (§14 default, now built). The bar grows from 50 : 50 each time the bottom-bar tab or the sub-tab opens.
- **Details:** while walking (as above), "ความไม่สมดุลของแรงกด (PAI)" is the engine's latest step-pair PAI (what `ASYMMETRY_PEAK` compares), with "(เฝ้าระวังเมื่อเกิน {asymmetry.peakPct}%)". "ความไม่สมดุลของแรงกดสะสม" is the PTI asymmetry (DATA-CONTRACT §8 addendum, display only) with "(ค่าอ้างอิง {asymmetry.ptiPct}% · ยังไม่ใช้แจ้งเตือน)" (draft; the board's "(เฝ้าระวังเมื่อเกิน 20%)" would promise an alert that does not exist). Otherwise the details show "ความไม่สมดุลของแรงกดขณะยืน" instead (user decision 2026-10-25): the PAI formula on the two feet's mean loads over Home's 10 s balance window. The CoP's "ซ้าย"/"ขวา" labels stay as built (user decision). Window and stride come from `model_input.json`. A two-foot figure with a foot missing reads "— (ต้องเชื่อมต่อทั้งสองข้าง)".
- **CoP:** per sample Σ kPa × zone position / Σ kPa over the latest step's samples, on the placeholder zone positions (§5), thinned for drawing; outline only until a step exists. Shown while walking.
- **Large text:** "ยืนหรือนั่งอยู่" (24/700) wraps to two lines in its half-width card at 390 dp even at 100 % text (BACKLOG 50); the cards stack above 1.3 like Home's.
- **Motion:** balance bar `value` from 50 : 50; steps count with `value`; confidence segments change colour with `enter`; probability bars move with `value`. Reduce motion: all instant.

### 8.4 Built in S6B part 2 (decisions and defaults not on the boards)

User decisions 2026-10-25 and the defaults applied with them; report 033.

- **Banners come from each tab's own rules,** not from Home's overall status. Pressure is Be careful only while a level-3 pressure rule holds (`PRESSURE_PEAK`, `PRESSURE_PTI`, `LOAD_CONCENTRATION`; the one Home's ranking would name), and its title and line are that alert's own copy (`alertCopyFor` title / detail), so the `watch` preset reads "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" rather than the board's wording. Level 2 keeps the Safe banner. Temperature is Rest only while `TEMP_DELTA` holds (2 readings); the site with the larger ΔT names it.
- **"ดูสิ่งที่ควรทำ"** opens the newest stored alert with the banner's code, foot and zone (pressure) or site (temperature), the key repeats are suppressed by; it is hidden until that row exists.
- **Pressure, one foot missing:** No-data banner "ยังไม่ได้รับข้อมูลเท้า{ข้าง}" / "ต้องเชื่อมต่อแผ่นรองเท้า{ข้าง}ก่อน" + "เชื่อมต่อแผ่นรองเท้า". A level-3 rule on the connected foot wins over it (as Home, BACKLOG 38). The connected foot keeps its map, top-3 rows and numbers; the missing foot has the dashed No-data map and "—".
- **Temperature, both feet missing:** the Pressure No-data banner. Both feet stream but no site can be compared (poor contact, sensor fault): No-data banner "เทียบความอุ่นไม่ได้" / "ตอนนี้แผ่นรองเท้ายังวัดความอุ่นไม่ได้", no button. Close with no reading stored yet: "รอผลการวัด". One foot missing that gave no reading today: "เท้า{ข้าง}ยังไม่ได้เชื่อมต่อ"; otherwise "ตั้งแต่ HH:mm" is its last sample in this run, else its last stored reading today.
- **Header:** "อัปเดตเมื่อสักครู่" while a foot streams. Above 1.3 text scale the line goes under the title (and the two site cards stack, as Home's small cards).
- **Top 3:** zones ranked by the higher kPa of the two feet; "ทั้งสองข้าง" when both feet's zone is at the same level, "น้อย" included. The kPa table uses the same 2 s peaks as the dots.
- **Detail figures** come from the alert engine's walking gate and step detector: peak = the highest zone kPa while walking in the last 5 min; PTI = the highest zone's mean per-step PTI over `ptiWindowMin` (the number the rule compares; display only, decision 4); single point = the highest per-step top-zone share among walking steps in the last 5 min. "—" for a foot that is not usable or has no step yet.
- **Site cards:** the note follows Home's rule ("{ข้าง}อุ่นกว่า" once one reading is above `deltaC`); the Rest colour, icon and red site dot only while `TEMP_DELTA` holds there. So for one reading the Close banner can sit above a card saying "{ข้าง}อุ่นกว่า"; the banner turns to Rest with the second reading (rule 6). Both feet stream but the site has no value: "ยังวัดไม่ได้".
- **Chart:** a point is |ΔT| whenever one foot's `normal` reading meets the other foot's newest `normal` reading no more than `notifyPeriod` older (the engine's pairing). The line breaks where points are more than 3 × `notifyPeriod` apart. A foot silent that long is a gap (dashed line); it is open, with no line after it, while that foot is not usable or has stored nothing for that long. Gaps of both feet starting together are one gap. Only the newest gap is labelled (294 px is too narrow for more): "ขาดข้อมูล / ตั้งแต่ HH:mm" only while the gap is open; once the foot's data came back, "ขาดข้อมูล / HH:mm–HH:mm" (start–end), so an ended gap never reads as still disconnected (user decision 2026-10-25). The label sits right of its line, or left when there is no room; when neither side fits (large text), the range breaks after the dash and the label stays left of the line, clamped to the plot's left edge. It is on an 85 % white backdrop over any line it crosses. "ระดับที่ควรระวัง" moves to the band's right end when a gap line would cross it. One end dot per line, red while that site's last ΔT is above `deltaC`. With large text the middle time label is dropped, then the start one, rather than overlap. Empty day: "ยังไม่มีข้อมูลวันนี้" over the empty chart.
- **Chart summary (screen reader)** per site: "{จุด}ขึ้นถึงระดับที่ควรระวังตั้งแต่ราว HH:mm ตอนนี้ x.x องศา", "{จุด}เคยขึ้นถึงระดับที่ควรระวังช่วง HH:mm–HH:mm ตอนนี้ x.x องศา", or "{จุด}ต่ำกว่า x.x องศาตลอด"; "ล่าสุด" instead of "ตอนนี้" during an open gap; "{จุด}ยังไม่มีข้อมูล" for a site with no point; then "ขาดข้อมูลเท้า{ข้าง}ตั้งแต่ HH:mm" for an open gap or "ขาดข้อมูลเท้า{ข้าง}ช่วง HH:mm–HH:mm" for an ended one, the same times as the drawn label. No point at all today: "กราฟความต่างของความอุ่นวันนี้ ยังไม่มีข้อมูล".
- **"คุณภาพสัญญาณ":** "ดีทั้ง 4 จุด" only when all four sites have a `normal` reading; otherwise each foot that is not ("เท้าซ้าย สัมผัสไม่ดี" / "เท้าซ้าย เซนเซอร์ผิดปกติ"; "เท้าซ้าย ยังวัดไม่ได้" with no reading yet or a site the sensor could not read; rule 5).
- **Motion:** the indicator slides (`enter`), labels change colour in 200 ms, the old panel fades out (`exit`) and the new one fades in 80 ms later (`enter`). The chart draws in from the left (`value`) each time the bottom-bar tab or the sub-tab opens, never on a new reading. Reduce motion: all instant.

---

## 9. Connection (S8B)

- Back link, title "เชื่อมต่อแผ่นรองเท้า", line "เชื่อมต่อทีละข้าง ซ้ายและขวา".
- Info box until both feet are connected, except while Bluetooth is off or a wrong-side message is showing: "เปิดสวิตช์ที่กล่องอุปกรณ์บนส้นรองเท้า ให้ไฟติด แล้ววางโทรศัพท์ไว้ใกล้ ๆ".
- **Bluetooth off** panel (No-data background, radius 16, padding 20): 44 white circle with `bluetooth-off` 26 + "บลูทูธของโทรศัพท์ปิดอยู่" (20/700) + "เปิดบลูทูธก่อน แล้วค่อยเชื่อมต่อแผ่นรองเท้า" (18) + primary "เปิดบลูทูธ" (`bluetooth`). Both foot cards then show "รอเปิดบลูทูธ".
- **One card per foot** (white, radius 16, padding 20, gap 16; `divider` 1 px only when connected or waiting for Bluetooth, `outline` 1.5 px in every other state; polite live region): 64×64 visual + "เท้าซ้าย" / "เท้าขวา" (22/700) + status (16/700) + optional line (16 `inkMuted`); optional message box (radius 12, padding 16, text 16); optional full-width button.

| State | Visual | Status (colour) | Message | Button |
|---|---|---|---|---|
| Not connected | 48 circle `track` + `bluetooth` `inkMuted` | "ยังไม่ได้เชื่อมต่อ" (`inkMuted`) | — | Primary "เชื่อมต่อเท้าซ้าย" / "เชื่อมต่อเท้าขวา" |
| Searching | Ripple rings (`outline`, 2 px) around a radius-20 `primarySoft` disc with `bluetooth` `primary` | "กำลังค้นหา…" (`ink`) | — | Secondary "หยุดค้นหา" |
| Connecting | Same disc, no ripple | "พบแล้ว กำลังเชื่อมต่อ…" (`ink`) | Progress bar 8 tall, radius 4, `primary` on `track` (screen reader "กำลังเชื่อมต่อ"); one step per connect-sequence step (FLUTTER-PLAN §5) | — |
| Connected | Radius-22 `connected` disc with a white `check` | "เชื่อมต่อแล้ว" (`ink`) | Line "แบต {n}% · เฟิร์มแวร์ {version}" (low-battery style when low, §5) | Secondary "ยกเลิกการเชื่อมต่อ" |
| Wrong side (rule 8: rejected) | 48 Be-careful circle + `triangle-alert` | "แผ่นที่พบเป็นของเท้าขวา" (Be-careful text) | Be-careful box: "ใส่แผ่นนี้ที่รองเท้าข้างขวา หรือเปิดแผ่นของเท้าซ้ายแล้วค้นหาอีกครั้ง" (sides swap for the right card) | Primary "ค้นหาอีกครั้ง" |
| Not found | 48 No-data circle + `search` | "ไม่พบแผ่นรองเท้า" (No-data text) | No-data box, numbered: "ตรวจว่าไฟที่กล่องอุปกรณ์ติดอยู่" / "ถ้าไฟไม่ติด ให้ชาร์จแบตเตอรี่ก่อน" / "วางโทรศัพท์ไว้ใกล้แผ่นรองเท้า" | Primary "ค้นหาอีกครั้ง" |
| Connected, no data (e.g. MTU too small, S3A note) | 48 Be-careful circle + `triangle-alert` | "เชื่อมต่อแล้ว แต่ยังไม่ได้รับข้อมูล" (Be-careful text) | Be-careful box: "ลองยกเลิกการเชื่อมต่อ แล้วเชื่อมต่อใหม่อีกครั้ง" | Primary "เชื่อมต่อใหม่" |
| Bluetooth off | 48 No-data circle + `bluetooth-off` | "รอเปิดบลูทูธ" (`inkMuted`) | — | — |

- When both feet are connected: the info box hides and a primary "เสร็จแล้ว กลับหน้าวันนี้" (`check`) appears → Home.

## 10. Settings (S8B)

### 10.1 Main ("ตั้งค่า")

Back link (→ Home), title "ตั้งค่า", then groups. Each group: label 16/700 `inkMuted`, 8 above a card of list rows (§5).

| Group | Content |
|---|---|
| "ข้อมูลของคุณ" | Row `user`: "ชื่อที่ใช้ทักทาย" / value "สมชาย" → name editor (not designed). No name → Home shows "สวัสดี". |
| "การแสดงผล" | `type` "ขนาดตัวอักษร"; 3 options in a radio group: "ปกติ" / "ใหญ่" / "ใหญ่มาก" (min height 52, radius 12; selected `primary` fill + white 700, others white + `outline` 1.5 + `ink` 600). Preview box (`bg`, radius 12, padding 16): "ตัวอย่าง" (16 `inkMuted`) + "ตอนนี้เท้าปลอดภัย" at 18 / 22 / 26 px (700, heading font). Note "ใช้ร่วมกับขนาดตัวอักษรที่ตั้งไว้ในโทรศัพท์". Default "ปกติ" (decision 11; the board shows "ใหญ่" selected only as an example). Scale factors: proposed, §14. |
| "การแจ้งเตือน" | Switch `volume-2` "เสียงแจ้งเตือน" · switch `camera` "เตือนให้ดูเท้าทุกวัน" · row `clock` "เวลาเตือน" / "ทุกวัน 19:00" → time picker (not designed). |
| "แผ่นรองเท้า" | Row `bluetooth` "เชื่อมต่อแผ่นรองเท้า" / "เชื่อมต่อแล้วทั้งสองข้าง" → Connection. |
| "ข้อมูลในเครื่องนี้" | Text row `lock`: "ข้อมูลและรูปถ่ายเท้าเก็บไว้ในโทรศัพท์เครื่องนี้เท่านั้น ไม่ได้ส่งไปที่ไหน". Destructive row in Rest colours (`#FBE3DF` circle, `trash-2` `#B42318`, title and chevron `#7F1D12`): "ลบรูปถ่ายเท้าทั้งหมด" / "ตอนนี้มี 28 รูป" → confirmation sheet (proposed, §14). |
| "สำหรับผู้วิจัย" | Row with a No-data circle and `lock` `#55666E`: "ส่วนผู้วิจัย" / "กดค้าง 2 วินาทีเพื่อเปิด"; opens only after a 2-second long press. |
| "เกี่ยวกับแอป" | "เวอร์ชัน" — "0.9.0 · รุ่นทดสอบงานวิจัย"; under a divider: "แอปนี้ช่วยดูแลเท้า ไม่ใช่เครื่องมือวินิจฉัยโรค ถ้ามีแผลหรืออาการผิดปกติ ให้ไปพบแพทย์". |

The debug screen is hidden (S8B): it is "Diagnostics", reached only from Researcher (§10.2), in release builds too.

### 10.2 Researcher ("ส่วนผู้วิจัย")

- Back link (→ Settings), title "ส่วนผู้วิจัย".
- Warning box (radius 16): "ใช้ระหว่างการทดสอบงานวิจัยเท่านั้น ผู้ใช้ทั่วไปไม่ต้องใช้ส่วนนี้".
- Card "เก็บข้อมูลวิจัย": readiness checks, each with `circle-check` 24 `#2E7D4F` and text 16: "เชื่อมต่อแล้วทั้งสองข้าง", "แบตเตอรี่ 80% ขึ้นไปทั้งสองข้าง (ซ้าย 92% · ขวา 88%)", "รับข้อมูลครบ 50 ครั้งต่อวินาทีทั้งสองข้าง". Primary "เริ่มเก็บข้อมูลวิจัย" (`flask-conical`) → the S4C capture flow. Row "ส่งออกไฟล์" / "ล่าสุด S07 · 21 ต.ค. · 6 ไฟล์" (`divider` top border).
- Card "อุปกรณ์": row `gauge` "ตั้งค่าศูนย์เซนเซอร์ (TARE)" / "ยกเท้าออกจากแผ่นรองเท้าก่อน" → TARE sheet; row `power` "รีสตาร์ตแผ่นรองเท้า" / "ใช้เมื่อแผ่นรองเท้าค้าง" → confirmation (proposed); footer "ทั้งสองอย่างทำไม่ได้ระหว่างเก็บข้อมูลวิจัย" — both are disabled while a research capture runs (BACKLOG 21).
- Card "ข้อมูลอุปกรณ์": "เฟิร์มแวร์" "ซ้าย 1.0.3 · ขวา 1.0.3" · "ขนาดแพ็กเก็ต (MTU)" "247" · "อัตราข้อมูล" "50 ครั้ง/วินาที ต่อข้าง".
- **TARE sheet** (bottom sheet, §5): "ตั้งค่าศูนย์เซนเซอร์" · "ใช้เมื่อค่าแรงกดไม่เป็นศูนย์ ทั้งที่ไม่มีใครเหยียบแผ่นรองเท้า" · steps "ให้ผู้สวมนั่งลง แล้วยกเท้าทั้งสองข้างให้ลอยจากพื้น" and "กด \"ตั้งค่าศูนย์\" แล้วรอจนขึ้นว่าเสร็จ" · warning "อย่าทำระหว่างเก็บข้อมูลวิจัย ค่าแรงกดที่บันทึกจะเพี้ยน" · buttons "ยกเลิก" / "ตั้งค่าศูนย์".
- The research capture screens themselves (S4C) are not on the canvas; they use these tokens and components, with large targets for one-handed use while walking.

---

## 11. Daily foot check (S8C)

Flow: Start → Capture (4 photos) → Compare & answer → Saved, or Something found. Options from FLUTTER-PLAN §9: answer only, 3-second self-timer, skip a photo. Photos stay on the device (rule 15). The app never says a foot is normal (rule 14). The "ตรวจเท้า" tab opens Start until today's check is saved, then Saved (decision 8), or the found-today view (§11.6) when today's check found something.

S8C (user, 2026-10-26): a day can have several checks; the latest one is that day's result (tab, Home card, 7-day row), and every check that found something keeps its own alert. "ตรวจอีกครั้ง" on Saved / found-today shows Start in the tab with a back link. Home's foot-check card shows only while today has no saved check (the day is re-checked at midnight and on resume, so the card comes back on a new day).

### 11.1 Start (bar visible)

1. Title "ตรวจเท้าประจำวัน".
2. Time card (`primarySoft`, radius 16, padding 16 20): `timer` 26 `ink` + "ใช้เวลาประมาณ 1 นาที" (18/700).
3. Reason (18, line height 1.6): "แผ่นรองเท้าวัดได้เฉพาะใต้ฝ่าเท้า การดูเท้าทุกวันช่วยให้เห็นแผลที่ปลายนิ้วหรือหลังเท้า ซึ่งอาจเกิดขึ้นโดยไม่รู้สึกตัว".
4. Card "ทำอะไรบ้าง" with steps "ถ่ายรูปเท้า 4 ภาพ ฝ่าเท้าและหลังเท้าทั้งสองข้าง", "ดูรูปวันนี้เทียบกับเมื่อวาน", "ตอบคำถามสั้น ๆ 3 ข้อ".
5. Tip box (`lightbulb`): "มองฝ่าเท้าไม่ถนัด วางโทรศัพท์บนพื้นแล้วใช้ปุ่มตั้งเวลา หรือให้ญาติช่วยถ่ายก็ได้".
6. Privacy line (`lock` 22 + 16/600 `ink`): "รูปเก็บไว้ในโทรศัพท์เครื่องนี้เท่านั้น".
7. Primary "เริ่มถ่ายรูป" (`camera`) and secondary "ไม่ถ่ายรูป ตอบคำถามอย่างเดียว" (gap 12).

### 11.2 Capture (full screen, camera colours)

Positions are for the 390×844 reference.
- Top row (top 8, height 48): "ยกเลิก" (`x` 24 + 18/600 white, min height 48) on the left; counter "ภาพที่ {n} จาก 4" (16 `camText2`, polite live region) on the right, then "สลับกล้อง" (S8C: `switch-camera` 26 white in a 48×48 button, screen-reader label "สลับกล้อง").
- Camera (S8C): soles open the front camera, tops the back camera. "สลับกล้อง" holds for the same kind of view (sole / top) for the rest of this check. The front preview is mirrored; the guide outline is drawn to match what the preview shows; the saved photo is always the true view (never mirrored), so a left sole looks the same whichever lens took it (user decision 1). Saved photos are cropped to the viewfinder's aspect, long side 1600 px, JPEG quality 85, with no EXIF or other metadata, in the app's private folder (never the gallery).
- "ยกเลิก" (S8C, user addition 7): leaves at once while no photo is taken; with a photo, first a confirm sheet (§10.1 TARE pattern, draft) "ยกเลิกการตรวจครั้งนี้?" / "รูปที่ถ่ายไว้จะถูกลบ" with "ถ่ายต่อ" and "ยกเลิกการตรวจ" (deletes this check's photos). "กลับ" from Compare returns to the first view with the photos kept; a new shot replaces that view's photo.
- Camera unavailable (S8C, draft): the viewfinder shows `camera-off` + "ต้องอนุญาตให้ใช้กล้อง" / "แอปใช้กล้องเพื่อถ่ายรูปเท้าเท่านั้น รูปเก็บไว้ในโทรศัพท์เครื่องนี้" with "อนุญาตให้ใช้กล้อง" (asks again, or opens the app's settings), or "เปิดกล้องไม่ได้" / "ลองใหม่อีกครั้ง หรือตอบคำถามอย่างเดียวก็ได้" with "ลองใหม่"; both offer "ไม่ถ่ายรูป ตอบคำถามอย่างเดียว".
- View name (32/700 white, top 64) in the order "ฝ่าเท้าซ้าย" → "ฝ่าเท้าขวา" → "หลังเท้าซ้าย" → "หลังเท้าขวา", over the hint "ให้เท้าอยู่ในกรอบ และมีแสงสว่างพอ" (18 `camText2`).
- Viewfinder (342×416 at top 164, radius 24, `camViewfinder`; the camera preview fills it): dashed foot guide 140×312 (`camGuide`, 2.5 px, dash 7 6), left or right outline to match the view; screen-reader label "กรอบวาง" + view name. Hint chip at its bottom: "วางโทรศัพท์บนพื้น แล้วใช้ปุ่มตั้งเวลา" (`camBg` 85 %, radius 16, padding 8 14, 16 `camChipText`). Countdown: 132 disc (`camBg` 80 %) in the centre, digit 72/700 white, announced assertively.
- Slot strip (top 596, 4 columns): 60×60 slots, radius 14, labels "ฝ่าซ้าย" "ฝ่าขวา" "หลังซ้าย" "หลังขวา" (16; current white 700, others `camText2` 500). Current: 2 px solid `camGuide`. Taken: `camSlotDone` fill with a thumbnail and a 22 check badge (`camGuide` disc, `camBg` check). Not taken: 2 px dashed `camSlotTodo`. Screen readers hear the label + "ถ่ายแล้ว" / "กำลังถ่าย" / "ยังไม่ได้ถ่าย".
- Controls (top 704, 3 columns): "ตั้งเวลา 3 วิ" (64 `camGuide` circle with `timer` 26 `camBg`; 4 px white ring while counting; label 16/600 white) · shutter 80 (5 px white ring around a 58 white disc; screen-reader label "ถ่ายรูป") · "ข้ามภาพนี้" (64 circle, white 16 %, `skip-forward` white).
- After the 4th photo or skip → Compare & answer.

### 11.3 Compare & answer (no bar)

1. Back link (→ Capture; → Start when answering only), title "เทียบกับเมื่อวาน".
2. View picker (segmented control as a radio group "รูปที่ดู", options 16): "ฝ่าซ้าย" / "ฝ่าขวา" / "หลังซ้าย" / "หลังขวา".
3. Photos side by side (gap 16): 196 tall, radius 16, `camViewfinder` placeholder; today has a 3 px `primary` border. Captions "เมื่อวาน · 20 ต.ค." (16 `inkMuted`) and "วันนี้ · 21 ต.ค." (16/700 `ink`). Screen-reader labels "รูป" + view name + "เมื่อวาน" / "วันนี้". S8C: the left photo is the newest photo of that view from an earlier day (today's don't count): "เมื่อวาน · {d MMM}" when it is from yesterday, otherwise "ครั้งก่อน · {d MMM}"; with none, a dashed frame "ยังไม่มีรูปก่อนหน้า" over the caption "ครั้งก่อน". A view skipped today shows a dashed frame "ไม่ได้ถ่ายภาพนี้" (draft). Answer-only has no picker and no photos (§14).
4. Questions card (padding 24, gap 24); each question is a radio group named by its text (18/600) with two options (2 columns, gap 12; min height 56, radius 14). No answer is selected when the screen opens (decision 9; the board shows sample answers):
   - "เห็นรอยแดง หรือผิวเปลี่ยนสีไหม"
   - "เห็นแผล รอยถลอก หรือตุ่มพองไหม"
   - "เท้าบวม หรือผิดรูปไปจากเดิมไหม"
   - "ไม่มี" selected: `primarySoft` fill, 2 px `primary` border, `check` 20, 700. "มี / ไม่แน่ใจ" selected: `#FFF0D2` fill, 2 px `#A86A00` border, `triangle-alert` 20 `#A86A00`, text `#5E3E00` 700. Unselected: white, `outline` 1.5 px, `ink` 600.
5. Info box: "แอปไม่ได้ตรวจรูปให้ ถ้าเห็นอะไรผิดปกติหรือไม่แน่ใจ ให้ตอบว่า \"มี / ไม่แน่ใจ\"" (keep the quoted answer on one line).
6. Primary "บันทึก" → Something found if any answer is "มี / ไม่แน่ใจ" ("not sure" counts as abnormal), otherwise Saved.

### 11.4 Something found (no bar, no back link)

1. Card (Be-careful background, radius 20, padding 24, gap 12): 56 white circle with `triangle-alert` 32 → "พบสิ่งที่ควรให้แพทย์ดู" (28/700 `#5E3E00`) → "คุณตอบว่า" (16/700) + one line (18) per "มี / ไม่แน่ใจ" answer: the question without the final "ไหม", e.g. "เห็นแผล รอยถลอก หรือตุ่มพอง".
2. Emphasised card "สิ่งที่ควรทำตอนนี้", steps: "ล้างเท้าด้วยน้ำสะอาด แล้วซับให้แห้ง", "ถ้ามีแผล ปิดด้วยผ้าก๊อซสะอาด", "เดินให้น้อยลง และอย่าเดินเท้าเปล่า", "ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู".
3. Urgent box: "ไปโรงพยาบาลทันที ถ้ามีไข้ เท้าบวมแดงลามออกไป มีหนอง หรือมีกลิ่น".
4. Disclaimer line.
5. Secondary "ดูรูปที่บันทึกไว้" (`image`) and primary "เข้าใจแล้ว กลับหน้าหลัก" → Home.

The result is logged as an alert (§7.1, foot-check finding).

### 11.5 Saved (bar visible)

1. Title "ตรวจเท้าประจำวัน".
2. Card (white, `divider`, radius 20, padding 24): 64 `primarySoft` circle with `check` 34 `primary` → "บันทึกแล้ว เจอกันพรุ่งนี้" (28/700) → "วันนี้ดูเท้าแล้ว เวลา {HH:mm}" and "พรุ่งนี้แอปจะเตือนตอน {HH:mm}" (16 `inkMuted`; the second line only while the reminder is on).
3. If yesterday's check found something, a warning box (padding 16 20): "เมื่อวานพบสิ่งที่ควรให้แพทย์ดู ถ้ายังไม่ได้ไป ควรไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน".
4. Card "7 วันที่ผ่านมา": 7 columns (gap 4), oldest first: day abbreviation (16; today 700 inside a 1.5 px `outline` frame, radius 12), then a 32 circle: saved = `primarySoft` + `check` `primary`; found = `#FFF0D2` + `triangle-alert` `#A86A00`; missed = 2 px dashed `inkSubtle` ring. Legend "บันทึกแล้ว" / "ควรให้แพทย์ดู" / "ไม่ได้ดู". Screen readers: list "ผลการดูเท้า 7 วันที่ผ่านมา"; each day reads e.g. "วันนี้ พ บันทึกแล้ว".
5. Secondary "ตรวจอีกครั้ง" (S8C) and "ดูรูปที่บันทึกไว้".

The "พรุ่งนี้แอปจะเตือนตอน" line also hides while the phone does not allow the app's notifications (§11.8).

### 11.6 Found today (bar visible; S8C, user decision 4, the approved proposal)

Today's latest check found something. Title "ตรวจเท้าประจำวัน", then a Be-careful card (radius 20, padding 24): 56 white circle with `triangle-alert` → "วันนี้พบสิ่งที่ควรให้แพทย์ดู" (28/700 `#5E3E00`) → "ดูเท้าแล้ว เวลา {HH:mm}" → "คุณตอบว่า" + the answer lines (as §11.4) → a white link row "ดูสิ่งที่ควรทำ" (`chevron-right`) opening Something found for that check → the reminder line. Yesterday's warning box is hidden. Then the 7-day card (today = found) and secondary "ตรวจอีกครั้ง" and "ดูรูปที่บันทึกไว้".

### 11.7 Photo history and viewer (S8C, draft from §5 components)

"ดูรูปที่บันทึกไว้" opens a pushed page: back link, title "รูปที่บันทึกไว้", info box (`lock`) "รูปเก็บไว้ 30 วัน ลบรูปทั้งหมดได้ที่หน้าตั้งค่า". Checks with photos, grouped by day (header "วันนี้ · อาทิตย์ 18 ต.ค." style, newest first); one card per check with "เวลา {HH:mm}" and a status tag ("บันทึกแล้ว" in the saved colours, never green; "ควรให้แพทย์ดู" Be careful), then the 4 views as square thumbnails (radius 14) with the slot labels; a skipped view is a dashed "ไม่ได้ถ่าย". Answer-only checks are not listed. Empty: `image` circle, "ยังไม่มีรูปที่บันทึกไว้", "รูปจากการดูเท้าประจำวันจะอยู่ที่นี่". Tap a photo: full screen on `camBg`, pinch to zoom, "ปิด" (`x`) top left and "{view} · {date} {HH:mm}" top right. View-only; deleting stays in Settings.

### 11.8 Evening reminder (S8C)

A system notification while "เตือนให้ดูเท้าทุกวัน" is on: "ถึงเวลาดูเท้าประจำวัน" / "ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที", at the set time in the phone's time zone, for the next 14 days (one-shot, inexact: Android may deliver it a few minutes late). Today's is cancelled once today's check is saved. It restores after a reboot. Tapping it opens the "ตรวจเท้า" tab. "เสียงแจ้งเตือน" off makes it silent (shown, no sound or vibration; user decision 2). Android 13+ asks for the notification permission at the first open of the tab and when the switch is turned on; while it is refused, Settings shows "ต้องอนุญาตการแจ้งเตือนในโทรศัพท์" / "ตอนนี้แอปเตือนให้ดูเท้าไม่ได้ แตะเพื่อเปิด" (draft, `bell-off`, No-data circle) under the switch, which asks again or opens the app's notification settings (user decision 3).

---

## 12. Motion

Reference boards: HomeDMotion, AlertsDMotion, FeetDMotion, ConnectDMotion, CheckDMotion (each has a "reduce motion" switch). The boards loop for the demo; the app plays each animation once per real event. All values live in `lib/ui/motion.dart` (FLUTTER-PLAN §8).

### 12.1 Tokens

| Token | Value | Flutter | Use |
|---|---|---|---|
| `exit` | 200 ms, cubic-bezier(0.32, 0, 0.67, 0) | `Cubic(0.32, 0.0, 0.67, 0.0)` | Old content fading out; collapsing |
| `enter` | 300 ms, cubic-bezier(0.33, 1, 0.68, 1) | `Cubic(0.33, 1.0, 0.68, 1.0)` | New content in; expanding; colour changes; dot fill and size |
| `value` | 400 ms, same curve as `enter` | `Cubic(0.33, 1.0, 0.68, 1.0)` | Numbers counting, bars, chart draw-in, photo fly |
| `stagger` | 40 ms per item | — | Entrance of cards and list items (rise 12 px + fade, `enter`) |
| `pop` | 300 ms, cubic-bezier(0.34, 1.3, 0.64, 1) | `Cubic(0.34, 1.3, 0.64, 1.0)` | Badge count, connected disc (scale 0.6 → 1, slight overshoot) |
| `pulse` | Every 1.6 s; the ring grows for 1.4 s with the `enter` curve | — | "High" dots, scanning ripple |
| `wiggle` | −14°, 12°, −8°, 6°, 0°, 110 ms per step, ease-in-out | `Curves.easeInOut` | Bell on a new alert (pivot at 50 % width, 15 % height) |
| `chevron` | 200 ms, ease | `Curves.ease` | Details-expander chevron |
| `press` | 150 ms, ease | `Curves.ease` | Self-timer button ring |

Define the curves as constants in `motion.dart`. Flutter's named `Curves.easeInCubic` (0.55, 0.055, 0.675, 0.19) and `Curves.easeOutCubic` (0.215, 0.61, 0.355, 1.0) are different curves and do not match the boards.

### 12.2 Per screen

| Screen | Animation |
|---|---|
| All screens | Material page transitions between screens (FLUTTER-PLAN §8, S1B). Screens not listed below have no other motion. |
| Home | On open: header, chips, status card, foot-check card, pressure card and small cards rise in with `stagger`. Status change: title, detail and icon fade out (`exit`), then the new ones fade in (`enter`; the icon also scales 0.85 → 1); the card colour cross-fades (`enter`); the advice box and connect button expand (`enter`) or collapse (`exit`). Dots tween fill and size (`enter`). Numbers count to the new value and the balance bar slides (`value`). Chip dots change colour (`enter`). "High" dots: a 2.5 px `#C2410C` ring grows from radius + 1 to + 12 while fading 0.5 → 0 (`pulse`). New alert: bell `wiggle` + badge `pop`. |
| Alerts | On open: title, group titles, cards and footer rise in with `stagger`. A new alert opens a row at the top of "วันนี้" (height + fade, `enter`) and slides down from −8 px; the unread line updates; badge `pop`; bell `wiggle`. |
| Alert detail | Chevron turns (`chevron`); the details appear without a height animation. |
| My feet | The selected-tab indicator slides (`enter`); labels change colour (200 ms). The panel fades out (`exit`) and the new one fades in (`enter`, 80 ms delay). Dots tween (`enter`). The temperature chart draws from left to right (`value`). The balance bar grows from 50 : 50 to its value (`value`). |
| Connection | Searching: a ring grows from radius 20 to 31 and fades 0.6 → 0 (`pulse`). Connecting: the bar follows the real connect steps. Connected: disc `pop`, then the check stroke draws (`enter`, 120 ms delay). "เสร็จแล้ว กลับหน้าวันนี้" fades in (`enter`, 200 ms delay). |
| Foot check › Capture | Self-timer: `press` ring, then "3", "2", "1" one second apart, each scaling 0.8 → 1 with a fade (200 ms, `enter` curve). After the shot, the thumbnail flies from the viewfinder into its slot (move + scale to 0.43, `value`) and fades (150 ms, starting at 380 ms). The next view name and guide fade in (200 ms). |

### 12.3 Reduce motion (system setting; FLUTTER-PLAN rule 16)

Everything jumps to its end state. "High" dots show a still ring (radius + 5, opacity 0.6). Scanning shows two still rings (radius 24 at 50 %, radius 30 at 25 %). Countdown digits still change every second, without scaling or fading. New alerts and numbers appear at once. 10 Hz updates must never stutter: dot and number tweens retarget smoothly.

---

## 13. Accessibility

- Text contrast: AA is the minimum (4.5:1; 3:1 for 24 px and larger). The style D boards meet AAA (7:1 body, 4.5:1 large); keep that for any new colour pair.
- Text is 16 or larger (the badge count, 14, is the only exception) and survives large system text without clipping.
- Touch targets ≥ 48 × 48 (rows 72, buttons 56, capture controls 64 and 80).
- Every icon-only control has a TalkBack label (e.g. "ตั้งค่า", "กลับ", "ถ่ายรูป"); the Alerts tab label carries the unread count (§4).
- Foot maps, charts, capture slots and history days have TalkBack descriptions, e.g. "เท้าซ้าย ปลายเท้ารับน้ำหนักมาก".
- Roles: sub-tabs are tabs; the view picker, answers and text-size options are radio groups; switches expose on/off; the details expander exposes expanded/collapsed; the connecting bar is a progress bar.
- Live regions: Home status card, Alerts unread line, My feet banner and connection foot cards (polite); capture counter (polite) and countdown (assertive).
- Status is never shown by colour alone (icon + text + colour); colours that must be told apart differ in both hue and lightness.

---

## 14. Decisions and open items

### Decisions (user, 2026-10-22)

1. Alert codes follow DATA-CONTRACT v1.5 §8.3: 8 codes. (An earlier "9" in the plan was an error; fixed in S6A.)
2. Status card radius is 20 (the canvas value). The 28 in the Home-only v2 was a misreading of the 56 px icon circle.
3. Placeholder sensor positions (§5) are fine until `shared/sensor_layout.json` exists.
4. PTI is display-only: its values stay only under "ดูตัวเลขละเอียด" until S7 settles its meaning (BACKLOG 31). The `PRESSURE_PTI` alert is still raised as the contract defines it.
5. Draft health advice stays marked as draft until the medical expert reviews it (Appendix A).
6. Volunteer manual (IRB doc 05) screenshots will not match the new UI; the user asks the advisor on Mon 2026-10-26 whether an IRB amendment is needed.
7. An alert becomes read once the user opens it (§7.2).
8. The "ตรวจเท้า" tab shows Saved after today's check is saved (§11).
9. Foot-check questions start with no answer selected (§11.3).
10. Low battery uses dark amber text plus a battery icon (§5).
11. Text size defaults to "ปกติ" (§10.1).

Earlier design-chat decisions: style D for the whole app; plain Thai first with numbers behind "ดูตัวเลขละเอียด"; level-2 events not in the Alerts list; My feet as 3 sub-tabs. The user also asked for motion after the first Home design had none; §12 covers it.

### Decisions (user, 2026-10-26, S8C)

12. The saved photo is the true view; the front preview stays mirrored and the guide matches the preview (§11.2).
13. "เสียงแจ้งเตือน" off makes the evening reminder silent, still shown (§11.8).
14. Notification permission: asked at the first open of "ตรวจเท้า" and when the reminder switch is turned on; refused → Settings line, Saved hides the reminder line (§11.8).
15. The found-today tab is the approved proposal (§11.6).
16. Reminders use the phone's time zone, never UTC.
17. Saved photos carry no EXIF or other metadata.
18. "ยกเลิก" on Capture asks first once a photo is taken (§11.2).
Also: a real system notification, compare with the newest earlier photo, several checks a day, automatic camera with a switch, no gallery, 1600 px / q85 photos, draft photo history.

### Proposed defaults (not on the boards; confirm or change before the session that builds them)

- **Alerts (S6B, built):** the "ยังไม่ได้อ่าน {n} รายการ" line is hidden when nothing is unread. Its live region stays in the tree (empty at 0), so TalkBack also announces the change from none to one.
- **Details expander (S6B, built):** starts closed each time a screen opens (the boards only show fixed open and closed versions).
- **Gait balance warning (S8A, built):** while `ASYMMETRY_PEAK` is active, the balance number and note use `#5E3E00` with a `triangle-alert` icon, as on Home (§8.5).
- **Gait tab (S8A, built):** see §8.5.
- **Foot check (S8C, built):** "บันทึก" is enabled after all 3 answers. Answer-only uses Compare & answer without the view picker and photos (title stays "เทียบกับเมื่อวาน"). See §11.2–§11.8 and report 036 for the drafts: camera switch, cancel sheet, camera panels, compare captions, found-today view, photo history, reminder and its permission line.
- **Switch off state (S8B, built):** "ปิด", knob on the left, `track` fill with a 2 px `inkSubtle` border; the off knob is `inkSubtle` so it shows on the light track. Above text scale 1.3 a switch goes under its row title.
- **Text size factors (S8B, built):** 22/18 for "ใหญ่" and 26/18 for "ใหญ่มาก" (from the preview sizes), multiplied with the phone's own text scale, never clamped.
- **Confirmations (S8B, built):** "ลบรูปถ่ายเท้าทั้งหมด", "รีสตาร์ตแผ่นรองเท้า" and the name editor use the TARE bottom-sheet pattern. TARE in progress has no buttons (a sent TARE cannot be taken back); done and failed have one "ปิด" button.
- **My feet (S6B part 2, built):** see §8.4.
- **Research readiness (S8B/S4C, built):** a failed check shows `triangle-alert` in `#A86A00` with its text and a reason in brackets (draft), and "เริ่มเก็บข้อมูลวิจัย" is disabled. The data-rate check passes at ≥ 49 samples/s per foot over 10 s (`CaptureTimings.minSampleRateHz`). "ส่งออกไฟล์" always opens capture.
- **Draft copy (S8B, not on the boards):** Researcher card "ตรวจสอบระบบ" with row "Diagnostics"; disabled TARE/reboot rows read "เชื่อมต่อแผ่นรองเท้าก่อน" when nothing is connected; readiness reasons in brackets ("(กำลังวัด)", "(ยังไม่ได้เชื่อมต่อ: ซ้าย)"); Settings "ยังไม่ได้ตั้งชื่อ", "ยังไม่มีรูปถ่ายเท้า", the one-foot and none lines of the insole row; every sheet's text other than TARE confirm. The permission panel (draft, §9) also hides the info box, like Bluetooth off.
- **Disabled rows (S8B, built):** TARE and reboot while a capture is open use the No-data icon circle, no chevron, and are announced as disabled buttons. While TARE runs, back and the scrim don't close its sheet.
- **Device info (S8B, built):** MTU and data rate show one value when both feet agree, as on the board, else "ซ้าย … · ขวา …".
- **Connection (S8B, built):** see §9 and report 035 (20 s search window, wrong side after 3 s with no other candidate, permission panel draft copy, "connected, no data" for stale / MTU too small / calibration rejected).

### Not designed yet (build from §5 components, or ask for a design)

- Built in S8C from §5 components with draft copy (report 036): photo history and viewer, Compare & answer with no earlier photo or a skipped view, the found-today tab (the approved proposal), the evening notification and its denied-permission line, camera panels, cancel sheet
- The Saved reminder for a finding older than yesterday
- Built in S8B from §5 components with draft copy (report 035): name editor, reminder time picker (platform, 24 h), TARE in progress / done / failed, reboot confirmation, delete-photos confirmation
- Research capture flow and export screens (S4C)
- `PRESSURE_PTI` alert copy (S7, drafted)
- Descriptions for "เดินกะเผลก", "เดินลงส้นเท้า", "เดินบิดปลายเท้า", and the rule-based line when the model is present but below `minConfidence` (S8A, drafted: Appendix A)
- An in-app banner for new alerts while another screen is open (today only the bell and badge react)

### Waiting on others

- `shared/sensor_layout.json`: real zone positions and channel mapping (hardware)
- PTI meaning, per step or per window (S7, BACKLOG 31)
- Medical expert review of Appendix A before 2026-11-05
- Advisor (2026-10-26): IRB doc 05 screenshots

### Board differences this spec settles

- The Alerts-tab screen-reader label on HomeD / HomeDMotion says "รายการใหม่"; use "แจ้งเตือน มี {n} รายการที่ยังไม่ได้อ่าน" everywhere (§4).
- The badge sits at top −4 / right 6 on HomeD and HomeDMotion and at −6 / 2 elsewhere; use −6 / 2.

---

## Appendix A — Draft health copy for the medical expert

Every string below is a draft (decision 5). Changes from the expert go into the boards' copy and this file before 2026-11-05.

| Where | Text |
|---|---|
| Home, Be careful | "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" · "ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่" |
| Home, Rest your feet | "เท้าขวาอุ่นกว่าเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก" · "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์" |
| Alerts list, "ควรทำ" | "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม" · "ลองเดินช้าลง ก้าวให้สั้นลง หรือนั่งพักสักครู่" · "ลองยืนให้น้ำหนักลงทั้งฝ่าเท้า หรือเปลี่ยนท่ายืน" · "ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู" · "ชาร์จแบตเตอรี่ก่อนใช้ครั้งต่อไป" · "ตรวจว่าแผ่นรองเท้าเปิดอยู่ แล้วเชื่อมต่อใหม่" |
| `TEMP_DELTA` detail | "ส้นเท้าขวาอุ่นกว่าส้นเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก" · steps "นั่งพักเท้า" / "ตรวจดูว่ามีรอยแดงหรือแผลไหม" / "ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์" · why "เมื่อเท้าข้างหนึ่งอุ่นกว่าอีกข้างที่ตำแหน่งเดียวกันต่อเนื่อง อาจเป็นสัญญาณเริ่มต้นของการอักเสบใต้ผิวหนัง ซึ่งมักเกิดก่อนจะเห็นแผล" |
| `PRESSURE_PEAK` detail | "โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงมากหลายก้าวติดกัน" · steps "ลองเดินช้าลง และก้าวให้สั้นลง" / "นั่งพักสักครู่ แล้วขยับเท้าเปลี่ยนท่า" / "ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า" · why "แรงกดที่สูงมากซ้ำ ๆ ที่จุดเดิมขณะเดิน อาจทำให้ผิวบริเวณนั้นช้ำและเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง" |
| `PRESSURE_PEAK` detail (S7, draft) | The board's "…หลายก้าวติดกัน" is not what the rule checks (one walking sample above the boundary raises it), so the app says "{จุด}{ข้าง}รับแรงกดสูงมากตอนเดิน", e.g. "โคนนิ้วหัวแม่เท้าซ้ายรับแรงกดสูงมากตอนเดิน". Steps and why as above |
| `PRESSURE_PTI` (S7, draft) | Title / Home "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" (board) · detail "{จุด}{ข้าง}รับแรงกดนานในทุกก้าว ต่อเนื่องมาตลอดช่วงที่ผ่านมา" · steps "นั่งพักเท้าสักครู่" / "ขยับเท้า เปลี่ยนท่ายืนหรือท่าเดิน" / "ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า" · why "เมื่อจุดเดิมของฝ่าเท้ารับแรงกดนาน ๆ ซ้ำทุกก้าว ผิวบริเวณนั้นอาจได้เลือดไปเลี้ยงน้อยลงและเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง" · ควรทำ "ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่" |
| `LOAD_CONCENTRATION` (S7, draft) | Title / Home "น้ำหนักลงที่{ส่วนเท้า}{ข้าง}จุดเดียวมากเกินไป" · detail "ทุกก้าวที่ผ่านมา น้ำหนักลงที่{จุด}{ข้าง}มากกว่าจุดอื่นของฝ่าเท้ามาก" · steps "ลองเดินช้าลง ให้น้ำหนักลงทั้งฝ่าเท้า" / "นั่งพักสักครู่ แล้วขยับเท้าเปลี่ยนท่า" / "ตรวจว่ารองเท้าไม่คับ และไม่มีอะไรอยู่ในรองเท้า" · why "เมื่อน้ำหนักลงที่จุดเดียวของฝ่าเท้ามากเกินไปทุกก้าว ผิวบริเวณนั้นต้องรับแรงมากกว่าปกติ และอาจเกิดแผลได้ โดยเฉพาะเมื่อเท้ารู้สึกได้น้อยลง" · ควรทำ / Home advice "ลองเดินช้าลงให้น้ำหนักลงทั้งฝ่าเท้า หรือนั่งพักสักครู่" (replaces the board's standing advice "ลองยืนให้น้ำหนักลงทั้งฝ่าเท้า หรือเปลี่ยนท่ายืน": the rule now counts walking steps) |
| `BATTERY_LOW` (S7, draft) | Title "แบตเตอรี่แผ่นรองเท้า{ข้าง}เหลือน้อย" · detail "แบตเตอรี่เหลือ {n}% ถ้าแบตเตอรี่หมด แอปจะบอกไม่ได้ว่าเท้า{ข้าง}ปลอดภัยหรือไม่" · steps "ชาร์จแบตเตอรี่ก่อนใช้ครั้งต่อไป" / "ถ้าต้องใช้ต่อ วางโทรศัพท์ไว้ใกล้ ๆ และดูว่ายังเชื่อมต่ออยู่" · why "แอปต้องได้รับข้อมูลจากแผ่นรองเท้าทั้งสองข้าง จึงจะเทียบน้ำหนักและความอุ่นของเท้าได้" |
| `DEVICE_LOST` (S7, draft) | Title "แผ่นรองเท้า{ข้าง}หลุดการเชื่อมต่อ" · detail "ขาดการเชื่อมต่อนานกว่า 5 นาที ระหว่างนี้แอปยังบอกไม่ได้ว่าเท้า{ข้าง}ปลอดภัยหรือไม่" · steps "ตรวจว่าสวิตช์ที่กล่องอุปกรณ์เปิดอยู่" / "วางโทรศัพท์ไว้ใกล้ ๆ" / "กด \"เชื่อมต่ออีกครั้ง\" ด้านล่าง" · why as `BATTERY_LOW` |
| `PRESSURE_WATCH` (S7, draft; level 2, stored, never listed) | Title "{ส่วนเท้า}{ข้าง}รับน้ำหนักค่อนข้างมาก" · detail "{จุด}{ข้าง}รับแรงกดสูงกว่าปกติ" · step / ควรทำ "ลองขยับเท้า หรือเปลี่ยนท่า" · why "แอปเฝ้าดูจุดที่รับแรงกดสูง เพื่อเตือนก่อนที่แรงกดจะสูงจนเสี่ยงเกิดแผล" |
| `ASYMMETRY_PEAK` (S7, draft; level 2, never listed; Home's orange balance note) | Title / balance note "ลงน้ำหนักเท้า{ข้าง}มากกว่า" · detail "ตอนเดิน เท้า{ข้าง}รับแรงกดสูงกว่าเท้า{อีกข้าง}ติดต่อกันหลายก้าว" · step / ควรทำ "ลองเดินช้าลง และลงน้ำหนักให้เท่ากันทั้งสองข้าง" · why "เมื่อเท้าข้างหนึ่งรับแรงมากกว่าอีกข้างต่อเนื่อง เท้าข้างนั้นมีโอกาสเกิดแผลมากขึ้น" |
| Home, No data with one foot connected (S7, draft) | "ยังไม่ได้เชื่อมต่อแผ่นรองเท้า{ขวา} จึงยังบอกไม่ได้ว่าเท้า{ขวา}ปลอดภัยหรือไม่" |
| Alert detail rows (S6B, draft; not health advice but shown to patients) | PTI: "{v} kPa·s เฉลี่ยต่อก้าว ที่{จุด}{ข้าง}" · "{t} kPa·s เฉลี่ยต่อก้าว ขณะเดิน" · "จำนวนก้าวที่ใช้" "{n} ก้าว ใน {m} นาทีล่าสุด". LOAD_CONCENTRATION: "{v}% ของแรงกดทั้งฝ่าเท้า ที่{จุด}{ข้าง}" · "{t}% ติดกัน {n} ก้าว" · "{n} ก้าวติดกัน". Foot-map label of a pressure alert's foot: "เท้า{ข้าง} {จุด}รับน้ำหนักมาก" |
| My feet (S6B part 2, draft; §8.4) | Pressure, one foot missing: "ยังไม่ได้รับข้อมูลเท้า{ข้าง}" · "ต้องเชื่อมต่อแผ่นรองเท้า{ข้าง}ก่อน". Temperature: "เทียบความอุ่นไม่ได้" · "ตอนนี้แผ่นรองเท้ายังวัดความอุ่นไม่ได้" · "เท้า{ข้าง}ยังไม่ได้เชื่อมต่อ" · "รอผลการวัด" · site note "ยังวัดไม่ได้" · chart "ยังไม่มีข้อมูลวันนี้" · gap label "ขาดข้อมูล / ตั้งแต่ HH:mm" (open) and "ขาดข้อมูล / HH:mm–HH:mm" (ended) · chart summary (§8.4) · quality "สัมผัสไม่ดี" / "เซนเซอร์ผิดปกติ" / "เท้า{ข้าง} ยังวัดไม่ได้" · details "ยังไม่ได้เชื่อมต่อ" |
| Gait notes | DATA-CONTRACT §8.3.1 (5 texts, owned by the contract) |
| Gait tab (S8A, draft; §8.5) | Class descriptions: "เดินกะเผลก" "ลงน้ำหนักข้างหนึ่งสั้นกว่าอีกข้าง" · "เดินลงส้นเท้า" "น้ำหนักลงที่ส้นเท้า ปลายเท้าแตะพื้นน้อย" · "เดินบิดปลายเท้า" "ปลายเท้าหันเข้าด้านในหรือออกด้านนอกขณะเดิน". Model below `minConfidence`: "ประเมินด้วยกฎพื้นฐาน เพราะโมเดล AI ยังไม่มั่นใจพอ" · details "กฎพื้นฐาน (โมเดล AI ยังไม่มั่นใจพอ)". No data: "ยังไม่มีข้อมูล" · "ต้องเชื่อมต่อแผ่นรองเท้าทั้งสองข้างก่อน". PTI asymmetry detail "{n}% (ค่าอ้างอิง {asymmetry.ptiPct}% · ยังไม่ใช้แจ้งเตือน)" |
| Daily foot check | Reason "แผ่นรองเท้าวัดได้เฉพาะใต้ฝ่าเท้า การดูเท้าทุกวันช่วยให้เห็นแผลที่ปลายนิ้วหรือหลังเท้า ซึ่งอาจเกิดขึ้นโดยไม่รู้สึกตัว" · the 3 questions (§11.3) · note "แอปไม่ได้ตรวจรูปให้ ถ้าเห็นอะไรผิดปกติหรือไม่แน่ใจ ให้ตอบว่า \"มี / ไม่แน่ใจ\"" |
| Something found | Steps "ล้างเท้าด้วยน้ำสะอาด แล้วซับให้แห้ง" / "ถ้ามีแผล ปิดด้วยผ้าก๊อซสะอาด" / "เดินให้น้อยลง และอย่าเดินเท้าเปล่า" / "ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู" · urgent "ไปโรงพยาบาลทันที ถ้ามีไข้ เท้าบวมแดงลามออกไป มีหนอง หรือมีกลิ่น" |
| Saved | "เมื่อวานพบสิ่งที่ควรให้แพทย์ดู ถ้ายังไม่ได้ไป ควรไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน" |
| Disclaimers | "คำแนะนำนี้ไม่ใช่การวินิจฉัยโรค ถ้าไม่แน่ใจ ให้ปรึกษาแพทย์หรือพยาบาล" · "แอปนี้ช่วยดูแลเท้า ไม่ใช่เครื่องมือวินิจฉัยโรค ถ้ามีแผลหรืออาการผิดปกติ ให้ไปพบแพทย์" · gait: "ค่าประมาณ ไม่ใช่การวินิจฉัย" · "ท่าเดินใช้ประกอบคำแนะนำเท่านั้น ไม่ได้ใช้ตัดสินว่าเท้าปลอดภัยหรือไม่" |

## Appendix B — Board index ("SmartInsole App Design" canvas)

| Section | Boards |
|---|---|
| §6 Home | HomeD (Safe), HomeDWatch (Be careful), HomeDRest (Rest your feet), HomeDNoData (No data), HomeDMotion (motion) |
| §7 Alerts | AlertsD (list), AlertsDEmpty (empty), AlertsDMotion (new alert arrives), AlertDetailD (`TEMP_DELTA`), AlertDetailDPressure (`PRESSURE_PEAK`, numbers open), AlertDetailDDevice (`DEVICE_LOST`) |
| §8 My feet | FeetD (pressure, Safe), FeetDPressureWatch (pressure, Be careful, numbers open), FeetDNoData (pressure, no data), FeetDTemp (temperature, close), FeetDTempRest (temperature, Rest your feet, numbers open), FeetDTempMissing (temperature, right foot missing), FeetDGait (gait, normal, rule-based), FeetDGaitToe (gait, toe walking, model, numbers open), FeetDGaitIdle (gait, not walking), FeetDMotion (motion) |
| §9 Connection | ConnectD (searching), ConnectDDone (both connected), ConnectDWrong (wrong side), ConnectDBtOff (Bluetooth off), ConnectDNotFound (not found + connected without data), ConnectDMotion (motion) |
| §10 Settings | SettingsD (main), SettingsDResearch (researcher), SettingsDTare (TARE sheet) |
| §11 Daily foot check | CheckD (start), CheckDCapture (capture), CheckDReview (compare and answer), CheckDFound (something found), CheckDSaved (saved), CheckDMotion (motion) |
| History only | Main, HomeWatch, HomeRest, HomeNoData, CheckStart, CheckCapture, CheckReview, CheckResult (v1); RedesignA, RedesignB, RedesignC (directions); superseded by style D |
