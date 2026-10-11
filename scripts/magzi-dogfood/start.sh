#!/bin/bash
# Local Magzi dogfood instance (never production): staging-active, stub WhatsApp
# (no real sends), isolated HOME (no access to your real Google/Magzi creds),
# mobile API on 127.0.0.1:8767, LLM via 9router.
#   scripts/magzi-dogfood/start.sh <magzid-binary> [dir]
# Then: python3 seed.py <dir>/state   (family + invites through the real API)
#       python3 chat.py Sara "what's on me this week?"
#       python3 otp.py <dir>/state sara@family.test   (after tapping "Send code" in the app)
set -euo pipefail
K=$(cd "$(dirname "$0")" && pwd)
BIN=$1; DIR=${2:-$HOME/magzi-dogfood}
mkdir -p "$DIR/state" "$DIR/ws" "$DIR/home" "$DIR/stub"
echo 'setInterval(()=>{},1e9)' > "$DIR/stub/bridge.js"   # no package.json: no npm install, no Baileys
sed "s|__DIR__|$DIR|g" "$K/config.template.json" > "$DIR/config.json"
if [ ! -f "$DIR/state/secrets.env" ]; then
  KEY=$(sed -n 's/^[[:space:]]*LOCAL_DEFAULT_PROVIDER_API_KEY[[:space:]]*=[[:space:]]*//p' "$K/../../src/ios/Configs/ProviderCustomization.xcconfig")
  umask 077; echo "MAGZI_9ROUTER_KEY=$KEY" > "$DIR/state/secrets.env"
fi
cd "$DIR" && HOME="$DIR/home" MAGZI_WA_SIDECAR="$DIR/stub/bridge.js" RUST_LOG=info exec "$BIN" --config "$DIR/config.json" start
