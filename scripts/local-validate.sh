#!/usr/bin/env bash
# Bootstraps the Swift toolchain if missing, then runs SwiftPM tests.
# Safe to run repeatedly — installs Swift only when not already on PATH.
set -euo pipefail

# Latest Swift version with confirmed Linux tarball availability.
# URL format (new 4-component): /{category}/{platform}/{version}/{file}
# e.g. https://download.swift.org/swift-6.3.2-release/debian12/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE-debian12.tar.gz
SWIFT_VERSION="6.3.2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "[local-validate] $*"; }

# Idempotent Swift toolchain installer.
# Tries swiftly first; falls back to a direct tarball download.
ensure_swift() {
    if command -v swift &>/dev/null; then
        log "Swift found: $(swift --version 2>&1 | head -1)"
        return 0
    fi

    log "Swift not found. Installing Swift $SWIFT_VERSION..."

    # --- Detect platform ---
    local arch
    arch=$(uname -m)
    local platform_name platform_full arch_suffix=""
    [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && arch_suffix="-aarch64"

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "$ID-$VERSION_ID" in
            debian-12)  platform_name="debian12";  platform_full="debian12" ;;
            ubuntu-24.04) platform_name="ubuntu2404"; platform_full="ubuntu24.04" ;;
            ubuntu-22.04) platform_name="ubuntu2204"; platform_full="ubuntu22.04" ;;
            ubuntu-20.04) platform_name="ubuntu2004"; platform_full="ubuntu20.04" ;;
            *)
                log "Unknown OS ($ID $VERSION_ID) — defaulting to ubuntu22.04 tarball."
                platform_name="ubuntu2204"; platform_full="ubuntu22.04" ;;
        esac
    else
        platform_name="ubuntu2204"; platform_full="ubuntu22.04"
    fi

    # --- Try swiftly (new installer location) ---
    local SWIFTLY_BIN="$HOME/.swiftly/bin/swiftly"
    if [[ ! -x "$SWIFTLY_BIN" ]]; then
        log "Downloading swiftly binary..."
        mkdir -p "$HOME/.swiftly/bin"
        curl -sfL \
            "https://github.com/swiftlang/swiftly/releases/download/0.3.0/swiftly-x86_64-unknown-linux-gnu" \
            -o "$SWIFTLY_BIN" --max-time 60 || true
        [[ -f "$SWIFTLY_BIN" ]] && chmod +x "$SWIFTLY_BIN"
    fi

    if [[ -x "$SWIFTLY_BIN" ]]; then
        export PATH="$HOME/.swiftly/bin:$PATH"
        # Ensure swiftly config exists
        mkdir -p "$HOME/.local/share/swiftly"
        if [[ ! -f "$HOME/.local/share/swiftly/config.json" ]]; then
            printf '{"inUse":null,"installedToolchains":[],"platform":{"name":"%s","nameFull":"%s","namePretty":"%s","architecture":"x86_64"}}\n' \
                "$platform_name" "$platform_full" "$platform_full" \
                > "$HOME/.local/share/swiftly/config.json"
        fi
        swiftly install "$SWIFT_VERSION" --no-verify 2>&1 || true
        export PATH="$HOME/.local/share/swiftly/toolchains/swift-${SWIFT_VERSION}-RELEASE/usr/bin:$PATH"
    fi

    if command -v swift &>/dev/null; then
        log "Swift installed via swiftly: $(swift --version 2>&1 | head -1)"
        return 0
    fi

    # --- Fallback: direct tarball download using new 4-component URL format ---
    # URL: https://download.swift.org/{category}/{platform}/{version}/{file}
    log "swiftly path failed; falling back to direct tarball download..."
    local platform_with_arch="${platform_name}${arch_suffix}"
    local version_tag="swift-${SWIFT_VERSION}-RELEASE"
    local filename="${version_tag}-${platform_full}${arch_suffix}.tar.gz"
    local category="swift-${SWIFT_VERSION}-release"
    local url="https://download.swift.org/${category}/${platform_with_arch}/${version_tag}/${filename}"
    local dest="$HOME/.swift-toolchain"

    log "Downloading $url ..."
    mkdir -p "$dest"
    curl -fL "$url" -o "$dest/swift.tar.gz" --progress-bar
    tar -xzf "$dest/swift.tar.gz" -C "$dest" --strip-components=1
    rm "$dest/swift.tar.gz"
    export PATH="$dest/usr/bin:$PATH"

    if ! command -v swift &>/dev/null; then
        log "ERROR: Swift installation failed. Install Swift $SWIFT_VERSION manually."
        exit 1
    fi
    log "Swift installed via tarball: $(swift --version 2>&1 | head -1)"
}

ensure_swift

# On Linux the root package can't build (FluidAudio requires mach/mach.h).
# Run the Linux-safe subset: NoteTakrKit (pure Foundation, no macOS frameworks).
log "Running NoteTakrKit tests (Linux-safe subset)..."
cd "$REPO_ROOT/NoteTakrKit"
swift test

log "All local tests passed."
