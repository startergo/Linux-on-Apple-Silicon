#!/bin/bash
# sign.sh — Sign, notarize, and staple LinuxVMCreator.app
#
# Usage:
#   ./sign.sh --app path/to/LinuxVMCreator.app
#   ./sign.sh --app path/to/LinuxVMCreator.app --notarize --apple-id you@example.com --team-id XXXXXXXXXX
#
# Requirements:
#   - Xcode Command Line Tools
#   - "Developer ID Application" certificate in your Keychain
#   - For notarization: app-specific password stored in Keychain as "notarytool-password"
#     Create it with:
#       xcrun notarytool store-credentials "notarytool-password" \
#         --apple-id you@example.com \
#         --team-id XXXXXXXXXX \
#         --password <app-specific-password>

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
APP_PATH=""
NOTARIZE=false
APPLE_ID=""
TEAM_ID=""
KEYCHAIN_PROFILE="notarytool-password"
ENTITLEMENTS="$(dirname "$0")/LinuxVMCreator.entitlements"
BUNDLE_ID="com.startergo.LinuxVMCreator"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)         APP_PATH="$2";          shift 2 ;;
    --notarize)    NOTARIZE=true;          shift   ;;
    --apple-id)    APPLE_ID="$2";          shift 2 ;;
    --team-id)     TEAM_ID="$2";           shift 2 ;;
    --profile)     KEYCHAIN_PROFILE="$2";  shift 2 ;;
    --entitlements) ENTITLEMENTS="$2";     shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Validation ─────────────────────────────────────────────────────────────────
if [[ -z "$APP_PATH" ]]; then
  echo "Error: --app is required"
  echo "Usage: $0 --app path/to/LinuxVMCreator.app [--notarize --apple-id ... --team-id ...]"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App not found at '$APP_PATH'"
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Error: Entitlements file not found at '$ENTITLEMENTS'"
  exit 1
fi

if $NOTARIZE && [[ -z "$APPLE_ID" || -z "$TEAM_ID" ]]; then
  echo "Error: --notarize requires --apple-id and --team-id"
  exit 1
fi

# ── Find Developer ID certificate ─────────────────────────────────────────────
echo "→ Looking for Developer ID Application certificate..."
IDENTITY=$(security find-identity -v -p codesigning | \
  grep "Developer ID Application" | \
  head -1 | \
  sed 's/.*"\(.*\)"/\1/')

if [[ -z "$IDENTITY" ]]; then
  echo "Error: No 'Developer ID Application' certificate found in Keychain."
  echo "Install your certificate from https://developer.apple.com/account/resources/certificates"
  exit 1
fi
echo "  Using: $IDENTITY"

# ── Sign ───────────────────────────────────────────────────────────────────────
echo "→ Signing $APP_PATH..."
codesign \
  --force \
  --deep \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

echo "→ Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true

echo "✓ Signed successfully"

# ── Notarize ───────────────────────────────────────────────────────────────────
if $NOTARIZE; then
  ZIP_PATH="${APP_PATH%.app}-notarize.zip"

  echo "→ Creating ZIP for notarization..."
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  echo "→ Submitting to Apple Notary Service (this may take a few minutes)..."
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    --timeout 600

  rm -f "$ZIP_PATH"

  echo "→ Stapling notarization ticket..."
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  echo "✓ Notarized and stapled successfully"
fi

# ── Final summary ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  App:        $APP_PATH"
echo "  Identity:   $IDENTITY"
echo "  Notarized:  $NOTARIZE"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|TeamIdentifier|Timestamp"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
