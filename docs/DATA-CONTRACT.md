# Data Contract v1.1

**STATUS: PLACEHOLDER — NOT YET FILLED IN.**

This file is a placeholder. The actual Data Contract v1.1 has not been pasted in
yet. Every threshold, type shape, channel order, and packet format currently
implemented in this codebase (`src/ts/constants.ts`, `src/ts/data/types.ts`,
`src/ts/data/*.ts`) was derived from that document during earlier sessions, but
the document itself has never lived in this repo — it existed only outside it,
referenced by name.

**Do not invent, reconstruct, or infer the contract's contents from the code.**
The code is downstream of the contract, not the other way around; if they ever
disagree, the contract wins and the code is what's wrong. Treat any threshold or
shape you find in `constants.ts` or `data/types.ts` as "what a past session
believed the contract said," not as a substitute for reading the contract
itself.

## To fill this in

Replace this entire file with the pasted contract text. Once that's done:

1. Re-check every constant in `src/ts/constants.ts` against it — the pressure
   tiers (`PRESSURE_WATCH_KPA`, `PRESSURE_ALERT_KPA`), `TEMP_DELTA_THRESHOLD`,
   and `FSR_CHANNEL_ORDER` were all typed from a remembered version of this
   contract and may not match v1.1 exactly.
2. Re-check `src/ts/data/types.ts` — `SensorSample`, `TempReading`,
   `DeviceStatus` — field names, types, and units against the contract's wire
   format.
3. Confirm the 30-minute per-code alert repeat-suppression window
   (`src/ts/data/AlertStore.ts`) and the packet/MTU details referenced in
   `docs/PROGRESS.md` still match.
# SmartInsole — Data Contract v1.0

**เอกสารสัญญาข้อมูลกลาง** สำหรับทีมฮาร์ดแวร์ (ESP32), ทีมแอปพลิเคชัน (React Native) และทีมปัญญาประดิษฐ์

| | |
|---|---|
| เวอร์ชัน | 1.1 |
| สถานะ | ร่างเพื่อพิจารณา — ต้องได้รับการยืนยันจากทั้ง 3 ทีมก่อนเริ่มพัฒนา |
| ขอบเขต | นิยาม BLE protocol, หน่วยวัด, โครงสร้างข้อมูล, และ interface ของโมเดล |

> **หลักการ:** เอกสารนี้คือจุดเดียวที่กำหนดว่าข้อมูลหน้าตาเป็นอย่างไร ทุกทีมพัฒนาแยกกันได้โดยยึดเอกสารนี้เป็นข้อตกลง หากต้องการเปลี่ยนแปลง ต้องแก้ที่เอกสารนี้ก่อนและแจ้งทุกทีม พร้อมเพิ่มเลขเวอร์ชัน

---

## 1. ภาพรวมสถาปัตยกรรมข้อมูล

```
┌─────────────────┐         ┌─────────────────┐
│  Insole ซ้าย     │         │  Insole ขวา      │
│  ESP32-C3       │         │  ESP32-C3       │
│  FSR×6, IMU×1   │         │  FSR×6, IMU×1   │
│  NTC×2          │         │  NTC×2          │
└────────┬────────┘         └────────┬────────┘
         │                           │
         └────────── BLE ────────────┘
                      │
              ┌───────▼────────┐
              │  Mobile App    │
              │  (React Native)│
              │  ┌──────────┐  │
              │  │ SQLite   │  │  ← ข้อมูลดิบ + ประวัติ
              │  └──────────┘  │
              │  ┌──────────┐  │
              │  │ TFLite   │  │  ← จำแนกท่าเดิน
              │  └──────────┘  │
              └───────┬────────┘
                      │ HTTPS (สรุป + alert เท่านั้น)
              ┌───────▼────────┐
              │   Firebase     │
              └────────────────┘
```

**กฎสำคัญ:** ข้อมูลไหลทางเดียวเสมอ `Insole → App → Cloud` — แผ่นรองเท้าไม่ติดต่อ Firebase โดยตรงในเฟสแรก

---

## 2. BLE Specification

### 2.1 การประกาศตัว (Advertising)

| รายการ | ค่า |
|---|---|
| Device Name (ซ้าย) | `SMARTINSOLE-L` |
| Device Name (ขวา) | `SMARTINSOLE-R` |
| Advertising Interval | 100 ms (ขณะยังไม่เชื่อมต่อ) |
| TX Power | 0 dBm |

