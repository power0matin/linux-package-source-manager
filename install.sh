#!/usr/bin/env bash
#
# Linux Package Source Manager — stable release bootstrap
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
#
set -Eeuo pipefail

readonly REPOSITORY="power0matin/linux-package-source-manager"
readonly RELEASE_BASE_URL="https://github.com/${REPOSITORY}/releases/latest/download"
readonly SCRIPT_NAME="linux-package-source-manager.sh"
readonly SCRIPT_URL="${RELEASE_BASE_URL}/${SCRIPT_NAME}"
readonly CHECKSUM_URL="${SCRIPT_URL}.sha256"

log() {
  printf '[LPSM] %s\n' "$*"
}

fail() {
  printf '[LPSM] ERROR: %s\n' "$*" >&2
  exit 1
}

download_file() {
  local url="$1"
  local destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --retry 3 \
      --connect-timeout 10 --max-time 300 --output "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 --timeout=10 --output-document="$destination" "$url"
  else
    fail "curl or wget is required to download the release."
  fi
}

command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required to verify the release."
command -v bash >/dev/null 2>&1 || fail "Bash is required to run the application."

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lpsm.XXXXXXXX")" || fail "Could not create a temporary directory."
readonly WORK_DIR
trap 'rm -rf -- "$WORK_DIR"' EXIT

SCRIPT_PATH="${WORK_DIR}/${SCRIPT_NAME}"
CHECKSUM_PATH="${SCRIPT_PATH}.sha256"

log "Downloading the latest stable release..."
download_file "$SCRIPT_URL" "$SCRIPT_PATH" || fail "Could not download the application script."
download_file "$CHECKSUM_URL" "$CHECKSUM_PATH" || fail "Could not download the release checksum."

[[ -s "$SCRIPT_PATH" ]] || fail "The downloaded application script is empty."
[[ -s "$CHECKSUM_PATH" ]] || fail "The downloaded checksum file is empty."

EXPECTED_HASH="$(awk -v filename="$SCRIPT_NAME" '$2 == filename { print $1; exit }' "$CHECKSUM_PATH")"
[[ "$EXPECTED_HASH" =~ ^[[:xdigit:]]{64}$ ]] || fail "The release checksum has an invalid format."

ACTUAL_HASH="$(sha256sum "$SCRIPT_PATH")"
ACTUAL_HASH="${ACTUAL_HASH%% *}"
[[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]] || fail "SHA-256 verification failed; the script will not be executed."

bash -n "$SCRIPT_PATH" || fail "The downloaded script contains invalid Bash syntax."

log "Checksum verified."
if (($# == 0)); then
  set -- --menu
fi

if ((EUID == 0)); then
  log "Opening the interactive menu..."
  bash "$SCRIPT_PATH" "$@"
elif command -v sudo >/dev/null 2>&1; then
  log "Requesting root privileges..."
  sudo bash "$SCRIPT_PATH" "$@"
else
  fail "Run as root or install sudo to open the system management menu."
fi
