# DESIGN-SPEC — SmartInsole App (Flutter)

> v1 · 2026-10-17 · Source: mockups on the "SmartInsole App Design" canvas (claude.ai)
> Status: Home ✅ · Daily foot check ✅ · Gait / Temperature / Alerts / Connection / Settings ⏳ (next version)
> Primary user: people with diabetes, possibly poor eyesight, not tech-savvy → large, clear, simple, friendly.
> Thai text in quotes is the exact UI copy to use. Everything else in this file is English.

---

## 1. Colour tokens

| Token | Hex | Use |
|---|---|---|
| `bg` | `#F2F7F8` | Page background |
| `surface` | `#FFFFFF` | Cards |
| `ink` | `#12303A` | Primary text |
| `inkMuted` | `#4A626B` | Secondary text |
| `inkSoft` | `#33505A` | Long body text |
| `primary` | `#0A6A87` | Primary buttons, links, selected tab |
| `primarySoft` | `#DDF0F4` | Selected-tab pill, step numbers |
| `info` | `#E6F2F5` | Tip boxes |
| `border` | `#DCE6E9` | Borders / dividers |
| `outlineBtn` | `#9FC3CE` | Secondary button outline |

### Status colours (always icon + text + colour; never colour alone)

| Status | Background | Text | Icon colour | Icon (Lucide name) |
|---|---|---|---|---|
| Safe | `#E2F2E8` | `#1B5536` | `#2E7D4F` | `circle-check` |
| Be careful | `#FFF0D2` | `#5E3E00` | `#A86A00` | `triangle-alert` |
| Rest your feet | `#FBE3DF` | `#7F1D12` | `#B42318` | `octagon-alert` |
| No data | `#E9EEF0` | `#33444B` | `#55666E` | `bluetooth-off` |

### Foot-map pressure dots (differ in both hue and lightness)

| Level | Hex |
|---|---|
| Low | `#BFE2EB` |
| Medium | `#F0B340` |
| High | `#C2410C` |
| No data | `#D3DDE1` |

kPa boundaries come from `thresholds.json`; never hardcode them.

### Camera screen (foot check)
Background `#0F1D22` · viewfinder `#22353B` · dashed guide outline `#7FD3E3` · secondary text `#C9DCE1`

---

## 2. Typography

- **Body:** IBM Plex Sans Thai **Looped** (looped Thai letterforms read better for older users) 400/500/600/700
- **Headings and big numbers:** IBM Plex Sans Thai 500/600/700
- **Bundled** in `assets/fonts/`; never downloaded at runtime

| Use | Size | Weight | Family |
|---|---|---|---|
| Status title | 28 | 700 | Plex Sans Thai |
| Screen title / greeting | 22–26 | 700 | Plex Sans Thai |
| Card numbers | 24 | 700 | Plex Sans Thai |
| Card title | 19 | 600 | Plex Sans Thai |
| Main body | 17–18 | 400–600 | Looped |
| Secondary / tab labels | 15–16 | 500 | Looped |
| Smallest | 14 | 400 | Looped |

Line height 1.4–1.55 · must support larger text from app settings and system settings without breaking layout.

---

## 3. Size, spacing, radius

- Reference screen 390 × 844
- Page padding 20 · gap between cards 14 · card padding 16–20
- Radius: large card 24 · small card 20 · tip box 14–18 · full-width buttons = pill (half height)
- **Minimum touch target 48 × 48** · primary button height 56 · secondary 52 · answer choice 44
- Shadow only on floating buttons: `0 1px 3px rgba(18,48,58,0.12)`; cards have no shadow

---

## 4. App structure

- **Bottom bar, 4 tabs** (height 80): Home (`house`), Gait (`footprints`), Temperature (`thermometer`), Alerts (`bell` + red count badge `#B42318`). Thai labels: "หน้าหลัก", "การเดิน", "อุณหภูมิ", "แจ้งเตือน".
  - Selected tab: icon in a 56×30 pill with `primarySoft` background; label `primary`, weight 700
- **Settings:** 48×48 gear button, top right of Home (label for screen readers: "ตั้งค่า")
- **Device connection:** tap the left/right foot buttons on Home
- **Daily foot check:** Home card (section 5, item 4) + in-app evening reminder
- No fake status bar

---

## 5. Home

