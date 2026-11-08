#!/usr/bin/env bash
# Builds a signed, notarized Lampo release: zip, Sparkle appcast and Homebrew cask.
#
#   scripts/release.sh                     full release (needs Packaging/release.env)
#   scripts/release.sh --skip-notarize     sign and package only (local check, nothing is uploaded)
#   scripts/release.sh --skip-appcast      no Sparkle appcast (e.g. no feed configured yet)
#
# One-time setup (see README › Releasing):
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. xcrun notarytool store-credentials lampo-notary --apple-id … --team-id 9K3LNS3KHP
#   3. build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys   (prints the public key)
#   4. cp Packaging/release.env.example Packaging/release.env and fill it in.
#
# The version is MARKETING_VERSION in project.yml; the build number is the commit count,
# so every release has a higher CFBundleVersion (Sparkle compares it).
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_NOTARIZE=0
SKIP_APPCAST=0
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --skip-appcast) SKIP_APPCAST=1 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

LAMPO_FEED_URL="" LAMPO_DOWNLOAD_URL_PREFIX="" LAMPO_SPARKLE_PUBLIC_KEY=""
LAMPO_WEBSITE_URL="" LAMPO_REPOSITORY_URL="" NOTARY_PROFILE="lampo-notary"
if [[ -f Packaging/release.env ]]; then
    # shellcheck disable=SC1091
    source Packaging/release.env
fi

VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
BUILD=$(git rev-list --count HEAD)
[[ -n "$VERSION" ]] || fail "MARKETING_VERSION not found in project.yml"

if [[ $SKIP_APPCAST -eq 0 ]]; then
    [[ "$LAMPO_FEED_URL" == https://* ]] || fail "LAMPO_FEED_URL must be an https URL (Packaging/release.env), or pass --skip-appcast"
    [[ "$LAMPO_DOWNLOAD_URL_PREFIX" == https://* ]] || fail "LAMPO_DOWNLOAD_URL_PREFIX must be an https URL"
    [[ -n "$LAMPO_SPARKLE_PUBLIC_KEY" ]] || fail "LAMPO_SPARKLE_PUBLIC_KEY is empty (run generate_keys)"
fi
if [[ $SKIP_NOTARIZE -eq 0 && -n "$(git status --porcelain)" ]]; then
    fail "uncommitted changes: commit before a real release (or use --skip-notarize for a local check)"
fi

OUT="build/release/$VERSION"
ARCHIVE="$OUT/Lampo.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Lampo.app"
ZIP="$OUT/Lampo-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"

step "Lampo $VERSION ($BUILD)"
xcodegen generate --quiet

step "Tests"
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData \
    -clonedSourcePackagesDirPath build/SourcePackages test -quiet

step "Archive (Release, Developer ID)"
xcodebuild -project Lampo.xcodeproj -scheme Lampo -configuration Release \
    -derivedDataPath build/DerivedDataRelease -clonedSourcePackagesDirPath build/SourcePackages \
    -archivePath "$ARCHIVE" archive -quiet \
    CURRENT_PROJECT_VERSION="$BUILD" \
    LAMPO_FEED_URL="$LAMPO_FEED_URL" \
    LAMPO_SPARKLE_PUBLIC_KEY="$LAMPO_SPARKLE_PUBLIC_KEY" \
    LAMPO_WEBSITE_URL="$LAMPO_WEBSITE_URL" \
    LAMPO_REPOSITORY_URL="$LAMPO_REPOSITORY_URL"

step "Export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Packaging/ExportOptions.plist \
    -exportPath "$EXPORT" -quiet

step "Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
# Captured first: `grep -q` closing the pipe early would trip `pipefail`.
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
grep -E "^Authority=Developer ID Application|^TeamIdentifier|^Runtime Version" <<<"$SIGNATURE" || true
grep -q "^Authority=Developer ID Application" <<<"$SIGNATURE" || fail "not signed with Developer ID"
grep -q "flags=.*runtime" <<<"$SIGNATURE" || fail "Hardened Runtime is off"
if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
    fail "the app has get-task-allow (debug entitlement)"
fi
grep -q "personal-information.calendars" <<<"$ENTITLEMENTS" || fail "calendars entitlement missing"
grep -q "device.audio-input" <<<"$ENTITLEMENTS" || fail "microphone entitlement missing"

package() {
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
}
package

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    step "Notarize (uploads $ZIP to Apple's notary service)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    package
else
    step "Notarization skipped (--skip-notarize): this build is NOT for distribution"
fi

SHA256=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')

if [[ $SKIP_APPCAST -eq 0 ]]; then
    step "Sparkle appcast"
    APPCAST_DIR="$OUT/appcast"
    mkdir -p "$APPCAST_DIR"
    cp "$ZIP" "$APPCAST_DIR/"
    # Start from the published feed so older entries are kept.
    curl -fsSL "$LAMPO_FEED_URL" -o "$APPCAST_DIR/appcast.xml" || echo "No published appcast yet: starting a new one."
    if [[ -f "Packaging/ReleaseNotes/$VERSION.html" ]]; then
        cp "Packaging/ReleaseNotes/$VERSION.html" "$APPCAST_DIR/Lampo-$VERSION.html"
    fi
    # Signs the zip with the EdDSA private key from the login keychain.
    build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
        --download-url-prefix "$LAMPO_DOWNLOAD_URL_PREFIX/v$VERSION/" "$APPCAST_DIR"
    cp "$APPCAST_DIR/appcast.xml" "$OUT/appcast.xml"
fi

step "Homebrew cask"
HOMEPAGE="${LAMPO_WEBSITE_URL:-$LAMPO_REPOSITORY_URL}"
CASK_URL="${LAMPO_DOWNLOAD_URL_PREFIX:-https://example.invalid}/v#{version}/Lampo-#{version}.zip"
sed -e "s|__VERSION__|$VERSION|" -e "s|__SHA256__|$SHA256|" -e "s|__URL__|$CASK_URL|" \
    -e "s|__HOMEPAGE__|${HOMEPAGE:-https://example.invalid}|" -e "s|__FEED_URL__|${LAMPO_FEED_URL:-https://example.invalid}|" \
    Packaging/Homebrew/lampo.rb.template > "$OUT/lampo.rb"
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    cp "$OUT/lampo.rb" Packaging/Homebrew/lampo.rb
fi

step "Done"
echo "  App:      $APP"
echo "  Zip:      $ZIP"
echo "  SHA-256:  $SHA256"
[[ $SKIP_APPCAST -eq 0 ]] && echo "  Appcast:  $OUT/appcast.xml"
echo "  Cask:     $OUT/lampo.rb"
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    cat <<EOF

Next steps (by hand):
  1. Upload $ZIP to $LAMPO_DOWNLOAD_URL_PREFIX/v$VERSION/
  2. Upload $OUT/appcast.xml to $LAMPO_FEED_URL
  3. git tag v$VERSION && git push --tags
  4. Commit Packaging/Homebrew/lampo.rb and copy it to your tap (Casks/lampo.rb).
EOF
fi
