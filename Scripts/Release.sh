#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples the app, then zips it.
# Requires a notarytool keychain profile (default: "notary"):
#   xcrun notarytool store-credentials "notary" --key AuthKey_XXXX.p8 --key-id XXXX --issuer <uuid>
# Usage: Scripts/Release.sh [output-dir]   (default: build/release)
set -euo pipefail

cd "${0:A:h}/.."

PROJECT="I am sure/I am sure.xcodeproj"
SCHEME="I am sure I want to open this App"
TEAM_ID="98DYJ8BJ46"
PROFILE="${NOTARY_PROFILE:-notary}"
OUT="${1:-build/release}"
APP_NAME="I am sure I want to open this App.app"

rm -rf "$OUT"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF

echo "==> Archive"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$WORK/App.xcarchive" archive -quiet

echo "==> Export (Developer ID)"
xcodebuild -exportArchive -archivePath "$WORK/App.xcarchive" \
  -exportOptionsPlist "$WORK/export.plist" -exportPath "$WORK/export" -quiet

APP="$WORK/export/$APP_NAME"
codesign --verify --deep --strict "$APP"

echo "==> Notarize"
ditto -c -k --keepParent "$APP" "$WORK/submit.zip"
xcrun notarytool submit "$WORK/submit.zip" --keychain-profile "$PROFILE" --wait

echo "==> Staple"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

echo "==> Package"
ditto "$APP" "$OUT/$APP_NAME"
ditto -c -k --keepParent "$OUT/$APP_NAME" "$OUT/I_am_sure_I_want_to_open_this_App.zip"
rm -rf "$OUT/$APP_NAME"

echo "Done: $OUT"
