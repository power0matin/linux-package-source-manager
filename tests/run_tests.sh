#!/usr/bin/env bash
#
# Power APT Boost — Offline regression and safety tests
#
# Run: bash tests/run_tests.sh

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT="${PROJECT_DIR}/power-apt-boost.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
_tests_run=0
_tests_passed=0
_tests_failed=0
_TEST_ROOT=""

assert_exit_code() {
  local expected="$1" actual="$2" name="$3"
  ((_tests_run+=1))
  if [[ "$actual" -eq "$expected" ]]; then
    ((_tests_passed+=1))
    printf '%bPASS%b %s\n' "$GREEN" "$RESET" "$name"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b %s (expected %d, got %d)\n' "$RED" "$RESET" "$name" "$expected" "$actual"
  fi
}

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  ((_tests_run+=1))
  if [[ "$actual" == *"$expected"* ]]; then
    ((_tests_passed+=1))
    printf '%bPASS%b %s\n' "$GREEN" "$RESET" "$name"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b %s (missing: %s)\n' "$RED" "$RESET" "$name" "$expected"
  fi
}

assert_file_contains() {
  local file="$1" expected="$2" name="$3"
  local content=""
  [[ ! -f "$file" ]] || content="$(cat "$file")"
  assert_contains "$expected" "$content" "$name"
}

cleanup() {
  [[ -z "$_TEST_ROOT" ]] || rm -rf "$_TEST_ROOT"
}
trap cleanup EXIT

test_cli() {
  local output code
  output="$(bash "$SCRIPT" --help 2>&1)"
  assert_contains "Power APT Boost" "$output" "help displays product name"
  assert_contains "--restore" "$output" "help displays restore option"

  output="$(bash "$SCRIPT" --version 2>&1)"
  assert_contains "3.0.0" "$output" "version matches script version"

  code=0
  bash "$SCRIPT" --invalid-option >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown option has usage exit code"

  code=0
  bash "$SCRIPT" --mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "missing mirror URL has usage exit code"

  code=0
  bash "$SCRIPT" --timeout 0 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "zero timeout is rejected"

  code=0
  bash "$SCRIPT" --timeout 301 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "timeout above maximum is rejected"

  code=0
  bash "$SCRIPT" --country usa >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "invalid country code is rejected"
}

