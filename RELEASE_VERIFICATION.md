# Release verification

Standard audit cycle for any Lisan release asset. Run these six commands
against a fresh download of the published zip. All six must pass — if any
fail, the release is not distribution-grade and must be re-packaged.

The `scripts/package-release.sh` script runs these automatically against
the final zip before emitting it, so a regression that breaks any gate
fails the build, not the audit.

## Prereqs

- macOS 13+ with developer CLT (`xcode-select --install`)
- `gh` CLI authenticated against the release org

## The cycle

```bash
# Clean working dir so nothing stale contaminates the check
TMP="$(mktemp -d)" && cd "$TMP"

VERSION="0.2.1"   # or whichever tag you're auditing

# --- 1. download the exact release asset from GitHub ---
gh release download "v${VERSION}" \
  --repo Moshe-ship/Lisan \
  --pattern "Lisan-v${VERSION}.zip"
shasum -a 256 "Lisan-v${VERSION}.zip"

# --- 2. unzip with plain `unzip` (not `ditto -x`) — this is the end-user path ---
unzip -q "Lisan-v${VERSION}.zip"

# --- 3. AppleDouble check — must return empty ---
find "Lisan-v${VERSION}/Lisan.app" -name "._*"

# --- 4. codesign strict verify ---
codesign --verify --deep --strict --verbose=4 "Lisan-v${VERSION}/Lisan.app"

# --- 5. Gatekeeper assessment ---
spctl -a -vv "Lisan-v${VERSION}/Lisan.app"

# --- 6. Notarization ticket validation ---
xcrun stapler validate "Lisan-v${VERSION}/Lisan.app"

# --- bonus: entitlements must be reduced to audio-input only ---
codesign -d --entitlements - "Lisan-v${VERSION}/Lisan.app"
```

## Expected output (the good path)

| Step | Command | Must output |
|------|---------|-------------|
| 3    | `find ... -name "._*"` | *(empty — no AppleDouble files inside bundle)* |
| 4    | `codesign --verify --deep --strict` | `valid on disk` AND `satisfies its Designated Requirement` |
| 5    | `spctl -a -vv` | `accepted` + `source=Notarized Developer ID` |
| 6    | `xcrun stapler validate` | `The validate action worked!` |
| bonus| `codesign -d --entitlements -` | Single key: `com.apple.security.device.audio-input` |

## Failure modes and what they mean

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| `sealed resource is missing or invalid` on `codesign --verify` | The zip was built without `--sequesterRsrc`; `._*` AppleDouble files scattered into the bundle on unzip | Re-package via `scripts/package-release.sh` which uses the right flag |
| `internal error in Code Signing subsystem` on `spctl` | Same as above — resource seal corrupted by AppleDouble | Same fix |
| `invalid entitlements blob` on `codesign -d --entitlements` | Entitlements file modified after signing, or signing step didn't receive the entitlements | Re-run sign step with `--entitlements Steno/Steno.entitlements` |
| `source=Unnotarized Developer ID` on `spctl` | Notarization step skipped or failed | Run `xcrun notarytool submit ... --wait` then `xcrun stapler staple` |
| `source=Developer ID` but not notarized, and `spctl` rejected | Ticket not stapled; app will fail Gatekeeper on offline machines | `xcrun stapler staple` the app and re-package |
| DYLD or other non-minimum entitlement present | `Steno/Steno.entitlements` regressed | Restore to audio-input only |

## When to run

- Automatic: on every invocation of `scripts/package-release.sh` (it self-verifies before producing the final zip)
- Manual: before announcing any release publicly
- Audit: any time a reviewer questions a release asset's trust posture

## Installing a verified asset

After the six gates pass on a fresh download, the installed copy should
be bit-identical to the downloaded binary. Verify by hash:

```bash
DL_HASH="$(shasum -a 256 "Lisan-v${VERSION}/Lisan.app/Contents/MacOS/Steno" | awk '{print $1}')"
rm -rf /Applications/Lisan.app
cp -R "Lisan-v${VERSION}/Lisan.app" /Applications/Lisan.app
INST_HASH="$(shasum -a 256 /Applications/Lisan.app/Contents/MacOS/Steno | awk '{print $1}')"
[ "$DL_HASH" = "$INST_HASH" ] && echo "MATCH" || echo "MISMATCH"
```

Re-run gates 4, 5, 6 against `/Applications/Lisan.app` — must still pass.

## Reference run: v0.2.1 (2026-04-17)

Zip SHA-256: `b479ae027e49817f0e012b145f3997a9ddd81c2d0e39c7a6da5ec1f4b4da453a`
Binary SHA-256: `7ac42ca1a6ad6dd84b077418b3ffa4e179f55ab0d6cec455dc325a7c42121f35`
Notary submission: `c12120fc-e10a-4682-ade2-fdd0e394bbfe` (status: Accepted)
Team ID: `VSL9H2F2D3`
All six gates passed on fresh download + installed copy.
