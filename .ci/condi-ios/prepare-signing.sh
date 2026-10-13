#!/usr/bin/env bash
set -euo pipefail
signing="$RUNNER_TEMP/condi-signing"
mkdir -p "$signing"
export CONDI_SIGNING_DIRECTORY="$signing"
python3 - <<'PY'
import os, base64, pathlib
root = pathlib.Path(os.environ["CONDI_SIGNING_DIRECTORY"])
for name, filename in [("IOS_DISTRIBUTION_P12_BASE64", "distribution.p12"), ("IOS_PROVISION_PROFILE_BASE64", "profile.mobileprovision")]:
    (root / filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
PY
keychain="$signing/condi.keychain-db"
keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing/distribution.p12" -k "$keychain" -P "${IOS_DISTRIBUTION_P12_PASSWORD:-}" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security cms -D -i "$signing/profile.mobileprovision" > "$signing/profile.plist"
python3 - <<'PY'
import os, pathlib, plistlib, re, datetime
root = pathlib.Path(os.environ["CONDI_SIGNING_DIRECTORY"])
with (root / "profile.plist").open("rb") as handle:
    profile = plistlib.load(handle)
team = os.environ["APPLE_TEAM_ID"]
if not re.fullmatch(r"[A-Z0-9]{10}", team) or team not in profile["TeamIdentifier"]:
    raise SystemExit("Apple team does not match the provisioning profile.")
app = profile["Entitlements"]["application-identifier"]
if not app.endswith(".ar.com.consultoradiagonales.condi"):
    raise SystemExit("Provisioning profile does not match the ConDi bundle identifier.")
expiry = profile.get("ExpirationDate")
if not expiry or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit("The provisioning profile has expired.")
if profile["Entitlements"].get("get-task-allow") or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
    raise SystemExit("ConDi requires an App Store distribution profile for this export mode.")
if any(character in profile["Name"] for character in "\r\n"):
    raise SystemExit("Invalid provisioning profile name.")
uuid = profile["UUID"]
if not re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid):
    raise SystemExit("Invalid provisioning profile UUID.")
aps = profile["Entitlements"].get("aps-environment")
if aps != "production":
    raise SystemExit("The App Store profile must enable production Push Notifications for ConDi.")
for directory in [pathlib.Path.home()/"Library/MobileDevice/Provisioning Profiles", pathlib.Path.home()/"Library/Developer/Xcode/UserData/Provisioning Profiles"]:
    directory.mkdir(parents=True, exist_ok=True)
    (directory/f"{uuid}.mobileprovision").write_bytes((root/"profile.mobileprovision").read_bytes())
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
    output.write(f"IOS_PROFILE_NAME={profile['Name']}\nIOS_APS_ENVIRONMENT={aps}\n")
PY