Top to bottom:
1. **Header:** date (16, `inkMuted`) + "สวัสดี คุณ[name]" (26/700) + settings button
2. **Left/right foot buttons** (2-column grid, height 48): status dot (green `#2E7D4F` = connected, grey `#8A9AA1` = not connected) + "เท้าซ้าย" / "เท้าขวา" + "แบต xx%" or "ไม่ได้เชื่อมต่อ" · low battery → orange battery label
3. **Status card** (status colours): icon in a 56 white circle + title 28 + detail 18 + advice box (only when not Safe) + button "เชื่อมต่อแผ่นรองเท้า" (only when No data)
4. **Foot-check card** (only while today's check is not done; whole card tappable): camera icon in a 44 `primarySoft` circle + "วันนี้ยังไม่ได้ดูเท้า" (17/600) + "ถ่ายรูปและตอบคำถาม ใช้เวลา 1 นาที" (15, `inkMuted`) + chevron · border `outlineBtn` 1.5, radius 20
5. **Card "น้ำหนักที่เท้ารับอยู่ตอนนี้"** + link "ดูเพิ่ม": left and right foot (top view, big toe on the inner side), dots placed from `sensor_layout.json`, legend "น้อย" / "ปานกลาง" / "มาก"
6. **Two small cards:** "ความอุ่นของเท้า" (difference x.x° + explanation) · "การลงน้ำหนัก" (left : right + explanation) · no data → "—" + "ต้องเชื่อมต่อทั้งสองข้าง"

The page scrolls; the bottom bar stays fixed.

### Copy per status

| Status | Title | Detail (example) | Advice |
|---|---|---|---|
| Safe | "ตอนนี้เท้าปลอดภัย" | "น้ำหนักและความอุ่นของเท้าทั้งสองข้างอยู่ในเกณฑ์ปกติ" | — |
| Be careful | "ควรระวัง" | "ปลายเท้าซ้ายรับน้ำหนักมากต่อเนื่องนานเกินไป" | "ลองขยับเท้า เปลี่ยนท่ายืน หรือนั่งพักสักครู่" |
| Rest your feet | "ควรพักเท้าตอนนี้" | "เท้าขวาอุ่นกว่าเท้าซ้าย 2.6 องศา ติดต่อกันมาสักพัก" | "นั่งพักเท้า แล้วตรวจดูว่ามีรอยแดงหรือแผลไหม ถ้าพรุ่งนี้ยังเป็นอยู่ ควรไปพบแพทย์" |
| No data | "ยังไม่ได้รับข้อมูล" | "ยังไม่ได้เชื่อมต่อแผ่นรองเท้า จึงยังบอกไม่ได้ว่าเท้าปลอดภัยหรือไม่" | (connect button) |

The real detail text is generated from the rule that caused the status (alert code + foot side + zone) in plain Thai. Never show kPa / ΔT / PAI on Home.

---

## 6. Daily foot check

| Screen | Content |
|---|---|
| **Start** | Title "ตรวจเท้าประจำวัน" + card "ใช้เวลาประมาณ 1 นาที" + reason ("แผ่นรองเท้าวัดได้เฉพาะใต้ฝ่าเท้า การดูเท้าทุกวันช่วยให้เห็นแผลที่ปลายนิ้วหรือหลังเท้า ซึ่งอาจเกิดขึ้นโดยไม่รู้สึกตัว") · steps 1–3 ("ถ่ายรูปเท้า 4 ภาพ ฝ่าเท้าและหลังเท้าทั้งสองข้าง", "ดูรูปวันนี้เทียบกับเมื่อวาน", "ตอบคำถามสั้น ๆ 3 ข้อ") · tip box ("มองฝ่าเท้าไม่ถนัด วางโทรศัพท์บนพื้นแล้วใช้ปุ่มตั้งเวลา หรือให้ญาติช่วยถ่ายก็ได้") · "รูปเก็บไว้ในโทรศัพท์เครื่องนี้เท่านั้น" · primary button "เริ่มถ่ายรูป" + secondary "ไม่ถ่ายรูป ตอบคำถามอย่างเดียว" |
| **Capture** | Dark background · "ภาพที่ n จาก 4" · large view name in order "ฝ่าเท้าซ้าย" → "ฝ่าเท้าขวา" → "หลังเท้าซ้าย" → "หลังเท้าขวา" · hint "ให้เท้าอยู่ในกรอบ และมีแสงสว่างพอ" · viewfinder with dashed foot outline · 4 progress dots · buttons "ตั้งเวลา 3 วิ" / 80 px shutter / "ข้ามภาพนี้" |
| **Compare & answer** | Title "เทียบกับเมื่อวาน" · tabs "ฝ่าซ้าย" / "ฝ่าขวา" / "หลังซ้าย" / "หลังขวา" · yesterday vs today (today has a `primary` border) · 3 questions: "เห็นรอยแดง หรือผิวเปลี่ยนสีไหม", "เห็นแผล รอยถลอก หรือตุ่มพองไหม", "เท้าบวม หรือผิดรูปไปจากเดิมไหม" · choices "ไม่มี" / "มี / ไม่แน่ใจ" (orange when selected) · note "แอปไม่ได้ตรวจรูปให้ ถ้าเห็นอะไรผิดปกติหรือไม่แน่ใจ ให้ตอบว่า \"มี / ไม่แน่ใจ\"" · button "บันทึก" |
| **Something found** | Orange card "พบสิ่งที่ควรให้แพทย์ดู" + what the user reported · "สิ่งที่ควรทำตอนนี้": "ล้างเท้าด้วยน้ำสะอาด แล้วซับให้แห้ง", "ถ้ามีแผล ปิดด้วยผ้าก๊อซสะอาด", "เดินให้น้อยลง และอย่าเดินเท้าเปล่า", "ไปพบแพทย์หรือพยาบาลภายใน 1–2 วัน และนำรูปที่ถ่ายไว้ไปให้ดู" · red box "ไปโรงพยาบาลทันที ถ้ามีไข้ เท้าบวมแดงลามออกไป มีหนอง หรือมีกลิ่น" · buttons "ดูรูปที่บันทึกไว้" / "เข้าใจแล้ว กลับหน้าหลัก" |

All answers "ไม่มี" → short confirmation "บันทึกแล้ว เจอกันพรุ่งนี้" (never say the foot is normal).
⚠️ Medical advice text must be reviewed by a medical expert before real use.

---

## 7. Motion

See FLUTTER-PLAN section 8 · default durations: short 200 ms, medium 300 ms, long 400 ms · curves `easeOutCubic` (enter) / `easeInCubic` (exit) · "high" dot pulse ~1.6 s per cycle · all disabled under reduce motion.

---

## 8. Accessibility

- Text contrast ≥ 4.5:1 (≥ 3:1 for 24 px and larger)
- Every icon-only button has a TalkBack label (e.g. "ตั้งค่า", "กลับ", "ถ่ายรูป")
- Foot maps have a TalkBack description, e.g. "เท้าซ้าย ปลายเท้ารับน้ำหนักมาก"
- Colours that must be told apart differ in both hue and lightness