test_filesystem_operations() {
  _TEST_ROOT="$(mktemp -d)"
  export POWER_APT_BOOST_TEST_MODE=1
  export POWER_APT_BOOST_TEST_ROOT="$_TEST_ROOT"
  export POWER_APT_BOOST_SOURCE_ONLY=1

  # shellcheck source=../power-apt-boost.sh
  source "$SCRIPT"
  _setup_colors

  mkdir -p "$APT_ETC_DIR" "$APT_SOURCES_DIR"
  printf 'deb http://old.example/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  printf 'Types: deb\nURIs: https://old.example/ubuntu\n' >"${APT_SOURCES_DIR}/ubuntu.sources"
  chmod 0640 "$APT_SOURCES_FILE"

  local backup_dir
  backup_dir="$(_create_backup)"
  assert_contains "manifest" "$(find "$backup_dir" -maxdepth 1 -type f -printf '%f ')" "backup contains a manifest"
  assert_file_contains "$backup_dir/manifest" "sources_list.d=present" "manifest records present source directory"
  assert_file_contains "$backup_dir/manifest" "apt.conf.d=absent" "manifest records absent config directory"
  (
    cd "$backup_dir"
    sha256sum -c archive.sha256 >/dev/null
  )
  assert_exit_code 0 "$?" "backup archive checksum validates"

  printf 'changed source list\n' >"$APT_SOURCES_FILE"
  printf 'changed deb822\n' >"${APT_SOURCES_DIR}/ubuntu.sources"
  mkdir -p "$APT_CONF_DIR"
  printf 'injected config\n' >"${APT_CONF_DIR}/99-unrelated"
  local restore_status=0
  _restore_backup "$backup_dir" >/dev/null 2>&1 || restore_status=$?
  assert_exit_code 0 "$restore_status" "restore succeeds"
  assert_file_contains "$APT_SOURCES_FILE" "old.example" "restore restores sources.list content"
  assert_file_contains "${APT_SOURCES_DIR}/ubuntu.sources" "old.example" "restore restores sources directory content"
  ((_tests_run+=1))
  if [[ ! -e "$APT_CONF_DIR" ]]; then
    ((_tests_passed+=1))
    printf '%bPASS%b restore removes directories absent from snapshot\n' "$GREEN" "$RESET"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b restore removes directories absent from snapshot\n' "$RED" "$RESET"
  fi

  local restored_mode
  restored_mode="$(stat -c '%a' "$APT_SOURCES_FILE")"
  assert_contains "640" "$restored_mode" "restore preserves original file mode"

  _atomic_write "${APT_SOURCES_DIR}/atomic.conf" 0600 <<'ATOMIC'
Acquire::Retries "7";
ATOMIC
  assert_file_contains "${APT_SOURCES_DIR}/atomic.conf" 'Acquire::Retries "7";' "atomic writer stores expected content"
  restored_mode="$(stat -c '%a' "${APT_SOURCES_DIR}/atomic.conf")"
  assert_contains "600" "$restored_mode" "atomic writer applies requested mode"
  ((_tests_run+=1))
  if [[ -z "$(find "$APT_SOURCES_DIR" -maxdepth 1 -name '*.tmp.*' -print -quit)" ]]; then
    ((_tests_passed+=1))
    printf '%bPASS%b atomic writer leaves no temporary files\n' "$GREEN" "$RESET"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b atomic writer leaves no temporary files\n' "$RED" "$RESET"
  fi

  TIMEOUT_TOTAL=37
  USE_IPV6=false
  _write_apt_config
  assert_file_contains "$APT_CONF_FILE" 'Acquire::ForceIPv4 "true";' "APT config follows IPv4 mode"
  assert_file_contains "$APT_CONF_FILE" 'Acquire::https::Timeout "37";' "APT config uses configured timeout"
  USE_IPV6=true
  _write_apt_config
  assert_file_contains "$APT_CONF_FILE" 'Acquire::ForceIPv6 "true";' "APT config follows IPv6 mode"
  ((_tests_run+=1))
  if ! grep -q 'Acquire::ForceIPv4' "$APT_CONF_FILE"; then
    ((_tests_passed+=1))
    printf '%bPASS%b IPv6 mode does not force IPv4 simultaneously\n' "$GREEN" "$RESET"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b IPv6 mode does not force IPv4 simultaneously\n' "$RED" "$RESET"
  fi

  COUNTRY_FILTER=ir
  local iran_mirrors
  iran_mirrors="$(_get_mirrors)"
  assert_contains "https://mirror.arvancloud.ir/ubuntu" "$iran_mirrors" "Iran filter includes provider mirrors"
  assert_contains "https://mirror.iranserver.com/ubuntu" "$iran_mirrors" "Iran filter includes IranServer"
  COUNTRY_FILTER=""
  assert_contains "https://archive.ubuntu.com/ubuntu" "$(_get_mirrors)" "unfiltered catalog includes global mirror"

  NO_SPINNER=true
  _start_spinner "test"
  local spinner_code=1
  [[ -z "$_spinner_pid" ]] && spinner_code=0
  assert_exit_code 0 "$spinner_code" "no-spinner prevents spinner startup"

  rm -f "$APT_DEB822_FILE" "$APT_CONF_FILE"
  rmdir "$APT_SOURCES_DIR" 2>/dev/null || true
  DRY_RUN=true
  SELECTED_MIRROR="https://example.invalid/ubuntu"
  SELECTED_TIME="0.001"
  _apply_changes >/dev/null 2>&1
  ((_tests_run+=1))
  if [[ ! -e "$APT_DEB822_FILE" && ! -e "$APT_CONF_FILE" && ! -d "$BACKUP_BASE" ]]; then
    ((_tests_passed+=1))
    printf '%bPASS%b dry-run does not mutate APT paths or create backups\n' "$GREEN" "$RESET"
  else
    ((_tests_failed+=1))
    printf '%bFAIL%b dry-run does not mutate APT paths or create backups\n' "$RED" "$RESET"
  fi

  local tampered_backup
  tampered_backup="$(mktemp -d "$BACKUP_BASE/tampered.XXXXXX")"
  cp -a "$backup_dir/." "$tampered_backup/"
  printf 'tamper\n' >>"$tampered_backup/apt-config.tar"
  printf 'current-state\n' >"$APT_SOURCES_FILE"
  local restore_code=0
  _restore_backup "$tampered_backup" >/dev/null 2>&1 || restore_code=$?
  assert_exit_code 8 "$restore_code" "restore rejects checksum mismatch"
  assert_file_contains "$APT_SOURCES_FILE" "current-state" "checksum failure leaves current files untouched"
}

test_probe_parser_and_list_criteria() {
  _probe_url_code() {
    case "$1" in
      */noble/InRelease) printf '200\t0.010000\t\n' ;;
      */noble-updates/InRelease) printf '200\t0.020000\t\n' ;;
      */noble-security/InRelease) printf '200\t0.030000\t\n' ;;
      *) printf '404\t0.040000\tmissing endpoint\n' ;;
    esac
  }

  local result_file
  result_file="$(mktemp)"
  _test_mirror "https://fixture.invalid/ubuntu" "$result_file" "noble" >/dev/null 2>&1
  assert_contains " pass" "$(cat "$result_file")" "mirror tester accepts all three successful endpoints"
  rm -f "$result_file"

  result_file="$(mktemp)"
  _test_mirror "https://fixture.invalid/ubuntu" "$result_file" "other" >/dev/null 2>&1
  assert_contains " fail" "$(cat "$result_file")" "mirror tester rejects incomplete endpoint coverage"
  rm -f "$result_file"
}

main() {
  printf '\nPower APT Boost — Offline Test Suite\n'
  printf '%s\n' '===================================='
  test_cli
  test_filesystem_operations
  test_probe_parser_and_list_criteria
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"