แอปใช้ **Service UUID** ในการ filter การสแกน ไม่ใช้ชื่ออุปกรณ์ (ชื่ออาจถูกระบบปฏิบัติการ cache ไว้ผิดพลาดได้)

### 2.2 GATT Service & Characteristics

**Service UUID:** `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900`

| Characteristic | UUID (ต่อท้าย) | Properties | ความถี่ | ขนาด |
|---|---|---|---|---|
| Sensor Stream | `...b45901` | Notify | 6.25 Hz | 200 bytes |
| Temperature | `...b45902` | Notify | 1/30 Hz | 12 bytes |
| Device Status | `...b45903` | Read, Notify | เมื่อเปลี่ยนแปลง | 8 bytes |
| Control | `...b45904` | Write | ตามคำสั่ง | 1–16 bytes |
| Calibration | `...b45905` | Read | ครั้งเดียวตอน connect | สูงสุด 512 bytes |

### 2.3 การตั้งค่าการเชื่อมต่อ

| พารามิเตอร์ | ค่าที่ต้องการ | ค่าสำรอง |
|---|---|---|
| MTU | 247 bytes | หากเจรจาไม่สำเร็จ → ลดเหลือ 4 samples/packet |
| Connection Interval | 15–30 ms | — |
| Slave Latency | 0 | — |
| Supervision Timeout | 4000 ms | — |

> **หมายเหตุสำหรับทีมแอป:** Android ต้องเรียก `requestMTU(247)` หลัง connect สำเร็จ **ก่อน** เปิด notification ส่วน iOS จัดการเองอัตโนมัติ

---

## 3. รูปแบบแพ็กเก็ต (Packet Format)

ทุกค่าเป็น **little-endian**

### 3.1 Sensor Stream Packet (200 bytes)

รวม 8 samples ต่อ 1 packet → ส่ง 6.25 ครั้ง/วินาที (ได้อัตราสุ่มจริง 50 Hz)

**Header (8 bytes)**

| Offset | ขนาด | ชนิด | ฟิลด์ | คำอธิบาย |
|---|---|---|---|---|
| 0 | 2 | uint16 | `seq` | ลำดับ packet วนกลับที่ 0 เมื่อครบ 65535 ใช้ตรวจจับ packet หาย |
| 2 | 4 | uint32 | `t0_ms` | เวลาของ sample แรกในหน่วย ms นับจาก boot |
| 6 | 1 | uint8 | `count` | จำนวน sample ในแพ็กเก็ตนี้ (ปกติ = 8) |
| 7 | 1 | uint8 | `flags` | bit0 = ข้อมูลอิ่มตัว (saturated), bit1 = อยู่ระหว่าง calibration |

**Sample Block (24 bytes × 8)**

| Offset | ขนาด | ชนิด | ฟิลด์ | หน่วย |
|---|---|---|---|---|
| +0 | 12 | uint16 × 6 | `fsr[0..5]` | ADC raw 0–4095 |
| +12 | 6 | int16 × 3 | `accel[x,y,z]` | 4096 LSB/g |
| +18 | 6 | int16 × 3 | `gyro[x,y,z]` | 32.8 LSB/(°/s) |

ระยะห่างระหว่าง sample = 20 ms คงที่ → เวลาของ sample ที่ `i` คือ `t0_ms + (i × 20)`

**ตำแหน่ง FSR (index ต้องตรงกันทั้งซ้ายและขวา)**

| Index | ตำแหน่ง | ชื่ออังกฤษ |
|---|---|---|
| 0 | นิ้วหัวแม่เท้า | Hallux |
| 1 | เนินปลายเท้าที่ 1 | 1st Metatarsal Head |
| 2 | เนินปลายเท้าที่ 3 | 3rd Metatarsal Head |
| 3 | เนินปลายเท้าที่ 5 | 5th Metatarsal Head |
| 4 | กลางเท้า | Midfoot / Lateral Arch |
| 5 | ส้นเท้า | Heel |

### 3.2 Temperature Packet (12 bytes)

| Offset | ขนาด | ชนิด | ฟิลด์ | หน่วย |
|---|---|---|---|---|
| 0 | 2 | uint16 | `seq` | — |
| 2 | 4 | uint32 | `t_ms` | ms จาก boot |
| 6 | 2 | int16 | `temp_forefoot` | 0.01 °C (เช่น 3180 = 31.80°C) |
| 8 | 2 | int16 | `temp_heel` | 0.01 °C |
| 10 | 1 | uint8 | `quality` | 0 = ปกติ, 1 = สัมผัสไม่ดี, 2 = เซนเซอร์ผิดพลาด |
| 11 | 1 | uint8 | `reserved` | สำรองไว้ = 0 |

