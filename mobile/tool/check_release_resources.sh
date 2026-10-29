#!/usr/bin/env bash
# Fails if a release APK lacks any resource the app looks up by name at
# runtime. Those are listed in android/app/src/main/res/raw/keep.xml
# (tools:keep); test/notify/android_resources_test.dart checks that every
# name in lib/notify/android_resources.dart is listed there. The release
# build's resource shrinker drops unreferenced resources, which debug
# builds keep, so only a release APK shows the problem (S8C).
#
# Usage (in mobile/): tool/check_release_resources.sh [apk]
# Run after every `flutter build apk --release`.
set -euo pipefail

cd "$(dirname "$0")/.."
apk="${1:-build/app/outputs/flutter-apk/app-release.apk}"
keep=android/app/src/main/res/raw/keep.xml

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
aapt2="$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
[[ -x "$aapt2" ]] || { echo "aapt2 not found under $sdk/build-tools" >&2; exit 2; }
[[ -f "$apk" ]] || { echo "APK not found: $apk" >&2; exit 2; }

# "@drawable/a,@raw/b" -> "drawable/a" "raw/b"
mapfile -t wanted < <(grep -o 'tools:keep="[^"]*"' "$keep" | cut -d'"' -f2 |
  tr ',' '\n' | sed 's/^ *@//; s/ *$//' | grep -v '^$')
[[ ${#wanted[@]} -gt 0 ]] || { echo "no tools:keep entries in $keep" >&2; exit 2; }

have="$("$aapt2" dump resources "$apk" | awk '/^ *resource 0x/ {print $3}')"
missing=0
for r in "${wanted[@]}"; do
  if grep -qx "$r" <<<"$have"; then
    echo "ok       $r"
  else
    echo "MISSING  $r" >&2
    missing=1
  fi
done
if [[ $missing -ne 0 ]]; then
  echo "release APK lacks runtime resources: $apk" >&2
  exit 1
fi
echo "all ${#wanted[@]} runtime resources present in $apk"
