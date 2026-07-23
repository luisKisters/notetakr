#!/usr/bin/env bash
# Create (once) and reuse a local code-signing identity for NoteTakr development.
#
# The identity lives in its own user keychain under Application Support. Keeping
# the certificate and private key stable gives every dev rebuild the same
# designated requirement, so macOS can carry TCC grants (microphone, screen
# capture, Calendar, Contacts) forward across installs.

set -euo pipefail

IDENTITY_NAME="NoteTakr Local Development"
SIGNING_ROOT="${NOTETAKR_DEV_SIGNING_DIR:-$HOME/Library/Application Support/NoteTakr/DevelopmentSigning}"
KEYCHAIN_PATH="$SIGNING_ROOT/NoteTakrLocalDevelopment.keychain-db"
PASSWORD_FILE="$SIGNING_ROOT/keychain-password"

log() { echo "[local-signing] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

for tool in openssl security; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but was not found."
done

mkdir -p "$SIGNING_ROOT"
chmod 700 "$SIGNING_ROOT"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    log "Creating the persistent local development identity (one-time setup) ..."
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT

    KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
    printf '%s' "$KEYCHAIN_PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -subj "/CN=$IDENTITY_NAME/O=NoteTakr Development/OU=Local Development" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,digitalSignature,keyCertSign" \
        -addext "extendedKeyUsage=codeSigning" \
        -keyout "$TEMP_DIR/private-key.pem" \
        -out "$TEMP_DIR/certificate.pem" \
        >/dev/null 2>&1

    openssl pkcs12 -export -legacy \
        -inkey "$TEMP_DIR/private-key.pem" \
        -in "$TEMP_DIR/certificate.pem" \
        -name "$IDENTITY_NAME" \
        -passout "pass:$KEYCHAIN_PASSWORD" \
        -out "$TEMP_DIR/identity.p12" \
        >/dev/null 2>&1

    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security import "$TEMP_DIR/identity.p12" \
        -k "$KEYCHAIN_PATH" \
        -P "$KEYCHAIN_PASSWORD" \
        -T /usr/bin/codesign \
        >/dev/null
    security add-trusted-cert -d -r trustRoot -p codeSign \
        -k "$KEYCHAIN_PATH" \
        "$TEMP_DIR/certificate.pem"
else
    [[ -f "$PASSWORD_FILE" ]] || die "Found $KEYCHAIN_PATH but not its password file. Remove that development-signing directory and rerun."
    KEYCHAIN_PASSWORD="$(<"$PASSWORD_FILE")"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

# codesign only resolves identities from keychains in the user search list.
# Prepend ours without removing or duplicating any existing keychain.
KEYCHAINS=("$KEYCHAIN_PATH")
while IFS= read -r keychain; do
    keychain="${keychain#\"}"
    keychain="${keychain%\"}"
    if [[ -n "$keychain" && "$keychain" != "$KEYCHAIN_PATH" ]]; then
        KEYCHAINS+=("$keychain")
    fi
done < <(security list-keychains -d user)
security list-keychains -d user -s "${KEYCHAINS[@]}"

IDENTITY_HASH="$(
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
        | awk -v name="$IDENTITY_NAME" 'index($0, "\"" name "\"") { print $2; exit }'
)"
[[ -n "$IDENTITY_HASH" ]] || die "The local code-signing identity is not valid."

log "Using stable identity: $IDENTITY_NAME ($IDENTITY_HASH)"
printf '%s\n' "$IDENTITY_HASH"