> ค่า `-32768` หมายถึงอ่านค่าไม่ได้ แอปต้องแสดงเป็น "ไม่มีข้อมูล" ไม่ใช่ตัวเลข

### 3.3 Device Status Packet (8 bytes)

| Offset | ขนาด | ชนิด | ฟิลด์ | คำอธิบาย |
|---|---|---|---|---|
| 0 | 1 | uint8 | `battery_pct` | 0–100 |
| 1 | 2 | uint16 | `battery_mv` | แรงดันจริง (mV) |
| 3 | 1 | uint8 | `foot_side` | 0 = ซ้าย, 1 = ขวา |
| 4 | 1 | uint8 | `fw_major` | เวอร์ชัน firmware |
| 5 | 1 | uint8 | `fw_minor` | — |
| 6 | 1 | uint8 | `state` | 0 = idle, 1 = streaming, 2 = error |
| 7 | 1 | uint8 | `error_code` | 0 = ไม่มี, ดูภาคผนวก A |

### 3.4 Control Commands (App → Insole)

| Opcode | ชื่อ | Payload | คำอธิบาย |
|---|---|---|---|
| `0x01` | START_STREAM | — | เริ่มส่งข้อมูล |
| `0x02` | STOP_STREAM | — | หยุดส่ง (เข้าโหมดประหยัดไฟ) |
| `0x03` | SYNC_TIME | uint64 (unix ms) | ตั้งเวลาอ้างอิงจากมือถือ |
| `0x04` | SET_RATE | uint8 (Hz) | เปลี่ยนอัตราสุ่ม (สำหรับทดสอบ) |
| `0x05` | TARE | — | ปรับ zero-point ของ FSR |
| `0x06` | REBOOT | — | รีสตาร์ต |

---

## 4. การซิงโครไนซ์เวลาระหว่างเท้าสองข้าง

**ปัญหา:** ESP32 สองตัวมีนาฬิกาแยกกัน ค่า `t_ms` ของแต่ละข้างเริ่มนับคนละจุด หากนำมาเทียบตรงๆ การคำนวณ symmetry และ CoP จะผิด

**วิธีแก้:**

1. เมื่อแอปเชื่อมต่อสำเร็จ ให้ส่ง `SYNC_TIME` พร้อม unix timestamp ปัจจุบันไปทั้งสองข้าง
2. แอปบันทึก `offset = unix_time_ณ_ขณะส่ง − t_ms_ล่าสุดที่ได้รับ` แยกของแต่ละข้าง
3. ทุก sample แปลงเป็น unix time ด้วย `t_unix = t_ms + offset`
4. ทำซ้ำทุก 5 นาที เพื่อชดเชย clock drift

**เกณฑ์ยอมรับ:** ความคลาดเคลื่อนระหว่างสองข้างต้องไม่เกิน **±10 ms** (ครึ่งหนึ่งของช่วง sample)

---

## 5. การแปลงหน่วย (Calibration)

### 5.1 FSR: ADC → kPa

**ข้อตกลง: ESP32 ส่ง raw ADC — แอปเป็นผู้คำนวณ — แต่ตาราง calibration เก็บไว้ในตัวแผ่นรองเท้า**

| องค์ประกอบ | อยู่ที่ไหน | เหตุผล |
|---|---|---|
| ข้อมูล ADC ดิบ | ส่งผ่าน BLE | เป็น source of truth เก็บไว้ re-calibrate ย้อนหลังได้ |
| ตาราง calibration | NVS ของ ESP32 | แผ่นรองเท้าพก identity ของตัวเองไปด้วย ใช้กับมือถือเครื่องใดก็ได้ |
| สูตรคำนวณ | โค้ดแอป | แก้ไขสูตรได้โดยไม่ต้อง flash firmware ใหม่ |

การออกแบบนี้แก้ปัญหาสำคัญ — หากผู้ป่วยมีแผ่นรองเท้าหลายคู่ หรือเปลี่ยนคู่ใหม่ แอปจะอ่านค่า calibration ที่ถูกต้องได้เองอัตโนมัติจาก characteristic `...b45905` ตอนเชื่อมต่อ ไม่ต้องให้ผู้ใช้ตั้งค่าเอง

