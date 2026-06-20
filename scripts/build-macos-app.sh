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
#   xcodebuild from Xcode 16+ must be on PATH. Install Xcode with xcodes or from
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
Install Xcode 16 or later with xcodes or from https://developer.apple.com/download/all/
then run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
Verify with: xcode-select -p && xcodebuild -version"
fi

XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / {print $2}')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
if [[ "${XCODE_MAJOR:-0}" -lt 16 ]]; then
    die "Xcode 16 or later is required for FluidAudio Swift tools 6.0 support. Selected Xcode: ${XCODE_VERSION:-unknown}"
fi

if [[ ! -d "$XCODEPROJ" ]]; then
    die "Xcode project not found at $XCODEPROJ"
fi

log "xcodebuild: $(xcodebuild -version 2>&1 | head -1)"
log "Scheme: $SCHEME  Config: $CONFIG"

mkdir -p "$BUILD_DIR" "$DERIVED_DATA"

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
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        AD_HOC_ENTITLEMENTS="$BUILD_DIR/NoteTakr.ad-hoc.entitlements"
        cp "$REPO_ROOT/NoteTakrApp/NoteTakr.entitlements" "$AD_HOC_ENTITLEMENTS"
        /usr/libexec/PlistBuddy \
            -c "Add :com.apple.security.cs.disable-library-validation bool true" \
            "$AD_HOC_ENTITLEMENTS" 2>/dev/null || \
            /usr/libexec/PlistBuddy \
                -c "Set :com.apple.security.cs.disable-library-validation true" \
                "$AD_HOC_ENTITLEMENTS"
        SIGN_ARGS+=(
            CODE_SIGN_STYLE=Manual
            CODE_SIGNING_REQUIRED=YES
            CODE_SIGNING_ALLOWED=YES
            CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
            CODE_SIGN_ENTITLEMENTS="$AD_HOC_ENTITLEMENTS"
            DEVELOPMENT_TEAM=""
        )
        log "Signing: ad-hoc with disabled library validation for embedded Sparkle."
    else
        # The project sets DEVELOPMENT_TEAM="" with automatic signing, which
        # xcodebuild rejects. Manual style signs directly with the identity;
        # no provisioning profile is needed for these entitlements on macOS.
        SIGN_ARGS+=(CODE_SIGN_STYLE=Manual)
        if [[ -n "${NOTETAKR_DEVELOPMENT_TEAM:-}" ]]; then
            SIGN_ARGS+=(DEVELOPMENT_TEAM="$NOTETAKR_DEVELOPMENT_TEAM")
        fi
        log "Signing: $SIGN_IDENTITY"
    fi
fi

# --- Build ---
log "Resolving Swift package dependencies ..."
xcodebuild -resolvePackageDependencies \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME"

log "Building $XCODEPROJ ..."
# Pipe through xcpretty only when it exists; `cat` keeps tee's stdout alive
# otherwise (a missing xcpretty kills tee with SIGPIPE after one line, which
# truncates the log and can abort xcodebuild itself).
PRETTY=(cat)
command -v xcpretty &>/dev/null && PRETTY=(xcpretty)
BUILD_EXIT=0
xcodebuild build \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    SYMROOT="$BUILD_DIR/symroot" \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
    PRODUCT_BUNDLE_IDENTIFIER="com.notetakr.app" \
    "${SIGN_ARGS[@]}" \
    | tee "$BUILD_DIR/xcodebuild.log" \
    | "${PRETTY[@]}" || BUILD_EXIT=$?
# pipefail (set at top) propagates xcodebuild's status through the pipeline.
if [[ $BUILD_EXIT -ne 0 ]]; then
    grep -E 'error:|Build FAILED' "$BUILD_DIR/xcodebuild.log" | head -20 || true
    die "xcodebuild failed (exit $BUILD_EXIT). See $BUILD_DIR/xcodebuild.log"
fi

# --- Locate the built product ---
# Only look in this config's output dir; searching the whole symroot tree can
# silently pick up a stale app from another configuration.
BUILT_APP=$(find "$BUILD_DIR/symroot/$CONFIG" -maxdepth 1 -name "*.app" -type d 2>/dev/null | head -1)

if [[ -z "$BUILT_APP" ]]; then
    die "Build succeeded but NoteTakr.app was not found under $BUILD_DIR/symroot.
Check $BUILD_DIR/xcodebuild.log for details."
fi

log "Built product: $BUILT_APP"

# --- Copy to deterministic output path ---
rm -rf "$OUTPUT_APP"
cp -Rp "$BUILT_APP" "$OUTPUT_APP"
log "Copied to: $OUTPUT_APP"

if [[ -n "$SIGN_IDENTITY" ]]; then
    bash "$REPO_ROOT/scripts/resign-sparkle-framework.sh" "$OUTPUT_APP" "$SIGN_IDENTITY"
fi

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
