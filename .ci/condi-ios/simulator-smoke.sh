#!/usr/bin/env bash
set -euo pipefail
project="${1:?project required}"
udid="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[v for values in d["devices"].values() for v in values if v.get("isAvailable") and v["name"].startswith("iPhone")]; assert phones, "No iPhone simulator available"; print(phones[0]["udid"])')"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$project/build/ios/iphonesimulator/Runner.app"
xcrun simctl launch --terminate-running-process "$udid" ar.com.consultoradiagonales.condi
sleep 12
xcrun simctl io "$udid" screenshot "$project/build/ios/ConDi-iOS-startup.png"
xcrun simctl spawn "$udid" launchctl list | grep -F ar.com.consultoradiagonales.condi >/dev/null
xcrun simctl spawn "$udid" log show --last 2m --style compact --predicate 'process == "Runner"' > "$project/build/ios/simulator-startup.log"
if grep -E 'Unhandled Exception|EXC_BAD_ACCESS|Terminating app due to uncaught exception' "$project/build/ios/simulator-startup.log"; then
  echo 'iOS startup reported a runtime failure.' >&2
  exit 1
fi
