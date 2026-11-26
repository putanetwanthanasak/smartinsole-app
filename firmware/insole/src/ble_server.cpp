#include "ble_server.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "cal_store.h"
#include "config.h"
#include "control.h"
#include "insole_frames.h"
#include "stream_session.h"
#include "tare_mean.h"

using insole::OutPacket;
using insole::SessionTable;
using insole::StreamSession;

static_assert(SessionTable::kMaxSessions >= 2, "at least two centrals");
static_assert(SessionTable::kMaxSessions <= CONFIG_BT_NIMBLE_MAX_CONNECTIONS,
              "NimBLE connection limit is below the session table size");

namespace ble {
namespace {

// Connection parameters requested from the central (contract §2.3).
constexpr uint16_t kConnIntervalMin = 12;  // x 1.25 ms = 15 ms
constexpr uint16_t kConnIntervalMax = 24;  // 30 ms
constexpr uint16_t kSlaveLatency = 0;
constexpr uint16_t kSupervisionTimeout = 400;  // x 10 ms = 4000 ms
constexpr uint16_t kAdvInterval = 160;         // x 0.625 ms = 100 ms
constexpr uint32_t kRebootResponseMs = 300;
constexpr uint32_t kRebootDisconnectMs = 200;

NimBLEServer* gServer = nullptr;
NimBLECharacteristic* gSensor = nullptr;
NimBLECharacteristic* gTemperature = nullptr;
NimBLECharacteristic* gStatus = nullptr;
NimBLECharacteristic* gControl = nullptr;
NimBLECharacteristic* gCalibration = nullptr;

// Sessions are touched by the NimBLE host task (callbacks) and the tick
// task. Notifications are always sent after the lock is released.
SemaphoreHandle_t gLock = nullptr;
SessionTable gSessions;
insole_hw::SaturationFlag gSatFlags[SessionTable::kMaxSessions];
insole::DeviceStatus gStatusValue{};
uint32_t gNotifyFailures = 0;
const insole::TemperatureReading kNoNtc = insole_hw::noNtcReading();

// Device-wide state, under gLock like the sessions.
insole_hw::TareMean gTare;
bool gRebootPending = false;

struct Lock {
  Lock() { xSemaphoreTake(gLock, portMAX_DELAY); }
  ~Lock() { xSemaphoreGive(gLock); }
};

insole_hw::SaturationFlag& flagOf(StreamSession* s) { return gSatFlags[s - gSessions.begin()]; }

// Call with gLock held. Returns true if `state` changed.
bool refreshState() {
  auto state = gSessions.anyStreaming() ? insole::DeviceState::Streaming
                                        : insole::DeviceState::Idle;
  if (state == gStatusValue.state) return false;
  gStatusValue.state = state;
  return true;
}

void publishStatus() {
  uint8_t bytes[insole::kStatusBytes];
  uint16_t targets[SessionTable::kMaxSessions];
  int n = 0;
  {
    Lock l;
    insole::encodeStatus(bytes, gStatusValue);
    for (StreamSession& s : gSessions)
      if (s.inUse() && s.statusSubscribed) targets[n++] = s.connHandle;
  }
  gStatus->setValue(bytes, sizeof bytes);
  for (int i = 0; i < n; ++i)
    if (!gStatus->notify(bytes, sizeof bytes, targets[i])) ++gNotifyFailures;
}

// A central already connected sees a new calibration only when it reads
// again (no contract signal for "calibration changed").
// Called from the tick task (TARE) and the serial loop (`cal set`).
SemaphoreHandle_t gCalLock = nullptr;

void publishCalibration() {
  xSemaphoreTake(gCalLock, portMAX_DELAY);
  char cal[insole_hw::kMaxCalibrationBytes + 1];
  size_t len = cal_store::json(cal, sizeof cal);
  gCalibration->setValue(reinterpret_cast<const uint8_t*>(cal), len);
  insole_hw::CalData now = cal_store::current();
  xSemaphoreGive(gCalLock);
  Serial.printf("[cal] serving %u bytes, offset_adc", static_cast<unsigned>(len));
  for (const insole_hw::CalChannel& c : now.ch) Serial.printf(" %u", c.offsetAdc);
  Serial.printf("\n");
}

void rebootTask(void*) {
  vTaskDelay(pdMS_TO_TICKS(kRebootResponseMs));
  uint16_t conns[SessionTable::kMaxSessions];
  int n = 0;
  {
    Lock l;
    for (StreamSession& s : gSessions)
      if (s.inUse()) conns[n++] = s.connHandle;
  }
  gServer->advertiseOnDisconnect(false);
  NimBLEDevice::stopAdvertising();
  for (int i = 0; i < n; ++i) gServer->disconnect(conns[i]);
  Serial.printf("[ctl] REBOOT: disconnected %d central(s), restarting\n", n);
  vTaskDelay(pdMS_TO_TICKS(kRebootDisconnectMs));
  esp_restart();
}

int connectedSessions() {
  int n = 0;
  for (StreamSession& s : gSessions)
    if (s.inUse()) ++n;
  return n;
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    uint16_t conn = info.getConnHandle();
    bool ok;
    int connected;
    {
      Lock l;
      StreamSession* s = gSessions.open(conn);
      ok = s != nullptr;
      if (s) {
        s->mtu = info.getMTU();
        flagOf(s).reset();
      }
      connected = connectedSessions();
    }
    if (!ok) {
      Serial.printf("[ble] conn %u: no free session, disconnecting\n", conn);
      server->disconnect(conn);
      return;
    }
    if (connected < SessionTable::kMaxSessions) NimBLEDevice::startAdvertising();
    server->updateConnParams(conn, kConnIntervalMin, kConnIntervalMax, kSlaveLatency,
                             kSupervisionTimeout);
    // The central's address is not logged: serial logs may be quoted in
    // reports, and the repo is public.
    Serial.printf("[ble] conn %u: connected, mtu %u, %d connected\n", conn, info.getMTU(),
                  connected);
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo& info, int reason) override {
    uint16_t conn = info.getConnHandle();
    bool changed;
    {
      Lock l;
      if (StreamSession* s = gSessions.find(conn)) flagOf(s).reset();
      gSessions.close(conn);
      changed = refreshState();
    }
    Serial.printf("[ble] conn %u: disconnected, reason 0x%x\n", conn, reason);
    if (changed) publishStatus();
  }

  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    uint16_t conn = info.getConnHandle();
    {
      Lock l;
      if (StreamSession* s = gSessions.open(conn)) s->mtu = mtu;
    }
    Serial.printf("[ble] conn %u: mtu %u -> %u samples/packet\n", conn, mtu,
                  insole::samplesPerPacket(mtu, config::kFsrCount));
  }
};

