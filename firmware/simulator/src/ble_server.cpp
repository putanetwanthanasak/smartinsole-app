#include "ble_server.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>

#include "calibration.h"
#include "config.h"
#include "control.h"
#include "data_source.h"
#include "stream_session.h"
#include "tare.h"

using insole::OutPacket;
using insole::SessionTable;
using insole::StreamSession;

// Two concurrent centrals at least (BACKLOG 17); NimBLE must allow as many
// connections as there are sessions.
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
// REBOOT waits for the write response to go out, then disconnects every
// central cleanly (so they see the drop at once instead of after the 4 s
// supervision timeout), then restarts.
constexpr uint32_t kRebootResponseMs = 300;
constexpr uint32_t kRebootDisconnectMs = 200;

constexpr const char* kNvsNamespace = "insole";
constexpr const char* kNvsOffsetsKey = "offsets";

uint8_t gFsrCount = 6;
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
insole::DeviceStatus gStatusValue{};
uint32_t gNotifyFailures = 0;

// Device-wide state, under gLock like the sessions.
insole::Tare gTare;
uint16_t gOffsets[insole::kMaxFsrCount];
bool gRebootPending = false;

struct Lock {
  Lock() { xSemaphoreTake(gLock, portMAX_DELAY); }
  ~Lock() { xSemaphoreGive(gLock); }
};

// Call with gLock held. Returns true if `state` changed.
bool refreshState() {
  auto state = gSessions.anyStreaming() ? insole::DeviceState::Streaming
                                        : insole::DeviceState::Idle;
  if (state == gStatusValue.state) return false;
  gStatusValue.state = state;
  return true;
}

// Sets the readable value and notifies every subscribed connection.
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

// offset_adc survives REBOOT and power cycles in NVS. A missing entry, or one
// stored for a different FSR count, leaves the contract example value.
void loadOffsets() {
  for (auto& o : gOffsets) o = insole::kDefaultOffsetAdc;
  Preferences nvs;
  if (!nvs.begin(kNvsNamespace, true)) return;  // namespace not created yet
  uint16_t stored[insole::kMaxFsrCount];
  size_t len = nvs.getBytesLength(kNvsOffsetsKey);
  if (len == gFsrCount * sizeof(uint16_t) && nvs.getBytes(kNvsOffsetsKey, stored, len) == len) {
    for (uint8_t c = 0; c < gFsrCount; ++c) gOffsets[c] = stored[c];
    Serial.printf("[cal] offsets loaded from NVS\n");
  }
  nvs.end();
}

bool saveOffsets(const uint16_t* offsets) {
  Preferences nvs;
  if (!nvs.begin(kNvsNamespace, false)) return false;
  size_t len = gFsrCount * sizeof(uint16_t);
  bool ok = nvs.putBytes(kNvsOffsetsKey, offsets, len) == len;
  nvs.end();
  return ok;
}

// Rebuilds the blob from `offsets` and sets it as the readable value. A
// central already connected sees it only when it reads again (no contract
// signal for "calibration changed", BACKLOG).
void publishCalibration(const uint16_t* offsets) {
  static char cal[insole::kMaxCalibrationBytes + 1];
  size_t len = insole::buildCalibrationJson(cal, sizeof cal, config::kDeviceId, gFsrCount,
                                            offsets);
  gCalibration->setValue(reinterpret_cast<const uint8_t*>(cal), len);
  Serial.printf("[cal] %u bytes, offset_adc", static_cast<unsigned>(len));
  for (uint8_t c = 0; c < gFsrCount; ++c) Serial.printf(" %u", offsets[c]);
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
  // No advertising until the restart: a central must not find the old boot.
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
      if (s) s->mtu = info.getMTU();
      connected = connectedSessions();
    }
    if (!ok) {
      Serial.printf("[ble] conn %u: no free session, disconnecting\n", conn);
      server->disconnect(conn);
      return;
    }
    // NimBLE stops advertising on connect; keep going so another central
    // can connect while this one streams.
    if (connected < SessionTable::kMaxSessions) NimBLEDevice::startAdvertising();
    server->updateConnParams(conn, kConnIntervalMin, kConnIntervalMax, kSlaveLatency,
                             kSupervisionTimeout);
    Serial.printf("[ble] conn %u: connected %s, mtu %u, %d connected\n", conn,
                  info.getAddress().toString().c_str(), info.getMTU(), connected);
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo& info, int reason) override {
    uint16_t conn = info.getConnHandle();
    bool changed;
    {
      Lock l;
      gSessions.close(conn);  // only this connection's stream ends
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
                  insole::samplesPerPacket(mtu, gFsrCount));
  }

  void onConnParamsUpdate(NimBLEConnInfo& info) override {
    Serial.printf("[ble] conn %u: interval %.2f ms, latency %u, timeout %u ms\n",
                  info.getConnHandle(), info.getConnInterval() * 1.25f, info.getConnLatency(),
                  info.getConnTimeout() * 10);
  }
};

