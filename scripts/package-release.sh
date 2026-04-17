#!/usr/bin/env bash
#
# Build + sign + notarize + staple + package Lisan for release.
#
# The critical thing this script gets right that ad-hoc CLI commands get
# wrong: `ditto -c -k --sequesterRsrc --keepParent` — without
# `--sequesterRsrc`, AppleDouble xattr metadata gets embedded as `._*`
# files INSIDE the bundle on unzip, which breaks
# `codesign --verify --deep --strict` on end-user machines. That's what
# happened to the initial v0.2.1 asset and is documented in the v0.2.2 fix.
#
# Prereqs (one-time):
#   1. Developer ID Application cert installed in login keychain
#   2. Notarization creds stored via:
#        xcrun notarytool store-credentials "lisan-notary" \
#          --apple-id <email> --team-id VSL9H2F2D3 --password <app-specific>
#   3. whisper.cpp built at ~/vendor/whisper.cpp with ggml-base.bin and
#      ggml-silero-v6.2.0.bin models
#
# Usage:
#   ./scripts/package-release.sh 0.2.2
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>  (e.g. 0.2.2)" >&2
  exit 1
fi

SIGNING_IDENTITY="Developer ID Application: MOUSA AHMAD MOUSA ABUMAZIN (VSL9H2F2D3)"
NOTARY_PROFILE="lisan-notary"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
STAGE_DIR="$REPO_DIR/release-stage/Lisan-v${VERSION}"
OUTPUT_DIR="$REPO_DIR/release-stage"
ZIP_PATH="$OUTPUT_DIR/Lisan-v${VERSION}.zip"
VENDOR_WHISPER="$HOME/vendor/whisper.cpp"

echo "==> Clean previous build + stage"
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$STAGE_DIR/vendor/whisper.cpp/build/bin" \
         "$STAGE_DIR/vendor/whisper.cpp/models" \
         "$STAGE_DIR/packs"

echo "==> xcodegen generate"
(cd "$REPO_DIR" && xcodegen generate >/dev/null)

echo "==> xcodebuild Release (ad-hoc first; we re-sign with Developer ID below)"
xcodebuild \
  -project "$REPO_DIR/Steno.xcodeproj" \
  -scheme Steno \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

APP_SRC="$BUILD_DIR/Build/Products/Release/Steno.app"
APP_DST="$STAGE_DIR/Lisan.app"
cp -R "$APP_SRC" "$APP_DST"

echo "==> Override CFBundleName to Lisan"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Lisan" "$APP_DST/Contents/Info.plist"

echo "==> Sign with Developer ID + hardened runtime + timestamp"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$REPO_DIR/Steno/Steno.release.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_DST"

echo "==> Local verify (strict) — must pass before submitting to Apple"
codesign --verify --deep --strict --verbose=2 "$APP_DST"

echo "==> Zip for notarization (use --sequesterRsrc so xattrs don't scatter on unzip)"
NOTARY_ZIP="$OUTPUT_DIR/Lisan-notary-v${VERSION}.zip"
(cd "$STAGE_DIR" && ditto -c -k --sequesterRsrc Lisan.app "$NOTARY_ZIP")

echo "==> Submit to Apple notary service (blocks until Accepted or Rejected)"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Staple notarization ticket"
xcrun stapler staple "$APP_DST"

echo "==> Final Gatekeeper assessment"
spctl -a -vv "$APP_DST"

echo "==> Populate release bundle (whisper, models, packs, INSTALL)"
cp "$VENDOR_WHISPER/build/bin/whisper-cli" "$STAGE_DIR/vendor/whisper.cpp/build/bin/"
cp "$VENDOR_WHISPER/models/ggml-base.bin" "$STAGE_DIR/vendor/whisper.cpp/models/"
cp "$VENDOR_WHISPER/models/ggml-silero-v6.2.0.bin" "$STAGE_DIR/vendor/whisper.cpp/models/"
cp -r "$REPO_DIR/packs/"*.txt "$REPO_DIR/packs/README.md" "$STAGE_DIR/packs/"

cat > "$STAGE_DIR/INSTALL.md" <<EOF
# Lisan v${VERSION} — Install

Developer-ID signed + Apple-notarized. First launch is clean, no Gatekeeper warning.

\`\`\`bash
mv Lisan.app /Applications/
mkdir -p ~/vendor && ln -sf "\$(pwd)/vendor/whisper.cpp" ~/vendor/whisper.cpp
open /Applications/Lisan.app
\`\`\`

Verify (optional):
\`\`\`
codesign --verify --deep --strict /Applications/Lisan.app
spctl -a -vv /Applications/Lisan.app
xcrun stapler validate /Applications/Lisan.app
\`\`\`

Source: https://github.com/Moshe-ship/Lisan
EOF

echo "==> Package final release zip (--sequesterRsrc again for the bundle)"
(cd "$OUTPUT_DIR" && ditto -c -k --sequesterRsrc --keepParent "Lisan-v${VERSION}" "$ZIP_PATH")

echo "==> Self-verify: unzip into temp and re-run all 3 gates on a FRESH bundle"
VERIFY_DIR="$(mktemp -d)"
(cd "$VERIFY_DIR" && unzip -q "$ZIP_PATH")
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/Lisan-v${VERSION}/Lisan.app"
spctl -a -vv "$VERIFY_DIR/Lisan-v${VERSION}/Lisan.app"
xcrun stapler validate "$VERIFY_DIR/Lisan-v${VERSION}/Lisan.app"
rm -rf "$VERIFY_DIR"

echo
echo "============================================================"
echo "  READY: $ZIP_PATH"
echo "  SHA-256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "  Size:    $(du -h "$ZIP_PATH" | awk '{print $1}')"
echo "============================================================"
echo "Next:  gh release create v${VERSION} \"$ZIP_PATH\" --repo Moshe-ship/Lisan"
