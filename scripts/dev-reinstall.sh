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
# Signing: defaults to the free "Apple Development" identity so the app keeps a
# STABLE code signature across rebuilds — without it every rebuild looks like a
# new app to macOS TCC and microphone/screen-recording permissions are silently
# revoked (recordings then capture nothing). Override with NOTETAKR_SIGN_IDENTITY.

set -euo pipefail

export NOTETAKR_SIGN_IDENTITY="${NOTETAKR_SIGN_IDENTITY:-Apple Development}"
# Team ID is the cert's OU (security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject)
export NOTETAKR_DEVELOPMENT_TEAM="${NOTETAKR_DEVELOPMENT_TEAM:-4C8444267Z}"

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