class SubscribeCallbacks : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic* chr, NimBLEConnInfo& info, uint16_t subValue) override {
    bool on = subValue & 1;  // notifications bit
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
    const char* name = insole::commandName(cmd.kind);
    uint32_t now = millis();
    bool changed = false;
    bool applied = true;  // false: valid, but changed nothing
    {
      Lock l;
      StreamSession* s = gSessions.find(conn);
      if (!s) return;
      switch (cmd.kind) {
        case insole::CommandKind::Start:
          applied = s->start(now);
          break;
        case insole::CommandKind::Stop:
          s->stop();  // this connection only
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
          applied = gTare.begin(gFsrCount);
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
        if (applied)
          Serial.printf("[ctl] conn %u: SET_RATE %u Hz (already the rate)\n", conn, cmd.rateHz);
        else
          Serial.printf("[ctl] conn %u: SET_RATE %u Hz unsupported, stays %u Hz (rule 1)\n",
                        conn, cmd.rateHz, insole::kSupportedRateHz);
        break;
      case insole::CommandKind::Tare:
        Serial.printf("[ctl] conn %u: TARE%s\n", conn,
                      applied ? ", measuring one stride" : " (already running, ignored)");
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
        Serial.printf("[ctl] conn %u: %s\n", conn, name);
        break;
    }
    if (changed) publishStatus();
  }
};

ServerCallbacks gServerCallbacks;
SubscribeCallbacks gSubscribeCallbacks;
ControlCallbacks gControlCallbacks;

}  // namespace

void begin(uint8_t fsrCount) {
  gFsrCount = fsrCount;
  gLock = xSemaphoreCreateMutex();

  NimBLEDevice::init(config::kDeviceName);
  NimBLEDevice::setPower(0);  // dBm
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
                                           insole::kMaxCalibrationBytes);

  gSensor->setCallbacks(&gSubscribeCallbacks);
  gTemperature->setCallbacks(&gSubscribeCallbacks);
  gStatus->setCallbacks(&gSubscribeCallbacks);
  gControl->setCallbacks(&gControlCallbacks);

  loadOffsets();
  publishCalibration(gOffsets);

  gStatusValue = {100, 4200, config::kFootSide, config::kFwMajor,
                  config::kFwMinor, insole::DeviceState::Idle, 0};
  uint8_t st[insole::kStatusBytes];
  insole::encodeStatus(st, gStatusValue);
  gStatus->setValue(st, sizeof st);

  gServer->start();

  // The 128-bit service UUID and the name don't fit one 31-byte advertising
  // packet together: UUID in the advertisement, name in the scan response.
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

  Serial.printf("[ble] advertising as %s, fsr_count %u, up to %d centrals\n",
                config::kDeviceName, fsrCount, SessionTable::kMaxSessions);
}

void pushSample(const insole::Sample& sample, const insole::TemperatureReading& temp,
                uint32_t tMs) {
  struct Pending {
    NimBLECharacteristic* chr;
    uint16_t conn;
    OutPacket pkt;
  };
  static Pending pending[2 * SessionTable::kMaxSessions];
  int n = 0;
  bool tareDone = false;
  uint16_t newOffsets[insole::kMaxFsrCount];
  {
    Lock l;
    // A sample measured by the tare is marked calibrating in every stream.
    bool calibrating = gTare.active();
    if (gTare.feed(sample)) {
      tareDone = true;
      for (uint8_t c = 0; c < insole::kMaxFsrCount; ++c) gOffsets[c] = gTare.offsets()[c];
      memcpy(newOffsets, gOffsets, sizeof newOffsets);
    }
    for (StreamSession& s : gSessions) {
      if (!s.inUse()) continue;
      Pending& p = pending[n];
      if (s.addSample(sample, tMs, gFsrCount, p.pkt, calibrating) && s.sensorSubscribed) {
        p.chr = gSensor;
        p.conn = s.connHandle;
        ++n;
      }
      Pending& q = pending[n];
      if (s.temperatureDue(tMs, temp, q.pkt) && s.temperatureSubscribed) {
        q.chr = gTemperature;
        q.conn = s.connHandle;
        ++n;
      }
    }
  }
  for (int i = 0; i < n; ++i)
    if (!pending[i].chr->notify(pending[i].pkt.bytes, pending[i].pkt.len, pending[i].conn))
      ++gNotifyFailures;

  if (tareDone) {
    // The flash write stalls this task a few ms; the tick catches up on the
    // fixed 20 ms grid (vTaskDelayUntil), so sample times are unaffected.
    uint32_t t = millis();
    bool saved = saveOffsets(newOffsets);
    Serial.printf("[cal] TARE done, %s NVS in %lu ms\n", saved ? "saved to" : "FAILED to save to",
                  static_cast<unsigned long>(millis() - t));
    publishCalibration(newOffsets);
  }
}

void updateStatus(const insole::BatteryReading& battery) {
  bool changed;
  {
    Lock l;
    changed = refreshState() || battery.pct != gStatusValue.batteryPct;
    gStatusValue.batteryPct = battery.pct;
    gStatusValue.batteryMv = battery.mv;
  }
  if (changed) publishStatus();
}

void logSessions() {
  Lock l;
  int active = 0;
  for (StreamSession& s : gSessions) {
    if (!s.inUse()) continue;
    ++active;
    Serial.printf("[sess] conn %u mtu %u (%u/pkt) %s sub[s%d t%d st%d] sent %lu mtu-drops %lu%s\n",
                  s.connHandle, s.mtu, insole::samplesPerPacket(s.mtu, gFsrCount),
                  s.streaming() ? "streaming" : "idle", s.sensorSubscribed,
                  s.temperatureSubscribed, s.statusSubscribed,
                  static_cast<unsigned long>(s.packetsSent),
                  static_cast<unsigned long>(s.samplesDroppedForMtu),
                  s.synced ? " synced" : "");
  }
  Serial.printf("[sess] %d connected, battery %u%%, notify failures %lu, heap %lu\n", active,
                gStatusValue.batteryPct, static_cast<unsigned long>(gNotifyFailures),
                static_cast<unsigned long>(ESP.getFreeHeap()));
}

}  // namespace ble