```
V_out = (adc / 4095) × 3.3
R_fsr = R_pulldown × (3.3 − V_out) / V_out
F_newton = a × R_fsr^b        // a, b จาก curve fitting รายชิ้น
P_kPa = F_newton / A_sensor   // A_sensor = พื้นที่รับแรงจริง (m²)
```

ทีมฮาร์ดแวร์ต้องส่งมอบ **ตาราง calibration** ในรูปแบบ JSON:

```json
{
  "device_id": "INSOLE-L-001",
  "r_pulldown_ohm": 10000,
  "sensor_area_m2": 0.000113,
  "channels": [
    { "index": 0, "a": 1.23e5, "b": -1.05, "offset_adc": 12 }
  ]
}
```

### 5.2 IMU

```
accel_g   = raw / 4096.0
gyro_dps  = raw / 32.8
```

### 5.3 อุณหภูมิ

```
temp_c = raw / 100.0
```

ESP32 แปลงจาก Steinhart-Hart ให้เรียบร้อยแล้ว เนื่องจากค่าคงที่ของ NTC ไม่ต้องปรับรายชิ้น

---

## 6. โครงสร้างข้อมูลภายในแอป (TypeScript)

```typescript
type FootSide = 'L' | 'R';

interface SensorSample {
  tUnixMs: number;
  side: FootSide;
  fsrKpa: number[];      // 6 ค่า, หน่วย kPa
  accelG: [number, number, number];
  gyroDps: [number, number, number];
}

interface TempReading {
  tUnixMs: number;
  side: FootSide;
  forefootC: number | null;
  heelC: number | null;
  quality: 0 | 1 | 2;
}

interface DeviceStatus {
  side: FootSide;
  batteryPct: number;
  connected: boolean;
  firmware: string;
  errorCode: number;
}

// ผลลัพธ์การประเมิน (มาจาก RuleBasedEngine หรือ TFLiteEngine)
interface RiskAssessment {
  tUnixMs: number;
  statusLevel: 1 | 2 | 3 | 4 | 5;
  gaitClass: GaitClass;
  confidence: number;          // 0.0–1.0
  deltaTForefoot: number | null;
  deltaTHeel: number | null;
  peakKpa: { L: number; R: number };
  ptiKpaS: { L: number; R: number };
  peakAsymmetryPct: number;    // PAI — ดูข้อ 8.2
  ptiAsymmetryPct: number;
  loadConcentrationPct: { L: number; R: number };
  symmetryScore: number;       // 0–100
  highRiskZones: RiskZone[];
  source: 'rule' | 'model';    // สำคัญ: ใช้เทียบ baseline กับ AI
}

interface RiskZone {
  side: FootSide;
  sensorIndex: number;
  labelTh: string;
  valueKpa: number;
}

type GaitClass =
  | 'normal'
  | 'minor_asymmetry'
  | 'high_pressure'
  | 'abnormal_gait'
  | 'critical';
```

**หลักการออกแบบสำคัญ** — UI ต้องอ่านค่าจาก interface เหล่านี้เท่านั้น ห้ามอ่านจาก BLE โดยตรง เพื่อให้สลับระหว่าง Mock / Simulator / Real ได้โดยไม่แก้ UI

```typescript
interface IDataSource {
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  onSample(cb: (s: SensorSample) => void): void;
  onTemp(cb: (t: TempReading) => void): void;
  onStatus(cb: (d: DeviceStatus) => void): void;
}
// implements: MockDataSource | SimulatorDataSource | BleDataSource
```

---

## 7. Interface ของโมเดลปัญญาประดิษฐ์

ระบบใช้โมเดล **2 ตัวทำงานต่อเนื่องกัน** ที่คนละระดับเวลา (Multi-Timescale) เพื่อแก้ปัญหาที่อัตราสุ่มของข้อมูลกลไก (50 Hz) กับอุณหภูมิ (1/30 Hz) ต่างกันประมาณ 1,500 เท่า จนไม่สามารถรวมไว้ในหน้าต่างเวลาเดียวกันได้

