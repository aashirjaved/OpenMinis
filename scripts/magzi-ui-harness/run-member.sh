#!/bin/bash
# Run the Magzi UI harness as one household member against the LOCAL dogfood daemon
# (scripts/magzi-dogfood). One bundle per member keeps their sessions apart.
#   run-member.sh <member> [tab] [screen]        member = aashir|sara|zain|aliya (email <member>@family.test)
#   HH=items|rota|meals|bills|approvals|reality|thread|facts|activity|summary|members   pushes that Household screen
#   SEND="text"            sends it in Magzi chat after launch
#   CC=<code>              logs the Ops cockpit in (code from `cockpit-code.sh`)
#   DOGFOOD=<dir>          the dogfood dir (default ~/magzi-dogfood), SIM=<udid> (default: first booted)
#   BIN=<path>             a prebuilt harness binary (default: build one now)
# Screenshots: xcrun simctl io <udid> screenshot out.png
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); H="$ROOT/scripts/magzi-ui-harness"
M=$1; TAB=${2:-home}; SCREEN=${3:-}
DOGFOOD=${DOGFOOD:-$HOME/magzi-dogfood}; STATE="$DOGFOOD/state"
D=${SIM:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;print([d["udid"] for r in json.load(sys.stdin)["devices"].values() for d in r][0])')}
OUT=${OUT:-/tmp/magzi-harness}; mkdir -p "$OUT"
if [ -z "${BIN:-}" ]; then
  cp "$H/HarnessStubs.swift.txt" "$OUT/HarnessStubs.swift"
  cd "$ROOT/src/ios"; SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  xcrun --sdk iphonesimulator swiftc -Onone -swift-version 5 -parse-as-library -target arm64-apple-ios17.0-simulator -sdk "$SDK" \
    $(find Magzi -name '*.swift' ! -name 'AIChatViewModel+MagziRemote.swift' ! -name MagziGatewaySettings.swift ! -name MagziSettingsView.swift) \
    Shared/AppLogger.swift "$OUT/HarnessStubs.swift" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$H/entitlements.plist" -o "$OUT/MagziHarness"
  BIN="$OUT/MagziHarness"
fi
BID=com.aashirjaved.magzi.harness.$M; A="$OUT/$M.app"; EMAIL="$M@family.test"
mkdir -p "$A"; cp "$BIN" "$A/MagziHarness"
plutil -create xml1 "$A/Info.plist"
for kv in CFBundleIdentifier=$BID CFBundleExecutable=MagziHarness CFBundleName=Magzi-$M CFBundlePackageType=APPL CFBundleVersion=1 MinimumOSVersion=17.0; do
  plutil -insert "${kv%%=*}" -string "${kv#*=}" "$A/Info.plist"; done
plutil -insert UILaunchScreen -dictionary "$A/Info.plist"
plutil -insert NSAppTransportSecurity -json '{"NSAllowsArbitraryLoads":true}' "$A/Info.plist"
codesign -f -s - "$A" 2>/dev/null
xcrun simctl terminate "$D" $BID 2>/dev/null || true
xcrun simctl install "$D" "$A"
python3 -I "$ROOT/scripts/magzi-dogfood/otp.py" "$STATE" "$EMAIL" >/dev/null
export SIMCTL_CHILD_MAGZI_LOGIN_EMAIL="$EMAIL" SIMCTL_CHILD_MAGZI_TAB="$TAB"
[ -n "$SCREEN" ] && export SIMCTL_CHILD_MAGZI_SCREEN="$SCREEN"
[ -n "${HH:-}" ] && export SIMCTL_CHILD_MAGZI_HH="$HH"
[ -n "${CC:-}" ] && export SIMCTL_CHILD_MAGZI_COCKPIT_CODE="$CC"
[ -n "${SEND:-}" ] && export SIMCTL_CHILD_MAGZI_AUTOSEND="$SEND"
xcrun simctl launch "$D" $BID >/dev/null
echo "launched $BID as $M tab=$TAB screen=$SCREEN hh=${HH:-}"
