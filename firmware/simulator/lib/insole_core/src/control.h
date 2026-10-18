// Control characteristic writes (Data Contract §3.4), parsed into a command.
// Every opcode has one exact length; anything else is Malformed and must not
// change any state. Opcodes the contract doesn't define (including 0x10
// SET_SCENARIO, BACKLOG 18) are Unknown and ignored the same way.
#pragma once

#include <cstddef>
#include <cstdint>

namespace insole {

enum class CommandKind : uint8_t {
  Start,
  Stop,
  SyncTime,
  SetRate,
  Tare,
  Reboot,
  Malformed,  // known opcode, wrong payload length
  Unknown,    // opcode not in the contract
};

struct Command {
  CommandKind kind;
  uint8_t opcode;   // the raw first byte, for the log (0 if the write was empty)
  uint64_t unixMs;  // SyncTime only
  uint8_t rateHz;   // SetRate only
};

// SET_RATE only accepts the contract's fixed 50 Hz: rule 1 (sample i =
// t0 + i * 20 ms) has no way to tell the app about another spacing.
constexpr uint8_t kSupportedRateHz = 50;

Command parseControl(const uint8_t* data, size_t len);

const char* commandName(CommandKind kind);

}  // namespace insole
