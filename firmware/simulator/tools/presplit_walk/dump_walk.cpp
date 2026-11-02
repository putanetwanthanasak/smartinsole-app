// Dumps the simulator's walk as raw 50 Hz samples (CSV) for the app's
// step-detector replay tests (BACKLOG 51, S9). Built against the synth.cpp
// of a chosen commit by dump_presplit_walk.sh; never flashed.
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

#include "synth.h"

int main(int argc, char** argv) {
  const uint32_t durationMs = argc > 1 ? static_cast<uint32_t>(std::atoi(argv[1])) : 60000;
  const uint8_t fsrCount = 6;
  std::printf("t_ms,side,fsr0,fsr1,fsr2,fsr3,fsr4,fsr5,ax,ay,az,gx,gy,gz\n");
  for (uint8_t side : {0, 1}) {
    for (uint32_t t = 0; t < durationMs; t += 20) {
      insole::Sample s = insole::synth::gaitSample(t, side, fsrCount);
      std::printf("%u,%u", t, side);
      for (int c = 0; c < fsrCount; ++c) std::printf(",%u", s.fsr[c]);
      for (int i = 0; i < 3; ++i) std::printf(",%d", s.accel[i]);
      for (int i = 0; i < 3; ++i) std::printf(",%d", s.gyro[i]);
      std::printf("\n");
    }
  }
  return 0;
}
