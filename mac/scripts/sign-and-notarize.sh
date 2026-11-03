#!/usr/bin/env bash
# Signs mac/build/Termaid.app (from build-app.sh) with a Developer ID and the hardened runtime,
# then notarizes and staples it so Gatekeeper opens it on other Macs.
# One-time setup: xcrun notarytool store-credentials termaid --apple-id <email> --team-id <team>
# Usage: scripts/sign-and-notarize.sh [--sign-only]
# Env: SIGN_IDENTITY (default: first Developer ID Application identity), NOTARY_PROFILE (default: termaid)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Termaid.app"
ENTITLEMENTS="$ROOT/Resources/Termaid.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-termaid}"
SIGN_ONLY=false
[[ "${1:-}" == "--sign-only" ]] && SIGN_ONLY=true

[[ -d "$APP" ]] || { echo "error: $APP missing; run scripts/build-app.sh first" >&2; exit 1; }
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"')}"
[[ -n "$IDENTITY" ]] || { echo "error: no Developer ID Application identity in the keychain" >&2; exit 1; }

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Inside out: nested code must be signed before whatever contains it.
sign "$APP/Contents/Frameworks/llama.framework"
for bundle in "$APP"/Contents/MacOS/*.bundle "$APP"/Contents/Resources/*.bundle; do
  sign "$bundle"
done
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --deep "$APP"
echo "Signed with $IDENTITY"
$SIGN_ONLY && exit 0

ZIP="$(mktemp -d)/Termaid.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
echo "Notarized $APP"

# The download for the GitHub release. Without --noextattr, ditto stores the symlinks' extended
# attributes as AppleDouble entries; unzip and Archive Utility write those out as ._ files inside
# llama.framework, which breaks the seal and Gatekeeper rejects the app.
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ROOT/build/Termaid.zip"
echo "Wrote $ROOT/build/Termaid.zip"
