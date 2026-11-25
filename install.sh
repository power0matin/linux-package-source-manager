#!/usr/bin/env bash
#
# Linux Package Source Manager — verified one-line bootstrap
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
#
set -Eeuo pipefail

readonly VERSION="v3.0.12"
readonly BASE_URL="https://github.com/power0matin/linux-package-source-manager/releases/download/${VERSION}"
readonly SCRIPT_NAME="linux-package-source-manager.sh"
readonly CHECKSUM_NAME="${SCRIPT_NAME}.sha256"

fail() {
  printf 'LPSM installer: %s\n' "$*" >&2
  exit 1
}

command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required."
command -v bash >/dev/null 2>&1 || fail "bash is required."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lpsm.XXXXXXXX")"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

download() {
  local url="$1" destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$destination" "$url"
  else
    fail "Install curl or wget, then run this command again."
  fi
}

download "${BASE_URL}/${SCRIPT_NAME}" "${TMP_DIR}/${SCRIPT_NAME}" ||
  fail "Could not download the LPSM release script."
download "${BASE_URL}/${CHECKSUM_NAME}" "${TMP_DIR}/${CHECKSUM_NAME}" ||
  fail "Could not download the release checksum."

(cd "$TMP_DIR" && sha256sum --check --status "$CHECKSUM_NAME") ||
  fail "Release checksum verification failed."

bash -n "${TMP_DIR}/${SCRIPT_NAME}" ||
  fail "Downloaded release script failed Bash syntax validation."

if ((EUID == 0)); then
  bash "${TMP_DIR}/${SCRIPT_NAME}" "$@"
else
  command -v sudo >/dev/null 2>&1 || fail "Run as root or install sudo."
  sudo -v || fail "Root authorization was not granted."
  sudo bash "${TMP_DIR}/${SCRIPT_NAME}" "$@"
fi
