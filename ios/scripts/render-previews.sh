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
SCREENS=(tokens components ledger-home ledger-entry ledger-report ledger-export-pdf ledger-export-xlsx meds-today
         meds-assistive meds-caregiver meds-add meds-edit meds-alerts cleaner-home cleaner-swipe cleaner-review
         cleaner-similar cleaner-done cleaner-paywall cleaner-library cleaner-measured cleaner-measured-home onboarding
         permission paywall paywall-subscriber paywall-billing-issue paywall-billing-legacy paywall-win-back settings
         settings-billing-issue)
LARGE_TEXT_SCREENS=(ledger-home ledger-entry meds-today meds-assistive meds-add meds-edit meds-alerts cleaner-home
                    cleaner-review cleaner-similar paywall paywall-subscriber paywall-billing-issue paywall-billing-legacy
                    paywall-win-back settings-billing-issue)
# Long screens, also shot at their end (`-scroll bottom`, as <id>.end.*.png):
# the cards the first screenful does not reach, such as the family's list of
# medicines, the edit form's "Ngừng thuốc", the last similar photos, the
# categories Vision found in the samples, the plan whose renewal failed, or
# the plan with an offer to come back.
LONG_SCREENS=(meds-caregiver meds-add meds-edit cleaner-similar cleaner-measured-home paywall-billing-issue
              paywall-win-back)

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
# The demo creates this file once the screen to shoot has appeared
# (DemoLaunch.markReady in ios/IdeaLabDemo/IdeaLabDemo/IdeaLabDemoApp.swift).
READY="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Library/Caches/demo-ready"

PROBE_DIR=$(mktemp -d)
trap 'rm -rf "$PROBE_DIR"' EXIT

snap() {
  xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null
}

# A screenshot shrunk to a BMP 120 pixels wide ($2): small enough to read in
# Python, and, unlike the PNG, nothing but pixels, so two probes of the same
# screen are the same bytes. sips ships with macOS. The old probe goes first,
# and a failed conversion stops the script, so an earlier shot's probe can
# never stand in for this one.
probe() {
  rm -f "$2"
  if ! sips -s format bmp --resampleWidth 120 "$1" --out "$2" >/dev/null; then
    echo "sips could not shrink $1" >&2
    exit 1
  fi
}

# Whether a probe shows the app rather than a blank frame: more than a few
# colours between the status bar and the home indicator. Both show on a blank
# frame, and the indicator's anti-aliased edge alone brings more than three
# colours: counted, it passed a black frame for a drawn one. It runs as a
# condition, where `set -e` does not reach, so a probe it cannot read stops the
# script here instead of passing for a blank frame or a drawn one.
drawn() {
  local status=0
  python3 - "$1" <<'PY' || status=$?
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
    if from_top < rows // 10 or from_top >= rows - rows // 20:  # the status bar, the home indicator
        continue
    line = bmp[start + row * stride:start + row * stride + width * depth]
    colours.update(line[x:x + 3] for x in range(0, len(line), depth))
sys.exit(0 if len(colours) > 3 else 3)  # 3: blank; 1 would be a Python error
PY
  case $status in
    0) return 0 ;;
    3) return 1 ;;
    *)
      echo "could not read the probe of $1" >&2
      exit 1
      ;;
  esac
}

shoot() {
  local name=$1 waited=0
  shift
  rm -f "$READY"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "(vi)" -AppleLocale vi_VN "$@" >/dev/null
  # Wait for the demo to say the screen to shoot has appeared: for a screen
  # that opens a sheet, the sheet. A slow simulator can show its blank launch
  # screen for a while, or the screen under a sheet before the sheet.
  until [ -f "$READY" ]; do
    if [ "$waited" -ge 60 ]; then
      echo "$name: the demo did not say it was ready in a minute" >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # Then time for a sheet to finish presenting and charts to animate in, and a
  # shot every second until the screen stands still: two shots in a row alike,
  # showing the app.
  sleep "${SETTLE_SECONDS:-2}"
  snap "$OUT/$name.png"
  probe "$OUT/$name.png" "$PROBE_DIR/now.bmp"
  waited=0
  while :; do
    mv "$PROBE_DIR/now.bmp" "$PROBE_DIR/before.bmp"
    sleep 1
    waited=$((waited + 1))
    snap "$OUT/$name.png"
    probe "$OUT/$name.png" "$PROBE_DIR/now.bmp"
    if cmp -s "$PROBE_DIR/before.bmp" "$PROBE_DIR/now.bmp" && drawn "$PROBE_DIR/now.bmp"; then
      break
    fi
    if [ "$waited" -ge 60 ]; then
      echo "$name: no still frame of the app in a minute" >&2
      exit 1
    fi
  done
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