| | **Model A** — Gait Classifier | **Model B** — Risk Fusion |
|---|---|---|
| หน้าที่ | จำแนกรูปแบบการเดิน | ประเมินระดับความเสี่ยงรวม |
| สถาปัตยกรรม | CNN-LSTM (Single-Branch) | Dual-Branch Intermediate Fusion |
| Input | 24 channels จาก FSR + IMU | Embedding จาก A + อุณหภูมิ + ตัวชี้วัดสมมาตร |
| Window | 2 วินาที | 5 นาที |
| ความถี่ทำนาย | 1 Hz | ทุก 5 นาที |
| Output | Gait class (5 คลาส) | Status Level 1–5 |

> Model B คือส่วนที่ทำให้โครงงานนี้มี **Sensor Fusion แบบกิ่งคู่** ตามที่ระบุไว้ในตารางเปรียบเทียบกับงานวิจัยอื่น กิ่งหนึ่งรับข้อมูลกลไกความถี่สูง อีกกิ่งรับข้อมูลอุณหภูมิความถี่ต่ำ แล้วรวมกันที่ชั้นกลางก่อนตัดสินใจ

---

### 7.1 Model A — Input

| รายการ | ค่า |
|---|---|
| Shape | `[1, 100, 24]` |
| Window | 100 timesteps = 2 วินาที @ 50 Hz |
| Stride | 50 timesteps (overlap 50%) → ทำนายทุก 1 วินาที |
| Channels | 24 = (6 FSR + 3 accel + 3 gyro) × 2 ข้าง |
| Normalization | z-score ต่อ channel ด้วย mean/std จากชุด training |
| dtype | float32 |

**ลำดับ channel (ห้ามสลับ)**

```
 0– 5 : FSR ซ้าย  index 0–5
 6– 8 : Accel ซ้าย x,y,z
 9–11 : Gyro ซ้าย  x,y,z
12–17 : FSR ขวา   index 0–5
18–20 : Accel ขวา x,y,z
21–23 : Gyro ขวา  x,y,z
```

> ทีม AI ต้องส่งมอบไฟล์ `normalization.json` ที่มี mean/std ของทั้ง 24 channels มาพร้อมกับโมเดล มิฉะนั้นแอปจะ normalize ไม่ตรงกับตอนเทรน และผลจะเพี้ยนทั้งหมด

### 7.2 Model A — Output

| รายการ | ค่า |
|---|---|
| Shape | `[1, 5]` (softmax) — ชื่อ output: `gait_probs` |
| Shape | `[1, 32]` (embedding) — ชื่อ output: `gait_embedding` |
| การตีความ | `argmax` = คลาส, `max` = confidence |

| Index | คลาส | Status Level |
|---|---|---|
| 0 | `normal` | 1 |
| 1 | `minor_asymmetry` | 2 |
| 2 | `high_pressure` | 3 |
| 3 | `abnormal_gait` | 4 |
| 4 | `critical` | 5 |

> โมเดลต้องส่งออก **สอง output** — ทั้ง probability และ embedding ขนาด 32 มิติจากชั้นก่อน softmax เพราะ Model B ใช้ embedding เป็น input ไม่ใช่ใช้ผลคลาสสุดท้าย (embedding เก็บข้อมูลได้ละเอียดกว่ามาก)

### 7.3 Model B — Input

**Branch 1: กลไก (จาก Model A)** — ขนาด `[1, 300, 32]`

รวม embedding 300 ครั้ง (5 นาที × 60 วินาที) จาก Model A

**Branch 2: อุณหภูมิและตัวชี้วัดรวม** — ขนาด `[1, 10, 8]`

10 timesteps (5 นาที ÷ 30 วินาที) × 8 features:

| Index | Feature | หน่วย |
|---|---|---|
| 0 | อุณหภูมิเนินปลายเท้าซ้าย | °C |
| 1 | อุณหภูมิเนินปลายเท้าขวา | °C |
| 2 | อุณหภูมิส้นเท้าซ้าย | °C |
| 3 | อุณหภูมิส้นเท้าขวา | °C |
| 4 | ΔT เนินปลายเท้า (L−R) | °C |
| 5 | ΔT ส้นเท้า (L−R) | °C |
| 6 | Peak Asymmetry Index | % |
| 7 | PTI Asymmetry Index | % |

### 7.4 Model B — Output

| รายการ | ค่า |
|---|---|
| Shape | `[1, 5]` (softmax) |
| การตีความ | `argmax + 1` = Status Level 1–5 |

### 7.5 เกณฑ์ยอมรับ

