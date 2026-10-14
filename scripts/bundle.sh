#!/bin/sh
# Builds a universal release Agry.app into build/, with Sparkle embedded.
# Signs ad hoc unless AGRY_SIGN_IDENTITY names a certificate, in which case it
# signs with the hardened runtime and a timestamp, ready for notarization.
set -eu
cd "$(dirname "$0")/.."
identity="${AGRY_SIGN_IDENTITY:--}"
version="$(cat VERSION)"
build="$(git rev-list --count HEAD)"
arch="--arch arm64 --arch x86_64"

swift build -c release --product Agry $arch
bin="$(swift build -c release $arch --show-bin-path)"
app=build/Agry.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/Agry" "$app/Contents/MacOS/Agry"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
# agry is not sandboxed, so Sparkle's XPC services are unused.
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$app/Contents/Frameworks/Sparkle.framework/XPCServices"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.agry</string>
  <key>CFBundleName</key><string>agry</string>
  <key>CFBundleExecutable</key><string>Agry</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>https://agry.dev/appcast.xml</string>
  <key>SUPublicEDKey</key><string>x2FUyFax0F13RcQETvpfOZ8tHFkAbh0GU1hCbd2vhT4=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>3600</integer>
</dict>
</plist>
PLIST

if [ "$identity" = "-" ]; then
    sign() { codesign --force --sign - "$@"; }
else
    sign() { codesign --force --timestamp --options runtime --sign "$identity" "$@"; }
fi
# Inside out, without --deep, as Sparkle's docs describe.
framework="$app/Contents/Frameworks/Sparkle.framework"
sign "$framework/Versions/B/Autoupdate"
sign "$framework/Versions/B/Updater.app"
sign "$framework"
sign "$app"
codesign --verify --strict --deep "$app"
echo "built $app $version ($build), signed: $identity"