class SubscribeCallbacks : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic* chr, NimBLEConnInfo& info, uint16_t subValue) override {
    bool on = subValue & 1;
    uint16_t conn = info.getConnHandle();
    {
      Lock l;
      StreamSession* s = gSessions.find(conn);
      if (!s) return;
      if (chr == gSensor) s->sensorSubscribed = on;
      if (chr == gTemperature) s->temperatureSubscribed = on;
      if (chr == gStatus) s->statusSubscribed = on;
    }
    Serial.printf("[ble] conn %u: %s notifications %s\n", conn,
                  chr->getUUID().toString().c_str(), on ? "on" : "off");
  }
};

// Per-connection: START, STOP, SYNC_TIME. Device-wide: SET_RATE, TARE,
// REBOOT (they act on the one physical insole, so every central sees them).
class ControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
    NimBLEAttValue v = chr->getValue();
    uint16_t conn = info.getConnHandle();
    insole::Command cmd = insole::parseControl(v.data(), v.size());
    uint32_t now = millis();
    bool changed = false;
    bool applied = true;
    {
      Lock l;
      StreamSession* s = gSessions.find(conn);
      if (!s) return;
      switch (cmd.kind) {
        case insole::CommandKind::Start:
          applied = s->start(now);
          if (applied) flagOf(s).reset();
          break;
        case insole::CommandKind::Stop:
          s->stop();
          flagOf(s).reset();
          break;
        case insole::CommandKind::SyncTime:
          s->synced = true;
          s->syncUnixMs = cmd.unixMs;
          s->syncDeviceMs = now;
          break;
        case insole::CommandKind::SetRate:
          applied = cmd.rateHz == insole::kSupportedRateHz;
          break;
        case insole::CommandKind::Tare:
          applied = gTare.begin();
          break;
        case insole::CommandKind::Reboot:
          applied = !gRebootPending;
          gRebootPending = true;
          break;
        case insole::CommandKind::Malformed:
        case insole::CommandKind::Unknown:
          break;
      }
      changed = refreshState();
    }

    switch (cmd.kind) {
      case insole::CommandKind::Start:
        Serial.printf("[ctl] conn %u: START_STREAM%s\n", conn,
                      applied ? "" : " (already streaming, ignored)");
        break;
      case insole::CommandKind::SyncTime:
        Serial.printf("[ctl] conn %u: SYNC_TIME unix %llu ms at device %lu ms\n", conn,
                      static_cast<unsigned long long>(cmd.unixMs),
                      static_cast<unsigned long>(now));
        break;
      case insole::CommandKind::SetRate:
        Serial.printf("[ctl] conn %u: SET_RATE %u Hz %s\n", conn, cmd.rateHz,
                      applied ? "(already the rate)" : "unsupported, stays 50 Hz (rule 1)");
        break;
      case insole::CommandKind::Tare:
        Serial.printf("[ctl] conn %u: TARE%s\n", conn,
                      applied ? ": 1 s mean, keep the insole unloaded" : " (already running, ignored)");
        break;
      case insole::CommandKind::Reboot:
        Serial.printf("[ctl] conn %u: REBOOT%s\n", conn, applied ? " in 300 ms" : " (pending)");
        if (applied) xTaskCreate(rebootTask, "reboot", 3072, nullptr, 1, nullptr);
        break;
      case insole::CommandKind::Malformed:
        Serial.printf("[ctl] conn %u: opcode 0x%02x with %u bytes: wrong length, ignored\n", conn,
                      cmd.opcode, static_cast<unsigned>(v.size()));
        break;
      case insole::CommandKind::Unknown:
        Serial.printf("[ctl] conn %u: opcode 0x%02x not in the contract, ignored\n", conn,
                      cmd.opcode);
        break;
      default:
        Serial.printf("[ctl] conn %u: %s\n", conn, insole::commandName(cmd.kind));
        break;
    }
    if (changed) publishStatus();
  }
};