| รายการ | Model A | Model B |
|---|---|---|
| ขนาดไฟล์ `.tflite` | ≤ 10 MB | ≤ 2 MB |
| Inference time (มือถือระดับกลาง) | ≤ 100 ms | ≤ 200 ms |
| Confidence ขั้นต่ำที่ยอมรับผล | 0.60 | 0.60 |

หาก confidence ต่ำกว่าเกณฑ์ หรือโมเดลยังไม่พร้อมใช้งาน แอปจะใช้ผลจาก `RuleBasedEngine` แทนโดยอัตโนมัติ

### 7.6 ลำดับการพัฒนา

Model A ต้องเสร็จก่อน Model B เสมอ เนื่องจาก Model B ใช้ embedding จาก Model A เป็น input — ระหว่างที่ Model B ยังไม่พร้อม ให้ใช้ `RuleBasedEngine` ทำหน้าที่ประเมิน Status Level แทน ซึ่งยังใช้เป็น baseline เปรียบเทียบในรายงานผลการทดลองได้ด้วย

---

## 8. เกณฑ์การแจ้งเตือน (Alert Rules)

### 8.1 หลักการ: ใช้ความสมมาตรแทนค่าฐานส่วนบุคคล

ระบบ **ไม่เก็บ baseline ส่วนบุคคล** เนื่องจากข้อจำกัดด้านการเก็บข้อมูลผู้ใช้และเพราะกลุ่มทดสอบของโครงงานเป็นอาสาสมัครสุขภาพดีที่จำลองท่าเดินผิดปกติ ซึ่งไม่มีค่าฐานระยะยาวให้เก็บอยู่แล้ว

แทนที่จะเทียบกับประวัติของผู้ใช้ ระบบใช้ **เท้าอีกข้างของผู้ใช้เองเป็นกลุ่มควบคุม** ซึ่งเป็นหลักการเดียวกับที่เกณฑ์ ΔT 2.2 °C ของ Lavery ใช้อยู่ — งานวิจัยไม่ได้กำหนดว่าอุณหภูมิสัมบูรณ์เท่าใดคืออันตราย แต่กำหนดจากผลต่างระหว่างสองข้างที่วัดพร้อมกัน เพราะวิธีนี้ตัดตัวแปรกวนอย่างอุณหภูมิห้อง น้ำหนักตัว และช่วงเวลาของวันออกไปได้เกือบทั้งหมด

**ข้อดีเพิ่มเติม** — ระบบใช้งานได้ทันทีตั้งแต่นาทีแรกที่สวมใส่ ไม่ต้องรอสะสมข้อมูล และเทียบระหว่างผู้ใช้ต่างคนได้โดยไม่ต้องปรับค่าตามน้ำหนักตัว

### 8.2 ตัวชี้วัดเชิงสมมาตร

| ตัวชี้วัด | สูตร | เกณฑ์ |
|---|---|---|
| Peak Asymmetry Index (PAI) | `abs(L−R) / ((L+R)/2) × 100` | > 15% = เฝ้าระวัง |
| PTI Asymmetry Index | เทียบแรงกดสะสมซ้าย-ขวา | > 20% = เฝ้าระวัง |
| Load Concentration | `จุดที่สูงสุด / ผลรวม 6 จุด × 100` | จุดเดียว > 40% = เสี่ยง |
| Within-Session Drift | เทียบ 5 นาทีแรกกับ 5 นาทีท้าย | เพิ่ม > 25% = ล้า/ชดเชยท่าเดิน |

> **ข้อควรระวัง** — การเทียบซ้าย-ขวาใช้ FSR คนละชุด หากเซนเซอร์สองข้างให้ค่าไม่ตรงกันจะเกิดความไม่สมมาตรปลอม (False Asymmetry) จึงต้องทำ **bench calibration** ตอนประกอบ โดยกดแผ่นรองเท้าทั้งคู่ด้วยน้ำหนักมาตรฐานเดียวกันแล้วบันทึกค่าชดเชยลง NVS (ดูข้อ 5.1) ขั้นตอนนี้ทำครั้งเดียวที่โรงงาน/ห้องแล็บ ไม่ต้องเก็บข้อมูลจากผู้ใช้เลย

### 8.3 เกณฑ์รายตัว

