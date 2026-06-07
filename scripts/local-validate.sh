#!/usr/bin/env bash
#
# local-validate.sh — run every Linux-compatible check available in the Docker
# container. This is the fast inner loop; the macOS GitHub Actions workflow is
# the source of truth for native compilation and macOS-only tests.
#
# It bootstraps a Swift for Linux toolchain if one is not already present so the
# script is self-contained on a fresh container.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SWIFT_VERSION="6.1"
SWIFT_INSTALL_DIR="/opt/swift"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

install_swift_linux() {
    log "Swift not found — installing Swift ${SWIFT_VERSION} for Linux"

    if ! command -v lsb_release >/dev/null 2>&1; then
        . /etc/os-release
        local ubuntu_ver="${VERSION_ID}"
    else
        local ubuntu_ver
        ubuntu_ver="$(lsb_release -rs)"
    fi

    local ubuntu_tag="ubuntu${ubuntu_ver//./}"     # 24.04 -> ubuntu2404
    local ubuntu_dir="ubuntu${ubuntu_ver}"         # 24.04 -> ubuntu24.04
    local base="https://download.swift.org/swift-${SWIFT_VERSION}-release/${ubuntu_tag}/swift-${SWIFT_VERSION}-RELEASE"
    local url="${base}/swift-${SWIFT_VERSION}-RELEASE-${ubuntu_dir}.tar.gz"

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
        libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata \
        zlib1g-dev libncurses-dev libsqlite3-dev

    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "${tmp}/swift.tar.gz" "$url"
    sudo mkdir -p "$SWIFT_INSTALL_DIR"
    sudo tar xzf "${tmp}/swift.tar.gz" -C "$SWIFT_INSTALL_DIR" --strip-components=1
    sudo ln -sf "${SWIFT_INSTALL_DIR}/usr/bin/swift" /usr/local/bin/swift
    sudo ln -sf "${SWIFT_INSTALL_DIR}/usr/bin/swiftc" /usr/local/bin/swiftc
    rm -rf "$tmp"
}

if ! command -v swift >/dev/null 2>&1; then
    install_swift_linux
fi

log "Toolchain: $(swift --version | head -1)"

log "Building Linux-compatible targets"
swift build

log "Running Linux-compatible tests (swift test)"
# NotetakrAppKit/NotetakrApp UI code is guarded behind #if os(macOS); on Linux
# only the cross-platform NotetakrCore tests actually execute.
swift test

log "local-validate.sh: all Linux-compatible checks passed ✅"
