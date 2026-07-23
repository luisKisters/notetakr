#!/usr/bin/env bash
# Dev convenience: build NoteTakr, replace /Applications/NoteTakr.app, and relaunch.
#
# This is the one-shot "I changed code, show me the new build" loop. It wraps
# scripts/build-macos-app.sh --install and additionally quits the running app
# before installing and relaunches it afterward, so you always see the latest build.
#
# Usage:
#   scripts/dev-reinstall.sh [--config <Debug|Release>] [--no-launch]
#
# Options:
#   --config CFG   Build configuration passed through to build-macos-app.sh (default: Debug).
#   --no-launch    Install but don't relaunch the app afterward.
#
# Signing: uses an explicitly configured identity when NOTETAKR_SIGN_IDENTITY is
# set. Otherwise it prefers an installed Apple Development identity and falls
# back to a persistent local identity created by setup-local-signing.sh. This is
# required for stable macOS privacy grants; ad-hoc signatures are tied to the
# exact build and trigger fresh prompts after code changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DEST="/Applications/NoteTakr.app"
CONFIG="Debug"
LAUNCH=true

log() { echo "[dev-reinstall] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)    CONFIG="$2"; shift 2 ;;
        --no-launch) LAUNCH=false; shift ;;
        --help|-h)
            sed -n '2,20p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "[dev-reinstall] Unknown argument: $1. Run with --help for usage." >&2; exit 1 ;;
    esac
done

# Use the standard Xcode install directly when xcode-select still points at the
# standalone Command Line Tools. This avoids requiring a global sudo switch.
if ! xcodebuild -version >/dev/null 2>&1 \
    && [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    log "Using Xcode from /Applications/Xcode.app."
fi

# --- Resolve a stable signing identity before touching the installed app ---
if [[ -z "${NOTETAKR_SIGN_IDENTITY:-}" ]]; then
    APPLE_DEVELOPMENT_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk '/"Apple Development: / { print $2; exit }'
    )"
    if [[ -n "$APPLE_DEVELOPMENT_IDENTITY" ]]; then
        export NOTETAKR_SIGN_IDENTITY="$APPLE_DEVELOPMENT_IDENTITY"
        log "Using installed Apple Development signing identity."
    else
        export NOTETAKR_SIGN_IDENTITY
        NOTETAKR_SIGN_IDENTITY="$("$REPO_ROOT/scripts/setup-local-signing.sh")"
        # A self-signed identity has no Apple Team ID. Hardened-runtime library
        # validation would therefore reject Sparkle even after re-signing it
        # with the same certificate, so local builds opt out of that one check.
        export NOTETAKR_DISABLE_LIBRARY_VALIDATION=1
    fi
elif [[ "$NOTETAKR_SIGN_IDENTITY" == "-" ]]; then
    log "WARNING: ad-hoc signing was explicitly requested; macOS permissions will not survive code changes."
elif security find-certificate -Z -c "NoteTakr Local Development" 2>/dev/null \
    | grep -q "$NOTETAKR_SIGN_IDENTITY"; then
    export NOTETAKR_DISABLE_LIBRARY_VALIDATION=1
fi

# Development builds do not need a distribution timestamp. This also keeps the
# local self-signed fallback away from Apple's secure timestamp service.
export NOTETAKR_DISABLE_TIMESTAMP="${NOTETAKR_DISABLE_TIMESTAMP:-1}"

# --- Quit any running instance so the bundle can be replaced cleanly ---
if pgrep -x NoteTakr >/dev/null 2>&1; then
    log "Quitting running NoteTakr ..."
    osascript -e 'quit app "NoteTakr"' 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x NoteTakr >/dev/null 2>&1 || break
        sleep 0.3
    done
    pkill -x NoteTakr 2>/dev/null || true
fi

# --- Build + install (replaces /Applications/NoteTakr.app) ---
log "Building and installing to $INSTALL_DEST ..."
"$REPO_ROOT/scripts/build-macos-app.sh" --install --config "$CONFIG"

# --- Relaunch ---
if $LAUNCH; then
    log "Launching $INSTALL_DEST ..."
    open "$INSTALL_DEST"
fi

log "Done."
