#!/usr/bin/env bash
# Build NoteTakr.app from the Xcode project.
#
# Usage:
#   scripts/build-macos-app.sh [--install] [--scheme <name>] [--config <Debug|Release>]
#
# Options:
#   --install       Copy the built app to /Applications/NoteTakr.app (requires sudo or write access).
#   --scheme NAME   Xcode scheme to build (default: NoteTakr).
#   --config CFG    Build configuration (default: Debug).
#
# Output:
#   build/NoteTakr.app  — always written here, regardless of --install.
#
# Signing:
#   By default the build uses CODE_SIGN_IDENTITY="" (ad-hoc / no signing),
#   which is sufficient for local development and preserves TCC permissions
#   as long as the bundle identifier (com.notetakr.app) does not change.
#   To use a real identity, set NOTETAKR_SIGN_IDENTITY in the environment:
#     NOTETAKR_SIGN_IDENTITY="Apple Development" scripts/build-macos-app.sh
#
# Xcode requirements:
#   xcodebuild must be on PATH.  Install Xcode from the App Store or
#   https://developer.apple.com/download/all/ and then run:
#     sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
#   To verify: xcode-select -p && xcodebuild -version
#   To switch between multiple Xcode versions:
#     sudo xcode-select --switch /path/to/Xcode.app/Contents/Developer

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$REPO_ROOT/Notetakr.xcodeproj"
BUILD_DIR="$REPO_ROOT/build"
OUTPUT_APP="$BUILD_DIR/NoteTakr.app"
DERIVED_DATA="$BUILD_DIR/.deriveddata"

SCHEME="NoteTakr"
CONFIG="Debug"
INSTALL=false

log() { echo "[build-macos-app] $*"; }
die() { log "ERROR: $*"; exit 1; }

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)  INSTALL=true; shift ;;
        --scheme)   SCHEME="$2"; shift 2 ;;
        --config)   CONFIG="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,30p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unknown argument: $1. Run with --help for usage." ;;
    esac
done

# --- Preflight checks ---
if ! command -v xcodebuild &>/dev/null; then
    die "xcodebuild not found.
Install Xcode from the App Store or https://developer.apple.com/download/all/
then run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
Verify with: xcode-select -p && xcodebuild -version"
fi

if [[ ! -d "$XCODEPROJ" ]]; then
    die "Xcode project not found at $XCODEPROJ"
fi

log "xcodebuild: $(xcodebuild -version 2>&1 | head -1)"
log "Scheme: $SCHEME  Config: $CONFIG"

# --- Signing identity ---
SIGN_IDENTITY="${NOTETAKR_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_ARGS=(
        CODE_SIGN_IDENTITY=""
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
    log "Signing: ad-hoc (no identity). Set NOTETAKR_SIGN_IDENTITY to use a real identity."
else
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
    log "Signing: $SIGN_IDENTITY"
fi

# --- Build ---
mkdir -p "$BUILD_DIR" "$DERIVED_DATA"

log "Building $XCODEPROJ ..."
xcodebuild build \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    SYMROOT="$BUILD_DIR/symroot" \
    ONLY_ACTIVE_ARCH=NO \
    PRODUCT_BUNDLE_IDENTIFIER="com.notetakr.app" \
    "${SIGN_ARGS[@]}" \
    | tee "$BUILD_DIR/xcodebuild.log" \
    | xcpretty 2>/dev/null || true
# xcpretty may not be installed; fall back to raw output already written via tee.
# Capture xcodebuild's exit code explicitly — pipefail alone is defeated by the xcpretty fallback.
BUILD_EXIT=${PIPESTATUS[0]}
if [[ $BUILD_EXIT -ne 0 ]]; then
    grep -E '^(error:|warning:|Build (succeeded|FAILED))' "$BUILD_DIR/xcodebuild.log" || true
    die "xcodebuild failed (exit $BUILD_EXIT). See $BUILD_DIR/xcodebuild.log"
fi

# --- Locate the built product ---
BUILT_APP=$(find "$BUILD_DIR/symroot/$CONFIG" -maxdepth 1 -name "*.app" -type d 2>/dev/null | head -1)
if [[ -z "$BUILT_APP" ]]; then
    # Fallback: search symroot tree
    BUILT_APP=$(find "$BUILD_DIR/symroot" -name "NoteTakr.app" -type d 2>/dev/null | head -1)
fi

if [[ -z "$BUILT_APP" ]]; then
    die "Build succeeded but NoteTakr.app was not found under $BUILD_DIR/symroot.
Check $BUILD_DIR/xcodebuild.log for details."
fi

log "Built product: $BUILT_APP"

# --- Copy to deterministic output path ---
rm -rf "$OUTPUT_APP"
cp -Rp "$BUILT_APP" "$OUTPUT_APP"
log "Copied to: $OUTPUT_APP"

# --- Verify bundle identifier ---
ACTUAL_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$OUTPUT_APP/Contents/Info.plist" 2>/dev/null || true)
if [[ -n "$ACTUAL_ID" && "$ACTUAL_ID" != "com.notetakr.app" ]]; then
    log "WARNING: Bundle identifier is '$ACTUAL_ID', expected 'com.notetakr.app'."
else
    log "Bundle identifier: ${ACTUAL_ID:-com.notetakr.app (from build settings)}"
fi

# --- Optional install ---
if $INSTALL; then
    INSTALL_DEST="/Applications/NoteTakr.app"
    log "Installing to $INSTALL_DEST ..."
    if [[ -d "$INSTALL_DEST" ]]; then
        rm -rf "$INSTALL_DEST"
    fi
    cp -Rp "$OUTPUT_APP" "$INSTALL_DEST"
    log "Installed: $INSTALL_DEST"
    log "NOTE: If macOS TCC entries exist for an older build, existing permissions"
    log "are preserved as long as the bundle identifier (com.notetakr.app) is unchanged."
fi

log "Done. App is at: $OUTPUT_APP"
