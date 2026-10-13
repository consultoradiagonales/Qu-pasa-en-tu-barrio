#!/usr/bin/env bash
set -euo pipefail
project="${1:?project directory required}"
mode="${2:-simulator}"
[[ "$(uname -s)" == Darwin ]] || { echo 'iOS requires macOS and Xcode.' >&2; exit 1; }
cd "$project"
export PUB_CACHE="${PUB_CACHE:-$project/.condi-dev/pub-cache}"
export TMPDIR="$project/.condi-dev/tmp"
mkdir -p "$PUB_CACHE" "$TMPDIR"
flutter config --no-enable-swift-package-manager
flutter pub get --enforce-lockfile
case "$mode" in
  simulator)
    flutter test --no-pub --reporter expanded
    flutter build ios --simulator --debug --no-pub --no-codesign
    ditto -c -k --sequesterRsrc --keepParent build/ios/iphonesimulator/Runner.app build/ios/ConDi-simulator.zip
    ;;
  unsigned-device)
    flutter build ios --release --no-pub --no-codesign
    ditto -c -k --sequesterRsrc --keepParent build/ios/iphoneos/Runner.app build/ios/ConDi-device-unsigned.zip
    ;;
  ipa)
    [[ -n "${APPLE_TEAM_ID:-}" && -n "${IOS_PROFILE_NAME:-}" ]] || { echo 'Apple signing configuration is missing.' >&2; exit 1; }
    export CONDI_EXPORT_METHOD="${CONDI_EXPORT_METHOD:-app-store-connect}"
    ruby -rxcodeproj -e '
      project = Xcodeproj::Project.open("ios/Runner.xcodeproj")
      runner = project.targets.find { |target| target.name == "Runner" }
      abort "Runner target missing" unless runner
      runner.build_configurations.each do |config|
        config.build_settings["DEVELOPMENT_TEAM"] = ENV.fetch("APPLE_TEAM_ID")
        config.build_settings["CODE_SIGN_STYLE"] = "Manual"
        config.build_settings["CODE_SIGN_IDENTITY"] = "Apple Distribution"
        config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = ENV.fetch("IOS_PROFILE_NAME")
        config.build_settings["APS_ENVIRONMENT"] = ENV.fetch("IOS_APS_ENVIRONMENT", "production")
      end
      project.save
    '
    python3 - <<'PY'
import os, plistlib
options = {
  "method": os.environ["CONDI_EXPORT_METHOD"],
  "teamID": os.environ["APPLE_TEAM_ID"],
  "signingStyle": "manual",
  "signingCertificate": "Apple Distribution",
  "provisioningProfiles": {"ar.com.consultoradiagonales.condi": os.environ["IOS_PROFILE_NAME"]},
  "manageAppVersionAndBuildNumber": False,
}
with open("ios/ExportOptions.ci.plist", "wb") as output:
    plistlib.dump(options, output)
PY
    flutter build ipa --release --no-pub --export-options-plist=ios/ExportOptions.ci.plist
    ;;
  *) echo "Unsupported build mode: $mode" >&2; exit 1 ;;
esac
