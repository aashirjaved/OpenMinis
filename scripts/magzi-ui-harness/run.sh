#!/bin/bash
# Renders the Magzi UI (src/ios/Magzi/**) in the iOS Simulator against a contract-shaped mock
# server, without the heavy native deps the full app needs. Screenshots land in $OUT.
#   scripts/magzi-ui-harness/run.sh [device-udid]
# Tabs: MAGZI_TAB=home|magzi|household|adhoc|more  Screens: MAGZI_SCREEN=capabilities|me|admin|ops|bridge
# bridge runs the real Ad-hoc→Magzi bridge tools (needs a signed-in session against a real magzid).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); H="$ROOT/scripts/magzi-ui-harness"
OUT=${OUT:-$(mktemp -d)}; D=${1:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;print([d["udid"] for r in json.load(sys.stdin)["devices"].values() for d in r][0])')}
A="$OUT/MagziHarness.app"; mkdir -p "$A"
cp "$H/HarnessStubs.swift.txt" "$OUT/HarnessStubs.swift"
cd "$ROOT/src/ios"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -Onone -swift-version 5 -parse-as-library -target arm64-apple-ios17.0-simulator -sdk "$SDK" \
  $(find Magzi -name '*.swift' ! -name 'AIChatViewModel+MagziRemote.swift' ! -name MagziGatewaySettings.swift ! -name MagziSettingsView.swift) \
  Shared/AppLogger.swift "$OUT/HarnessStubs.swift" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$H/entitlements.plist" -o "$A/MagziHarness"
plutil -create xml1 "$A/Info.plist"
for kv in CFBundleIdentifier=com.aashirjaved.magzi.harness CFBundleExecutable=MagziHarness CFBundleName=Magzi CFBundlePackageType=APPL CFBundleVersion=1 MinimumOSVersion=17.0; do
  plutil -insert "${kv%%=*}" -string "${kv#*=}" "$A/Info.plist"; done
plutil -insert UILaunchScreen -dictionary "$A/Info.plist"
plutil -insert NSAppTransportSecurity -json '{"NSAllowsArbitraryLoads":true}' "$A/Info.plist"
codesign -f -s - "$A"
python3 -I "$H/mock_magzi.py" & MOCK=$!; trap 'kill $MOCK' EXIT
xcrun simctl install "$D" "$A"
for t in home magzi household adhoc more; do
  xcrun simctl terminate "$D" com.aashirjaved.magzi.harness 2>/dev/null || true
  SIMCTL_CHILD_MAGZI_MOCK=1 SIMCTL_CHILD_MAGZI_TAB=$t xcrun simctl launch "$D" com.aashirjaved.magzi.harness >/dev/null
  sleep 6; xcrun simctl io "$D" screenshot "$OUT/$t.png" >/dev/null
done
echo "screenshots: $OUT"