ServerCallbacks gServerCallbacks;
SubscribeCallbacks gSubscribeCallbacks;
ControlCallbacks gControlCallbacks;

}  // namespace

void begin() {
  gLock = xSemaphoreCreateMutex();
  gCalLock = xSemaphoreCreateMutex();

  NimBLEDevice::init(config::kDeviceName);
  NimBLEDevice::setPower(0);  // dBm, as the simulator; revisit in the shoe
  NimBLEDevice::setMTU(insole::kTargetMtu);

  gServer = NimBLEDevice::createServer();
  gServer->setCallbacks(&gServerCallbacks);
  gServer->advertiseOnDisconnect(true);

  NimBLEService* svc = gServer->createService(insole::kServiceUuid);
  gSensor = svc->createCharacteristic(insole::kSensorUuid, NIMBLE_PROPERTY::NOTIFY);
  gTemperature = svc->createCharacteristic(insole::kTemperatureUuid, NIMBLE_PROPERTY::NOTIFY);
  gStatus = svc->createCharacteristic(insole::kStatusUuid,
                                      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  gControl = svc->createCharacteristic(insole::kControlUuid,
                                       NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  gCalibration = svc->createCharacteristic(insole::kCalibrationUuid, NIMBLE_PROPERTY::READ,
                                           insole_hw::kMaxCalibrationBytes);

  gSensor->setCallbacks(&gSubscribeCallbacks);
  gTemperature->setCallbacks(&gSubscribeCallbacks);
  gStatus->setCallbacks(&gSubscribeCallbacks);
  gControl->setCallbacks(&gControlCallbacks);

  publishCalibration();

  // No battery fitted: 255 / 0 mV (contract §3.3 addendum 2).
  gStatusValue = {insole_hw::kBatteryExternalPct, insole_hw::kBatteryExternalMv,
                  config::kFootSide, config::kFwMajor, config::kFwMinor,
                  insole::DeviceState::Idle, 0};
  uint8_t st[insole::kStatusBytes];
  insole::encodeStatus(st, gStatusValue);
  gStatus->setValue(st, sizeof st);

  gServer->start();

  // UUID in the advertisement, name in the scan response (31-byte limit).
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.addServiceUUID(insole::kServiceUuid);
  NimBLEAdvertisementData scanData;
  scanData.setName(config::kDeviceName);
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  adv->enableScanResponse(true);
  adv->setMinInterval(kAdvInterval);
  adv->setMaxInterval(kAdvInterval);
  adv->start();

  Serial.printf("[ble] advertising as %s, fw %u.%u, up to %d centrals\n", config::kDeviceName,
                config::kFwMajor, config::kFwMinor, SessionTable::kMaxSessions);
}

void pushSample(const insole::Sample& sample, bool saturated, uint32_t tMs) {
  struct Pending {
    NimBLECharacteristic* chr;
    uint16_t conn;
    OutPacket pkt;
  };
  static Pending pending[2 * SessionTable::kMaxSessions];
  int n = 0;
  insole_hw::TareMean::Outcome tare;
  uint16_t newOffsets[insole_hw::kCalChannels];
  uint8_t movedChannel = 0;
  uint16_t movedSpread = 0;
  {
    Lock l;
    bool calibrating = gTare.active();
    tare = gTare.feed(sample.fsr);
    if (tare == insole_hw::TareMean::Outcome::Done)
      for (uint8_t c = 0; c < insole_hw::kCalChannels; ++c) newOffsets[c] = gTare.offsets()[c];
    if (tare == insole_hw::TareMean::Outcome::Moved) {
      movedChannel = gTare.movedChannel();
      movedSpread = gTare.spread(movedChannel);
    }
    for (StreamSession& s : gSessions) {
      if (!s.inUse()) continue;
      Pending& p = pending[n];
      if (flagOf(&s).add(s, sample, saturated, tMs, config::kFsrCount, p.pkt, calibrating) &&
          s.sensorSubscribed) {
        p.chr = gSensor;
        p.conn = s.connHandle;
        ++n;
      }
      Pending& q = pending[n];
      if (s.temperatureDue(tMs, kNoNtc, q.pkt) && s.temperatureSubscribed) {
        q.chr = gTemperature;
        q.conn = s.connHandle;
        ++n;
      }
    }
  }
  for (int i = 0; i < n; ++i)
    if (!pending[i].chr->notify(pending[i].pkt.bytes, pending[i].pkt.len, pending[i].conn))
      ++gNotifyFailures;

  if (tare == insole_hw::TareMean::Outcome::Done) {
    // The flash write stalls this task a few ms; the tick catches up on the
    // fixed 20 ms grid (vTaskDelayUntil), so sample times are unaffected.
    bool saved = cal_store::setOffsets(newOffsets);
    Serial.printf("[cal] TARE done (1 s mean), %s NVS\n", saved ? "saved to" : "FAILED to save to");
    publishCalibration();
  } else if (tare == insole_hw::TareMean::Outcome::Moved) {
    Serial.printf("[cal] TARE refused: channel %u moved %u counts in 1 s (insole touched?); "
                  "offsets unchanged\n",
                  movedChannel, movedSpread);
  }
}

void updateStatus(uint8_t errorCode) {
  bool changed;
  {
    Lock l;
    changed = refreshState() || errorCode != gStatusValue.errorCode;
    gStatusValue.errorCode = errorCode;
  }
  if (changed) publishStatus();
}

void republishCalibration() { publishCalibration(); }

void logSessions() {
  Lock l;
  int active = 0;
  for (StreamSession& s : gSessions) {
    if (!s.inUse()) continue;
    ++active;
    Serial.printf("[sess] conn %u mtu %u (%u/pkt) %s sub[s%d t%d st%d] sent %lu mtu-drops %lu%s\n",
                  s.connHandle, s.mtu, insole::samplesPerPacket(s.mtu, config::kFsrCount),
                  s.streaming() ? "streaming" : "idle", s.sensorSubscribed,
                  s.temperatureSubscribed, s.statusSubscribed,
                  static_cast<unsigned long>(s.packetsSent),
                  static_cast<unsigned long>(s.samplesDroppedForMtu), s.synced ? " synced" : "");
  }
  Serial.printf("[sess] %d connected, error %u, notify failures %lu, heap %lu\n", active,
                gStatusValue.errorCode, static_cast<unsigned long>(gNotifyFailures),
                static_cast<unsigned long>(ESP.getFreeHeap()));
}

}  // namespace ble
