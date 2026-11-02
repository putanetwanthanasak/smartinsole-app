#!/usr/bin/env bash
# Replays the simulator walk from before 2e2a326 (midfoot {0.40, 0.40, 860},
# peak ~18 kPa), whose summed kPa dips below steps.contactKpa between heel
# and forefoot (BACKLOG 51). Extracts that commit's insole_core sources from
# git into a temp dir, builds synth.cpp natively with dump_walk.cpp, and
# writes raw ADC / IMU samples for both feet to the app's test fixture.
# Usage: dump_presplit_walk.sh [commit] [duration_ms] [out.csv]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
commit="${1:-2e2a326^}"
duration="${2:-60000}"
out="${3:-$repo/mobile/test/fixtures/steps/presplit_walk.csv}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$repo" archive "$commit" firmware/simulator/lib/insole_core/src | tar -x -C "$tmp"
src="$tmp/firmware/simulator/lib/insole_core/src"
g++ -std=gnu++17 -O0 -I"$src" "$here/dump_walk.cpp" "$src/synth.cpp" -o "$tmp/dump_walk"
mkdir -p "$(dirname "$out")"
"$tmp/dump_walk" "$duration" > "$out"
echo "wrote $(($(wc -l < "$out") - 1)) samples from $commit to $out"
