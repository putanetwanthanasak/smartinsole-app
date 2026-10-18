#include "control.h"

#include "protocol.h"

namespace insole {

Command parseControl(const uint8_t* data, size_t len) {
  Command c{CommandKind::Malformed, 0, 0, 0};
  if (len == 0) return c;
  c.opcode = data[0];

  // Expected total length (opcode + payload) for each known opcode.
  CommandKind kind;
  size_t want;
  switch (static_cast<Opcode>(data[0])) {
    case Opcode::StartStream: kind = CommandKind::Start, want = 1; break;
    case Opcode::StopStream: kind = CommandKind::Stop, want = 1; break;
    case Opcode::SyncTime: kind = CommandKind::SyncTime, want = 9; break;
    case Opcode::SetRate: kind = CommandKind::SetRate, want = 2; break;
    case Opcode::Tare: kind = CommandKind::Tare, want = 1; break;
    case Opcode::Reboot: kind = CommandKind::Reboot, want = 1; break;
    default:
      c.kind = CommandKind::Unknown;
      return c;
  }
  if (len != want) return c;  // Malformed

  c.kind = kind;
  if (kind == CommandKind::SyncTime)
    for (int i = 7; i >= 0; --i) c.unixMs = c.unixMs << 8 | data[1 + i];  // little-endian
  if (kind == CommandKind::SetRate) c.rateHz = data[1];
  return c;
}

const char* commandName(CommandKind kind) {
  switch (kind) {
    case CommandKind::Start: return "START_STREAM";
    case CommandKind::Stop: return "STOP_STREAM";
    case CommandKind::SyncTime: return "SYNC_TIME";
    case CommandKind::SetRate: return "SET_RATE";
    case CommandKind::Tare: return "TARE";
    case CommandKind::Reboot: return "REBOOT";
    case CommandKind::Malformed: return "malformed";
    case CommandKind::Unknown: return "unknown";
  }
  return "?";
}

}  // namespace insole