| รหัส | เงื่อนไข | ระดับ | ที่มา |
|---|---|---|---|
| `TEMP_DELTA` | ΔT ซ้าย-ขวา ตำแหน่งเดียวกัน > 2.2 °C ต่อเนื่อง ≥ 2 ครั้งวัด | 4 | Lavery et al. (2004) |
| `PRESSURE_WATCH` | จุดใดจุดหนึ่ง > 75 kPa | 2 | เกณฑ์เฝ้าระวังของโครงงาน |
| `PRESSURE_PEAK` | Peak > 200 kPa ขณะเดิน | 3 | Owings et al. (2009) |
| `PRESSURE_PTI` | PTI > 80 kPa·s สะสมในหน้าต่าง 1 ชม. | 3 | Waaijman et al. (2014) |
| `ASYMMETRY_PEAK` | PAI > 15% ต่อเนื่อง ≥ 20 ก้าว | 2 | ตัวชี้วัดของโครงงาน |
| `LOAD_CONCENTRATION` | จุดเดียวรับน้ำหนัก > 40% ของฝ่าเท้า | 3 | ตัวชี้วัดของโครงงาน |
| `GAIT_ABNORMAL` | Model A จำแนกคลาส 3 หรือ 4 และ confidence ≥ 0.60 | 4 | โมเดลของโครงงาน |
| `DEVICE_LOST` | ขาดการเชื่อมต่อ > 5 นาที | 1 | — |
| `BATTERY_LOW` | แบตเตอรี่ < 15% | 1 | — |

**ข้อตกลงเรื่องเกณฑ์แรงกดสองระดับ**

| ระดับ | ค่า | การแสดงผล | แจ้งเตือน |
|---|---|---|---|
| เฝ้าระวัง | 75 kPa | วงกลมสีส้มบน heatmap | ไม่ push notification |
| แจ้งเตือน | 200 kPa | วงกลมสีแดง + ป้าย ALERT | push notification |

> **หมายเหตุทางเทคนิคที่ต้องระบุในเล่ม** — ค่า 200 kPa จากงานวิจัยได้มาจากแผ่นวัดที่มีเซนเซอร์หลายร้อยจุด ขณะที่ระบบนี้มี FSR เพียง 6 จุดต่อข้าง จึงมีโอกาสวัดไม่ตรงตำแหน่งที่แรงกดสูงสุดจริง ทำให้ค่าที่อ่านได้มีแนวโน้มต่ำกว่าความเป็นจริง ตัวชี้วัดเชิงสมมาตรในข้อ 8.2 จึงถูกออกแบบมาเพื่อชดเชยข้อจำกัดเชิงพื้นที่นี้โดยเฉพาะ

**ค่าเกณฑ์ทั้งหมดต้องเก็บในไฟล์ `thresholds.json` ห้าม hardcode ในโค้ด** เพราะจะต้องปรับหลังการทดสอบกับฮาร์ดแวร์จริงอย่างแน่นอน

```json
{
  "version": 1,
  "pressure": { "watchKpa": 75, "alertKpa": 200, "ptiKpaS": 80 },
  "temperature": { "deltaC": 2.2, "consecutiveReadings": 2 },
  "asymmetry": { "peakPct": 15, "ptiPct": 20, "concentrationPct": 40 },
  "model": { "minConfidence": 0.60 }
}
```

### 8.4 การรวมผล (Fusion)

```
statusLevel = max(ระดับจากทุกกฎที่เข้าเงื่อนไข, ระดับจาก Model B)
```

ใช้ค่าสูงสุดเพื่อความปลอดภัยของผู้ป่วย (fail-safe) — ยอมเตือนเกินดีกว่าพลาด

### 8.5 การป้องกันการเตือนซ้ำ

- แจ้งเตือนรหัสเดียวกันได้ไม่เกิน 1 ครั้งต่อ **30 นาที**
- ทุกการแจ้งเตือนต้องมีข้อความคำแนะนำภาษาไทยกำกับเสมอ ไม่แสดงเพียงตัวเลข

---

## 9. Schema ของ Firebase

**หลักการ: ไม่ส่งข้อมูลดิบ 50 Hz ขึ้น cloud** — เก็บใน SQLite และซิงค์เฉพาะข้อมูลสรุปกับเหตุการณ์

```
users/{uid}
  ├─ profile        : { displayName, iwgdfRiskGroup, createdAt }
  ├─ devices/{id}   : { side, lastSeen, firmware, batteryPct }
  ├─ hourly/{yyyyMMddHH}
  │     { steps, walkMinutes, peakKpaL, peakKpaR, ptiL, ptiR,
  │       avgTempForefootL, avgTempForefootR, maxDeltaT,
  │       symmetryScore, dominantGaitClass }
  ├─ alerts/{alertId}
  │     { code, tUnixMs, level, valueSnapshot, adviceTh,
  │       acknowledged, source }
  └─ sessions/{sessionId}
        { startMs, endMs, sampleCount, uploadedAt }
```

