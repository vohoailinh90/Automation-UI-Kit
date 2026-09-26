#!/usr/bin/env bash
# Screenshots every demo screen on an iPhone simulator: light and dark, plus a
# large-text pass on the screens most likely to break. Needs Xcode (macOS).
#
#   ios/scripts/render-previews.sh [output-dir]      # default: ios/previews
#
# Used by .github/workflows/ios-previews.yml; runs the same way on a Mac.
set -euo pipefail

cd "$(dirname "$0")/../.."
OUT="${1:-ios/previews}"
DERIVED="${DERIVED_DATA:-build/DerivedData}"
BUNDLE_ID="dev.idealab.demo"
# The ids of DemoScreen in ios/IdeaLabDemo/IdeaLabDemo/DemoScreens.swift.
SCREENS=(tokens components ledger-home ledger-entry ledger-report meds-today meds-caregiver meds-add
         cleaner-home cleaner-swipe cleaner-review cleaner-done cleaner-paywall onboarding permission paywall settings)
LARGE_TEXT_SCREENS=(ledger-home ledger-entry meds-today meds-add cleaner-home cleaner-review paywall)
# Long forms, also shot at their end (`-scroll bottom`, as <id>.end.*.png): the
# cards the first screenful does not reach.
LONG_SCREENS=(meds-add)

mkdir -p "$OUT"

# The newest iPhone Pro this Xcode ships, else any available iPhone.
UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
phones = [d for runtime, devices in sorted(runtimes.items(), reverse=True) if ".iOS-" in runtime
          for d in devices if d["name"].startswith("iPhone")]
if not phones:
    sys.exit("no iPhone simulator available")
for name in ("iPhone 17 Pro", "iPhone 16 Pro"):
    match = [d for d in phones if d["name"] == name]
    if match:
        print(match[0]["udid"])
        break
else:
    print(phones[0]["udid"])
')
echo "Simulator: $(xcrun simctl list devices | grep "$UDID")"

xcodebuild build \
  -project ios/IdeaLabDemo/IdeaLabDemo.xcodeproj \
  -scheme IdeaLabDemo \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# Apple's marketing status bar: 9:41, full signal, full battery.
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/IdeaLabDemo.app"

PROBE_DIR=$(mktemp -d)
trap 'rm -rf "$PROBE_DIR"' EXIT

snap() {
  xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null
}

# Whether a screenshot shows the app rather than its blank launch screen: more
# than a few colours below the status bar. sips ships with macOS, and a BMP 40
# pixels wide is small enough to read in Python.
drawn() {
  sips -s format bmp --resampleWidth 40 "$1" --out "$PROBE_DIR/probe.bmp" >/dev/null
  python3 - "$PROBE_DIR/probe.bmp" <<'PY'
import struct, sys
bmp = open(sys.argv[1], "rb").read()
start, = struct.unpack_from("<I", bmp, 10)
width, height = struct.unpack_from("<ii", bmp, 18)
depth = struct.unpack_from("<H", bmp, 28)[0] // 8
stride = (width * depth + 3) // 4 * 4
rows = abs(height)
colours = set()
for row in range(rows):
    from_top = rows - 1 - row if height > 0 else row  # a positive height: bottom-up
    if from_top < rows // 10:  # the status bar
        continue
    line = bmp[start + row * stride:start + row * stride + width * depth]
    colours.update(line[x:x + 3] for x in range(0, len(line), depth))
sys.exit(0 if len(colours) > 3 else 1)
PY
}

shoot() {
  local name=$1 waited=0
  shift
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "(vi)" -AppleLocale vi_VN "$@" >/dev/null
  # Long enough for sheets to finish presenting and charts to animate in.
  sleep "${SETTLE_SECONDS:-3}"
  snap "$OUT/$name.png"
  # A slow simulator can still be on the blank launch screen by then. Wait for
  # the app's first frame, then as long again, rather than publish a blank.
  if ! drawn "$OUT/$name.png"; then
    until drawn "$OUT/$name.png"; do
      if [ "$waited" -ge 60 ]; then
        echo "$name: the app drew nothing for a minute" >&2
        exit 1
      fi
      sleep 1
      waited=$((waited + 1))
      snap "$OUT/$name.png"
    done
    sleep "${SETTLE_SECONDS:-3}"
    snap "$OUT/$name.png"
    echo "  $name (first frame after $((${SETTLE_SECONDS:-3} + waited)) s)"
    return
  fi
  echo "  $name"
}

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for screen in "${SCREENS[@]}"; do
    shoot "$screen.$appearance" -screen "$screen"
  done
done

xcrun simctl ui "$UDID" appearance light
for screen in "${LONG_SCREENS[@]}"; do
  shoot "$screen.end.light" -screen "$screen" -scroll bottom
done

xcrun simctl ui "$UDID" content_size accessibility-large
for screen in "${LARGE_TEXT_SCREENS[@]}"; do
  shoot "$screen.large-text" -screen "$screen"
done
for screen in "${LONG_SCREENS[@]}"; do
  shoot "$screen.end.large-text" -screen "$screen" -scroll bottom
done
xcrun simctl ui "$UDID" content_size large

echo "Wrote $(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ') screenshots to $OUT"
