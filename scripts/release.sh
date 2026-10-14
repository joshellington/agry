#!/bin/sh
# Publishes a signed, notarized build to agry.dev: the DMG at /download/agry.dmg
# (plus a versioned copy) and a Sparkle feed at /appcast.xml that installed
# copies check for updates.
#
# One-time setup on the releasing Mac:
#   - a "Developer ID Application" certificate in the login keychain
#   - notarytool credentials: xcrun notarytool store-credentials agry-notary ...
#   - the Sparkle signing key: .build/sparkle/bin/generate_keys --account agry
# Pass --skip-notarize to stop after building and signing the DMG.
set -eu
cd "$(dirname "$0")/.."

notarize=true
[ "${1:-}" = "--skip-notarize" ] && notarize=false

identity="${AGRY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$identity" ]; then
    echo "No Developer ID Application certificate in the keychain." >&2
    exit 1
fi
# The build number is the commit count, so a release must match a commit.
if ! git diff --quiet HEAD -- Sources Package.swift Package.resolved VERSION scripts; then
    echo "Commit your changes first; the build number comes from the commit count." >&2
    exit 1
fi

sparkle=.build/sparkle
if [ ! -x "$sparkle/bin/sign_update" ]; then
    mkdir -p "$sparkle"
    curl -sSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
        | tar -xJ -C "$sparkle"
fi

AGRY_SIGN_IDENTITY="$identity" scripts/bundle.sh
version="$(cat VERSION)"
build="$(git rev-list --count HEAD)"

dmg="build/agry-$version-$build.dmg"
staging=build/dmg
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto build/Agry.app "$staging/Agry.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname agry -srcfolder "$staging" -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

if ! $notarize; then
    echo "built and signed $dmg (not notarized, not published)"
    exit 0
fi
xcrun notarytool submit "$dmg" --keychain-profile agry-notary --wait
xcrun stapler staple "$dmg"

# sign_update prints: sparkle:edSignature="…" length="…"
attributes="$("$sparkle/bin/sign_update" --account agry "$dmg")"
downloads=site/public/download
mkdir -p "$downloads"
cp "$dmg" "$downloads/agry-$version-$build.dmg"
cp "$dmg" "$downloads/agry.dmg"
cat > site/public/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>agry</title>
    <item>
      <title>agry $version ($build)</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0.0</sparkle:minimumSystemVersion>
      <enclosure url="https://agry.dev/download/agry-$version-$build.dmg" $attributes type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
(cd site && npx cf deploy)
echo "published agry $version ($build): https://agry.dev/download/agry.dmg"