**นโยบายการซิงค์**

| ข้อมูล | ความถี่ | เงื่อนไข |
|---|---|---|
| `alerts` | ทันที | เมื่อมีเน็ต ถ้าไม่มีให้ queue ไว้ |
| `hourly` | ทุก 1 ชม. | Wi-Fi หรือ mobile data |
| `devices` | เมื่อสถานะเปลี่ยน | — |
| ข้อมูลดิบ | ไม่ซิงค์ | เก็บใน SQLite เท่านั้น |

---

## 10. รายการส่งมอบระหว่างทีม

| จาก | ถึง | สิ่งที่ส่งมอบ | จำเป็นก่อนเฟส |
|---|---|---|---|
| ฮาร์ดแวร์ | แอป | ยืนยัน packet format + UUID | 2 |
| ฮาร์ดแวร์ | แอป | ไฟล์ calibration JSON | 3 |
| ฮาร์ดแวร์ | แอป | ต้นแบบใช้งานได้ 1 คู่ | 5 |
| แอป | AI | ข้อมูลจริงจาก sensor สำหรับเทรน | 4 |
| ฮาร์ดแวร์ | แอป | ผล bench calibration ซ้าย-ขวา (บันทึกลง NVS) | 5 |
| AI | แอป | `model_a.tflite` + `normalization.json` | 4 |
| AI | แอป | `model_b.tflite` (dual-branch fusion) | 4 |
| AI | แอป | รายงาน accuracy + confusion matrix ของทั้ง 2 โมเดล | 4 |

---

## ภาคผนวก A — รหัสข้อผิดพลาด

| รหัส | ความหมาย |
|---|---|
| 0 | ปกติ |
| 1 | IMU ไม่ตอบสนอง |
| 2 | อ่านค่า NTC ไม่ได้ |
| 3 | ADC อิ่มตัว (สงสัยสายลัดวงจร) |
| 4 | แรงดันแบตเตอรี่ต่ำวิกฤต |
| 5 | หน่วยความจำภายในเต็ม |

## ภาคผนวก B — Checklist ก่อนอนุมัติเอกสาร

- [ ] ทีมฮาร์ดแวร์ยืนยันว่า ESP32 ส่งข้อมูลตาม format นี้ได้จริง
- [ ] ทีมฮาร์ดแวร์ยืนยันรุ่นบอร์ดที่ใช้ (ต้องมี BLE — **ห้ามใช้ ESP32-S2**)
- [ ] ทีม AI ยืนยัน input shape และลำดับ channel
- [x] ตัดสินใจเรื่องเกณฑ์ 75 kPa vs 200 kPa แล้ว → ใช้สองระดับ (ข้อ 8.3)
- [ ] ทีมฮาร์ดแวร์ยืนยันว่าเขียน calibration ลง NVS และเปิดให้อ่านผ่าน BLE ได้
- [ ] วางแผนขั้นตอน bench calibration ซ้าย-ขวาแล้ว (ข้อ 8.2)
- [ ] ทีม AI ยืนยันว่า Model A ส่งออก embedding 32 มิติได้
- [ ] ยืนยันตำแหน่งติดตั้ง FSR ทั้ง 6 จุดตรงกับตารางข้อ 3.1
- [ ] ตกลงว่าใครเป็นผู้ดูแลเอกสารนี้เมื่อมีการเปลี่ยนแปลง

---

## ประวัติการแก้ไข

| เวอร์ชัน | วันที่ | ผู้แก้ไข | รายละเอียด |
|---|---|---|---|
| 1.0 | — | — | ฉบับร่างแรก |
| 1.1 | — | — | เก็บ calibration ใน NVS ของ ESP32 (ข้อ 5.1), แยกโมเดลเป็น 2 ตัวแบบ multi-timescale พร้อม dual-branch fusion (ข้อ 7), เปลี่ยนจาก baseline ส่วนบุคคลมาใช้ตัวชี้วัดเชิงสมมาตร (ข้อ 8.1–8.2), กำหนดเกณฑ์แรงกดสองระดับและย้ายค่าเกณฑ์ไป `thresholds.json` (ข้อ 8.3) |
