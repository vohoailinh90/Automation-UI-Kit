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
SCREENS=(tokens components ledger-home ledger-entry ledger-report meds-today meds-caregiver
         cleaner-home cleaner-swipe cleaner-review cleaner-done cleaner-paywall onboarding permission paywall settings)
LARGE_TEXT_SCREENS=(ledger-home ledger-entry meds-today cleaner-home cleaner-review paywall)

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

shoot() {
  local name=$1
  shift
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "(vi)" -AppleLocale vi_VN "$@" >/dev/null
  # Long enough for sheets to finish presenting and charts to animate in.
  sleep "${SETTLE_SECONDS:-3}"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null
  echo "  $name"
}

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for screen in "${SCREENS[@]}"; do
    shoot "$screen.$appearance" -screen "$screen"
  done
done

xcrun simctl ui "$UDID" appearance light
xcrun simctl ui "$UDID" content_size accessibility-large
for screen in "${LARGE_TEXT_SCREENS[@]}"; do
  shoot "$screen.large-text" -screen "$screen"
done
xcrun simctl ui "$UDID" content_size large

echo "Wrote $(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ') screenshots to $OUT"
