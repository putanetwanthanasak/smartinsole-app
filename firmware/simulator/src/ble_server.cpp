#include "ble_server.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "calibration.h"
#include "config.h"
#include "data_source.h"
#include "stream_session.h"

using insole::OutPacket;
using insole::SessionTable;
using insole::StreamSession;

namespace ble {
namespace {

// Connection parameters requested from the central (contract §2.3).
constexpr uint16_t kConnIntervalMin = 12;  // x 1.25 ms = 15 ms
constexpr uint16_t kConnIntervalMax = 24;  // 30 ms
constexpr uint16_t kSlaveLatency = 0;
constexpr uint16_t kSupervisionTimeout = 400;  // x 10 ms = 4000 ms
constexpr uint16_t kAdvInterval = 160;         // x 0.625 ms = 100 ms

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

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    uint16_t conn = info.getConnHandle();
    bool ok;
    {
      Lock l;
      StreamSession* s = gSessions.open(conn);
      ok = s != nullptr;
      if (s) s->mtu = info.getMTU();
    }
    if (!ok) {
      Serial.printf("[ble] conn %u: no free session, disconnecting\n", conn);
      server->disconnect(conn);
      return;
    }
    server->updateConnParams(conn, kConnIntervalMin, kConnIntervalMax, kSlaveLatency,
                             kSupervisionTimeout);
    Serial.printf("[ble] conn %u: connected %s, mtu %u\n", conn,
                  info.getAddress().toString().c_str(), info.getMTU());
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

class ControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
    NimBLEAttValue v = chr->getValue();
    uint16_t conn = info.getConnHandle();
    if (v.size() == 0) return;
    auto op = static_cast<insole::Opcode>(v[0]);
    bool changed = false;
    {
      Lock l;
      StreamSession* s = gSessions.find(conn);
      if (!s) return;
      switch (op) {
        case insole::Opcode::StartStream:
          s->start(millis());
          break;
        case insole::Opcode::StopStream:
          s->stop();  // this connection only
          break;
        default:
          break;
      }
      changed = refreshState();
    }
    switch (op) {
      case insole::Opcode::StartStream:
        Serial.printf("[ctl] conn %u: START_STREAM\n", conn);
        break;
      case insole::Opcode::StopStream:
        Serial.printf("[ctl] conn %u: STOP_STREAM\n", conn);
        break;
      default:
        Serial.printf("[ctl] conn %u: opcode 0x%02x ignored (implemented in S2C)\n", conn, v[0]);
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

  static char cal[insole::kMaxCalibrationBytes + 1];
  size_t calLen = insole::buildCalibrationJson(cal, sizeof cal, config::kDeviceId, fsrCount);
  gCalibration->setValue(reinterpret_cast<const uint8_t*>(cal), calLen);

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

  Serial.printf("[ble] advertising as %s, fsr_count %u, calibration %u bytes\n",
                config::kDeviceName, fsrCount, static_cast<unsigned>(calLen));
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
  {
    Lock l;
    for (StreamSession& s : gSessions) {
      if (!s.inUse()) continue;
      Pending& p = pending[n];
      if (s.addSample(sample, tMs, gFsrCount, p.pkt) && s.sensorSubscribed) {
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
    Serial.printf("[sess] conn %u mtu %u %s sub[s%d t%d st%d] sent %lu mtu-drops %lu\n",
                  s.connHandle, s.mtu, s.streaming() ? "streaming" : "idle", s.sensorSubscribed,
                  s.temperatureSubscribed, s.statusSubscribed,
                  static_cast<unsigned long>(s.packetsSent),
                  static_cast<unsigned long>(s.samplesDroppedForMtu));
  }
  Serial.printf("[sess] %d connected, battery %u%%, notify failures %lu, heap %lu\n", active,
                gStatusValue.batteryPct, static_cast<unsigned long>(gNotifyFailures),
                static_cast<unsigned long>(ESP.getFreeHeap()));
}

}  // namespace ble
