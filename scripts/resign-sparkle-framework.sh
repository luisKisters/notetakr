#!/usr/bin/env bash
# Re-sign Sparkle's embedded helper code with the same identity as NoteTakr.app.
#
# Sparkle's release framework is already signed by Sparkle upstream. That is not
# enough for a hardened runtime app: dyld library validation rejects loading a
# third-party framework whose Team ID differs from the containing app. Re-signing
# nested Sparkle code first, then Sparkle.framework, then the outer app keeps the
# app bundle internally consistent for both Developer ID and ad-hoc releases.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/resign-sparkle-framework.sh /path/to/NoteTakr.app <codesign-identity> [outer-app-entitlements.plist]

Examples:
  scripts/resign-sparkle-framework.sh build/NoteTakr.app "-"
  scripts/resign-sparkle-framework.sh build/NoteTakr.app "Developer ID Application: Name (TEAMID)"
USAGE
}

log() { echo "[resign-sparkle] $*"; }
die() { log "ERROR: $*"; exit 1; }

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
    exit 2
fi

APP_PATH="$1"
SIGNING_IDENTITY="$2"
OUTER_APP_ENTITLEMENTS="${3:-}"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"

[[ -d "$APP_PATH" ]] || die "App bundle not found: $APP_PATH"
if [[ -n "$OUTER_APP_ENTITLEMENTS" && ! -f "$OUTER_APP_ENTITLEMENTS" ]]; then
    die "Entitlements file not found: $OUTER_APP_ENTITLEMENTS"
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    log "No Sparkle.framework found in $APP_PATH; nothing to re-sign."
    exit 0
fi

SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
if [[ ! -d "$SPARKLE_VERSION_DIR" ]]; then
    CURRENT_VERSION="$(readlink "$SPARKLE_FRAMEWORK/Versions/Current" 2>/dev/null || true)"
    if [[ -n "$CURRENT_VERSION" && -d "$SPARKLE_FRAMEWORK/Versions/$CURRENT_VERSION" ]]; then
        SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/$CURRENT_VERSION"
    else
        die "Could not find Sparkle framework version directory under $SPARKLE_FRAMEWORK/Versions"
    fi
fi

TIMESTAMP_ARGS=()
if [[ "$SIGNING_IDENTITY" != "-" && "${NOTETAKR_DISABLE_TIMESTAMP:-0}" != "1" ]]; then
    TIMESTAMP_ARGS+=(--timestamp)
fi

BASE_CODESIGN_ARGS=(
    --force
    --sign "$SIGNING_IDENTITY"
    --options runtime
)
if [[ ${#TIMESTAMP_ARGS[@]} -gt 0 ]]; then
    BASE_CODESIGN_ARGS+=("${TIMESTAMP_ARGS[@]}")
fi

sign_if_present() {
    local path="$1"
    shift

    if [[ -e "$path" || -L "$path" ]]; then
        log "Signing ${path#$APP_PATH/}"
        codesign "${BASE_CODESIGN_ARGS[@]}" "$@" "$path"
    fi
}

sign_if_present "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_if_present "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign_if_present "$SPARKLE_VERSION_DIR/Autoupdate"
sign_if_present "$SPARKLE_VERSION_DIR/Updater.app"
sign_if_present "$SPARKLE_FRAMEWORK"

log "Re-signing outer app bundle"
APP_CODESIGN_ARGS=(
    --force
    --sign "$SIGNING_IDENTITY"
    --options runtime
)
if [[ ${#TIMESTAMP_ARGS[@]} -gt 0 ]]; then
    APP_CODESIGN_ARGS+=("${TIMESTAMP_ARGS[@]}")
fi
if [[ -n "$OUTER_APP_ENTITLEMENTS" ]]; then
    APP_CODESIGN_ARGS+=(--entitlements "$OUTER_APP_ENTITLEMENTS")
else
    APP_CODESIGN_ARGS+=(--preserve-metadata=entitlements)
fi
codesign "${APP_CODESIGN_ARGS[@]}" "$APP_PATH"

APP_TEAM_IDENTIFIER="$(codesign -dv "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
SPARKLE_TEAM_IDENTIFIER="$(codesign -dv "$SPARKLE_FRAMEWORK" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
APP_TEAM_IDENTIFIER="${APP_TEAM_IDENTIFIER:-not set}"
SPARKLE_TEAM_IDENTIFIER="${SPARKLE_TEAM_IDENTIFIER:-not set}"

log "App TeamIdentifier: $APP_TEAM_IDENTIFIER"
log "Sparkle TeamIdentifier: $SPARKLE_TEAM_IDENTIFIER"

if [[ "$APP_TEAM_IDENTIFIER" != "$SPARKLE_TEAM_IDENTIFIER" ]]; then
    die "App and Sparkle TeamIdentifier values differ after signing."
fi

codesign --verify --strict --verbose=2 "$SPARKLE_FRAMEWORK"
codesign --verify --strict --verbose=2 "$APP_PATH"
