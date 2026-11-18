#!/usr/bin/env bash
#
# Power APT Boost — Offline regression and safety tests
#
# Run: bash tests/run_tests.sh

set -Eeuo pipefail

# This test intentionally sources the script and mutates its globals/functions.
# shellcheck disable=SC2034,SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR
SCRIPT="${PROJECT_DIR}/power-apt-boost.sh"
readonly SCRIPT

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'
_tests_run=0
_tests_passed=0
_tests_failed=0
_TEST_ROOT=""

assert_exit_code() {
  local expected="$1" actual="$2" name="$3"
  ((_tests_run += 1))
  if [[ "$actual" -eq "$expected" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b %s\n' "$GREEN" "$RESET" "$name"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b %s (expected %d, got %d)\n' "$RED" "$RESET" "$name" "$expected" "$actual"
  fi
}

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  ((_tests_run += 1))
  if [[ "$actual" == *"$expected"* ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b %s\n' "$GREEN" "$RESET" "$name"
  else
    ((_tests_failed += 1))
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
  assert_contains "--menu" "$(bash "$SCRIPT" --help 2>&1)" "help documents interactive menu"
  assert_contains "--doctor" "$(bash "$SCRIPT" --help 2>&1)" "help documents doctor command"
  assert_contains "--yes" "$(bash "$SCRIPT" --help 2>&1)" "help documents explicit non-interactive confirmation"

  code=0
  bash "$SCRIPT" </dev/null >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "default non-interactive invocation never blocks or mutates"

  code=0
  bash "$SCRIPT" --menu </dev/null >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "explicit menu rejects non-interactive input"

  code=0
  bash "$SCRIPT" --status --doctor >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "conflicting report modes are rejected"

  output="$(bash "$SCRIPT" --status 2>&1)"
  assert_contains "System Status" "$output" "status command prints a read-only report"

  output="$(bash "$SCRIPT" --doctor 2>&1)"
  assert_contains "Diagnostics" "$output" "doctor command runs local checks"

  local json_file
  json_file="$(mktemp)"
  bash "$SCRIPT" --status --json >"$json_file"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["schema_version"] == 1; assert d["command"] == "status"; assert "apt" in d and "backups" in d and "checks" in d' "$json_file"
  assert_exit_code 0 "$?" "status JSON follows schema version 1"
  bash "$SCRIPT" --doctor --json >"$json_file"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["schema_version"] == 1; assert d["command"] == "doctor"; assert isinstance(d["checks"], list) and d["checks"]' "$json_file"
  assert_exit_code 0 "$?" "doctor JSON contains structured health checks"
  rm -f "$json_file"

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

  local menu_selection
  menu_selection="$(printf '2\n' | _menu_choose "Test menu" "Choose" "first" "First" "second" "Second" 2>/dev/null)"
  assert_contains "second" "$menu_selection" "numbered menu fallback maps selection to a stable action"

  local confirmation_status=0
  YES=false
  _confirm_action "Non-interactive test" >/dev/null 2>&1 || confirmation_status=$?
  assert_exit_code 2 "$confirmation_status" "mutating actions require explicit yes without a TTY"

  YES=true
  confirmation_status=0
  _confirm_action "Approved test" >/dev/null 2>&1 || confirmation_status=$?
  assert_exit_code 0 "$confirmation_status" "yes flag bypasses confirmation explicitly"

  local cancel_input="${_TEST_ROOT}/cancel.input"
  printf 'n\n' >"$cancel_input"
  local before_cancel after_cancel cancel_status=0
  before_cancel="$(find "$APT_ETC_DIR" -type f -print 2>/dev/null | sort || true)"
  _is_interactive() { return 0; }
  YES=false
  _confirm_apply <"$cancel_input" >/dev/null 2>&1 || cancel_status=$?
  unset -f _is_interactive
  after_cancel="$(find "$APT_ETC_DIR" -type f -print 2>/dev/null | sort || true)"
  assert_exit_code 10 "$cancel_status" "declining an apply preview returns cancelled"
  assert_contains "$before_cancel" "$after_cancel" "cancel leaves APT configuration file set unchanged"

  local escaped_json="${_TEST_ROOT}/escaped.json"
  local escaped_value=
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
  local restore_log="${_TEST_ROOT}/restore.log"
  _restore_backup "$backup_dir" >"$restore_log" 2>&1 || restore_status=$?
  if [[ "$restore_status" -ne 0 ]]; then
    printf '%s\n' 'Restore diagnostic:'
    cat "$restore_log"
  fi
  assert_exit_code 0 "$restore_status" "restore succeeds"
  assert_file_contains "$APT_SOURCES_FILE" "old.example" "restore restores sources.list content"
  assert_file_contains "${APT_SOURCES_DIR}/ubuntu.sources" "old.example" "restore restores sources directory content"
  ((_tests_run += 1))
  if [[ ! -e "$APT_CONF_DIR" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b restore removes directories absent from snapshot\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b restore removes directories absent from snapshot\n' "$RED" "$RESET"
  fi

  local restored_mode
  restored_mode="$(stat -c '%a' "$APT_SOURCES_FILE")"
  assert_contains "640" "$restored_mode" "restore preserves original file mode"

  printf 'current-sources-list\n' >"$APT_SOURCES_FILE"
  printf 'current-deb822\n' >"${APT_SOURCES_DIR}/ubuntu.sources"
  mkdir -p "$APT_CONF_DIR"
  printf 'current-apt-config\n' >"${APT_CONF_DIR}/99-current"
  local mv_calls=0 injected_restore_code=0
  mv() {
    mv_calls=$((mv_calls + 1))
    if [[ "$mv_calls" -eq 5 ]]; then
      return 1
    fi
    command mv "$@"
  }
  _restore_backup "$backup_dir" >/dev/null 2>&1 || injected_restore_code=$?
  unset -f mv
  assert_exit_code 8 "$injected_restore_code" "restore reports a failed snapshot install"
  assert_file_contains "$APT_SOURCES_FILE" "current-sources-list" "failed restore recovers original sources.list"
  assert_file_contains "${APT_SOURCES_DIR}/ubuntu.sources" "current-deb822" "failed restore recovers original source directory"
  assert_file_contains "${APT_CONF_DIR}/99-current" "current-apt-config" "failed restore recovers original apt config directory"

  rm -f "$APT_SOURCES_FILE"
  rm -rf "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  local empty_backup empty_restore_status=0
  empty_backup="$(_create_backup)"
  mkdir -p "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'new source file\n' >"$APT_SOURCES_FILE"
  printf 'new source entry\n' >"${APT_SOURCES_DIR}/new.list"
  printf 'new apt config\n' >"${APT_CONF_DIR}/99-new"
  _restore_backup "$empty_backup" >/dev/null 2>&1 || empty_restore_status=$?
  assert_exit_code 0 "$empty_restore_status" "restore accepts an empty APT snapshot"
  ((_tests_run += 1))
  if [[ ! -e "$APT_SOURCES_FILE" && ! -e "$APT_SOURCES_DIR" && ! -e "$APT_CONF_DIR" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b empty snapshot removes all subsequently created managed paths\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b empty snapshot removes all subsequently created managed paths\n' "$RED" "$RESET"
  fi

  mkdir -p "$APT_SOURCES_DIR"
  _atomic_write "${APT_SOURCES_DIR}/atomic.conf" 0600 <<'ATOMIC'
Acquire::Retries "7";
ATOMIC
  assert_file_contains "${APT_SOURCES_DIR}/atomic.conf" 'Acquire::Retries "7";' "atomic writer stores expected content"
  restored_mode="$(stat -c '%a' "${APT_SOURCES_DIR}/atomic.conf")"
  assert_contains "600" "$restored_mode" "atomic writer applies requested mode"
  ((_tests_run += 1))
  if [[ -z "$(find "$APT_SOURCES_DIR" -maxdepth 1 -name '*.tmp.*' -print -quit)" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b atomic writer leaves no temporary files\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
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
  ((_tests_run += 1))
  if ! grep -q 'Acquire::ForceIPv4' "$APT_CONF_FILE"; then
    ((_tests_passed += 1))
    printf '%bPASS%b IPv6 mode does not force IPv4 simultaneously\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
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

  mkdir -p "$APT_SOURCES_DIR" "$APT_CONF_DIR" "${_SYSTEM_ROOT}/var/lib/apt/lists" "${_SYSTEM_ROOT}/var/cache/apt/archives"
  printf 'cached-index\n' >"${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index"
  printf 'cached-package\n' >"${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb"
  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  printf 'prior-source-config\n' >"$APT_DEB822_FILE"
  printf 'prior-apt-config\n' >"$APT_CONF_FILE"
  local cache_index_before cache_package_before
  cache_index_before="$(sha256sum "${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index")"
  cache_package_before="$(sha256sum "${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb")"
  DRY_RUN=false
  SKIP_UPDATE=true
  CODENAME=noble
  SELECTED_MIRROR="https://example.invalid/ubuntu"
  SELECTED_TIME="0.001"
  _apply_changes >/dev/null 2>&1
  assert_file_contains "${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index" "cached-index" "skip-update preserves package lists"
  assert_file_contains "${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb" "cached-package" "skip-update preserves downloaded packages"
  local skip_backup
  skip_backup="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' | sort -rn | head -1 | cut -f2)"
  _restore_backup "$skip_backup" >/dev/null 2>&1

  rm -f "$APT_DEB822_FILE" "$APT_CONF_FILE"
  local backups_before backups_after atomic_before atomic_after
  backups_before="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  atomic_before="$(sha256sum "${APT_SOURCES_DIR}/atomic.conf")"
  DRY_RUN=true
  SKIP_UPDATE=false
  SELECTED_MIRROR="https://example.invalid/ubuntu"
  SELECTED_TIME="0.001"
  _apply_changes >/dev/null 2>&1
  backups_after="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  atomic_after="$(sha256sum "${APT_SOURCES_DIR}/atomic.conf")"
  ((_tests_run += 1))
  if [[ ! -e "$APT_DEB822_FILE" && ! -e "$APT_CONF_FILE" && "$backups_before" == "$backups_after" && "$atomic_before" == "$atomic_after" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b dry-run leaves APT files and backup count unchanged\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b dry-run leaves APT files and backup count unchanged\n' "$RED" "$RESET"
  fi

  local backup_failure=0
  tar() { return 1; }
  _create_backup >/dev/null 2>&1 || backup_failure=$?
  unset -f tar
  assert_exit_code 7 "$backup_failure" "backup creation fails closed when tar fails"

  local atomic_failure=0
  cat() { return 1; }
  _atomic_write "${APT_SOURCES_DIR}/must-not-exist.conf" 0600 <<<"blocked" >/dev/null 2>&1 || atomic_failure=$?
  unset -f cat
  assert_exit_code 1 "$atomic_failure" "atomic write reports temporary write failure"
  ((_tests_run += 1))
  if [[ ! -e "${APT_SOURCES_DIR}/must-not-exist.conf" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b failed atomic write leaves no destination file\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b failed atomic write leaves no destination file\n' "$RED" "$RESET"
  fi

  printf 'write-rollback-sources-list\n' >"$APT_SOURCES_FILE"
  printf 'write-rollback-source-config\n' >"$APT_DEB822_FILE"
  printf 'write-rollback-apt-config\n' >"$APT_CONF_FILE"
  local write_rollback_code=0
  (
    local write_mv_calls=0
    mv() {
      write_mv_calls=$((write_mv_calls + 1))
      if [[ "$write_mv_calls" -eq 2 ]]; then
        return 1
      fi
      command mv "$@"
    }
    DRY_RUN=false
    SKIP_UPDATE=true
    CODENAME=noble
    SELECTED_MIRROR="https://broken.example/ubuntu"
    SELECTED_TIME="0.001"
    _apply_changes >/dev/null 2>&1
  ) || write_rollback_code=$?
  assert_exit_code 1 "$write_rollback_code" "APT config write failure returns general error"
  assert_file_contains "$APT_SOURCES_FILE" "write-rollback-sources-list" "APT write failure restores legacy sources.list"
  assert_file_contains "$APT_DEB822_FILE" "write-rollback-source-config" "APT write failure restores deb822 source"
  assert_file_contains "$APT_CONF_FILE" "write-rollback-apt-config" "APT write failure restores previous apt config"

  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  printf 'prior-source-config\n' >"$APT_DEB822_FILE"
  printf 'prior-apt-config\n' >"$APT_CONF_FILE"
  local rollback_code=0
  (
    apt-get() { return 1; }
    DRY_RUN=false
    SKIP_UPDATE=false
    SELECTED_MIRROR="https://broken.example/ubuntu"
    SELECTED_TIME="0.001"
    _apply_changes >/dev/null 2>&1
  ) || rollback_code=$?
  assert_exit_code 3 "$rollback_code" "failed apt-get update returns network exit code after rollback"
  assert_file_contains "$APT_SOURCES_FILE" "archive.ubuntu.com" "failed update restores legacy sources.list"
  assert_file_contains "$APT_DEB822_FILE" "prior-source-config" "failed update restores prior deb822 content"
  assert_file_contains "$APT_CONF_FILE" "prior-apt-config" "failed update restores prior apt config"

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
quote " slash \\ tab\t newline\n'
  printf '{"value":%s}\n' "$(_json_quote "$escaped_value")" >"$escaped_json"
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1], encoding="utf-8"))["value"] == "quote \" slash \\ tab\t newline\n"' "$escaped_json"
  assert_exit_code 0 "$?" "JSON quoting escapes quotes, slashes, tabs and newlines"

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
  local restore_log="${_TEST_ROOT}/restore.log"
  _restore_backup "$backup_dir" >"$restore_log" 2>&1 || restore_status=$?
  if [[ "$restore_status" -ne 0 ]]; then
    printf '%s\n' 'Restore diagnostic:'
    cat "$restore_log"
  fi
  assert_exit_code 0 "$restore_status" "restore succeeds"
  assert_file_contains "$APT_SOURCES_FILE" "old.example" "restore restores sources.list content"
  assert_file_contains "${APT_SOURCES_DIR}/ubuntu.sources" "old.example" "restore restores sources directory content"
  ((_tests_run += 1))
  if [[ ! -e "$APT_CONF_DIR" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b restore removes directories absent from snapshot\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b restore removes directories absent from snapshot\n' "$RED" "$RESET"
  fi

  local restored_mode
  restored_mode="$(stat -c '%a' "$APT_SOURCES_FILE")"
  assert_contains "640" "$restored_mode" "restore preserves original file mode"

  printf 'current-sources-list\n' >"$APT_SOURCES_FILE"
  printf 'current-deb822\n' >"${APT_SOURCES_DIR}/ubuntu.sources"
  mkdir -p "$APT_CONF_DIR"
  printf 'current-apt-config\n' >"${APT_CONF_DIR}/99-current"
  local mv_calls=0 injected_restore_code=0
  mv() {
    mv_calls=$((mv_calls + 1))
    if [[ "$mv_calls" -eq 5 ]]; then
      return 1
    fi
    command mv "$@"
  }
  _restore_backup "$backup_dir" >/dev/null 2>&1 || injected_restore_code=$?
  unset -f mv
  assert_exit_code 8 "$injected_restore_code" "restore reports a failed snapshot install"
  assert_file_contains "$APT_SOURCES_FILE" "current-sources-list" "failed restore recovers original sources.list"
  assert_file_contains "${APT_SOURCES_DIR}/ubuntu.sources" "current-deb822" "failed restore recovers original source directory"
  assert_file_contains "${APT_CONF_DIR}/99-current" "current-apt-config" "failed restore recovers original apt config directory"

  rm -f "$APT_SOURCES_FILE"
  rm -rf "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  local empty_backup empty_restore_status=0
  empty_backup="$(_create_backup)"
  mkdir -p "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'new source file\n' >"$APT_SOURCES_FILE"
  printf 'new source entry\n' >"${APT_SOURCES_DIR}/new.list"
  printf 'new apt config\n' >"${APT_CONF_DIR}/99-new"
  _restore_backup "$empty_backup" >/dev/null 2>&1 || empty_restore_status=$?
  assert_exit_code 0 "$empty_restore_status" "restore accepts an empty APT snapshot"
  ((_tests_run += 1))
  if [[ ! -e "$APT_SOURCES_FILE" && ! -e "$APT_SOURCES_DIR" && ! -e "$APT_CONF_DIR" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b empty snapshot removes all subsequently created managed paths\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b empty snapshot removes all subsequently created managed paths\n' "$RED" "$RESET"
  fi

  mkdir -p "$APT_SOURCES_DIR"
  _atomic_write "${APT_SOURCES_DIR}/atomic.conf" 0600 <<'ATOMIC'
Acquire::Retries "7";
ATOMIC
  assert_file_contains "${APT_SOURCES_DIR}/atomic.conf" 'Acquire::Retries "7";' "atomic writer stores expected content"
  restored_mode="$(stat -c '%a' "${APT_SOURCES_DIR}/atomic.conf")"
  assert_contains "600" "$restored_mode" "atomic writer applies requested mode"
  ((_tests_run += 1))
  if [[ -z "$(find "$APT_SOURCES_DIR" -maxdepth 1 -name '*.tmp.*' -print -quit)" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b atomic writer leaves no temporary files\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
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
  ((_tests_run += 1))
  if ! grep -q 'Acquire::ForceIPv4' "$APT_CONF_FILE"; then
    ((_tests_passed += 1))
    printf '%bPASS%b IPv6 mode does not force IPv4 simultaneously\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
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

  mkdir -p "$APT_SOURCES_DIR" "$APT_CONF_DIR" "${_SYSTEM_ROOT}/var/lib/apt/lists" "${_SYSTEM_ROOT}/var/cache/apt/archives"
  printf 'cached-index\n' >"${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index"
  printf 'cached-package\n' >"${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb"
  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  printf 'prior-source-config\n' >"$APT_DEB822_FILE"
  printf 'prior-apt-config\n' >"$APT_CONF_FILE"
  local cache_index_before cache_package_before
  cache_index_before="$(sha256sum "${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index")"
  cache_package_before="$(sha256sum "${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb")"
  DRY_RUN=false
  SKIP_UPDATE=true
  CODENAME=noble
  SELECTED_MIRROR="https://example.invalid/ubuntu"
  SELECTED_TIME="0.001"
  _apply_changes >/dev/null 2>&1
  assert_file_contains "${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index" "cached-index" "skip-update preserves package lists"
  assert_file_contains "${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb" "cached-package" "skip-update preserves downloaded packages"
  local skip_backup
  skip_backup="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' | sort -rn | head -1 | cut -f2)"
  _restore_backup "$skip_backup" >/dev/null 2>&1

  rm -f "$APT_DEB822_FILE" "$APT_CONF_FILE"
  local backups_before backups_after atomic_before atomic_after
  backups_before="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  atomic_before="$(sha256sum "${APT_SOURCES_DIR}/atomic.conf")"
  DRY_RUN=true
  SKIP_UPDATE=false
  SELECTED_MIRROR="https://example.invalid/ubuntu"
  SELECTED_TIME="0.001"
  _apply_changes >/dev/null 2>&1
  backups_after="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  atomic_after="$(sha256sum "${APT_SOURCES_DIR}/atomic.conf")"
  ((_tests_run += 1))
  if [[ ! -e "$APT_DEB822_FILE" && ! -e "$APT_CONF_FILE" && "$backups_before" == "$backups_after" && "$atomic_before" == "$atomic_after" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b dry-run leaves APT files and backup count unchanged\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b dry-run leaves APT files and backup count unchanged\n' "$RED" "$RESET"
  fi

  local backup_failure=0
  tar() { return 1; }
  _create_backup >/dev/null 2>&1 || backup_failure=$?
  unset -f tar
  assert_exit_code 7 "$backup_failure" "backup creation fails closed when tar fails"

  local atomic_failure=0
  cat() { return 1; }
  _atomic_write "${APT_SOURCES_DIR}/must-not-exist.conf" 0600 <<<"blocked" >/dev/null 2>&1 || atomic_failure=$?
  unset -f cat
  assert_exit_code 1 "$atomic_failure" "atomic write reports temporary write failure"
  ((_tests_run += 1))
  if [[ ! -e "${APT_SOURCES_DIR}/must-not-exist.conf" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b failed atomic write leaves no destination file\n' "$GREEN" "$RESET"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b failed atomic write leaves no destination file\n' "$RED" "$RESET"
  fi

  printf 'write-rollback-sources-list\n' >"$APT_SOURCES_FILE"
  printf 'write-rollback-source-config\n' >"$APT_DEB822_FILE"
  printf 'write-rollback-apt-config\n' >"$APT_CONF_FILE"
  local write_rollback_code=0
  (
    local write_mv_calls=0
    mv() {
      write_mv_calls=$((write_mv_calls + 1))
      if [[ "$write_mv_calls" -eq 2 ]]; then
        return 1
      fi
      command mv "$@"
    }
    DRY_RUN=false
    SKIP_UPDATE=true
    CODENAME=noble
    SELECTED_MIRROR="https://broken.example/ubuntu"
    SELECTED_TIME="0.001"
    _apply_changes >/dev/null 2>&1
  ) || write_rollback_code=$?
  assert_exit_code 1 "$write_rollback_code" "APT config write failure returns general error"
  assert_file_contains "$APT_SOURCES_FILE" "write-rollback-sources-list" "APT write failure restores legacy sources.list"
  assert_file_contains "$APT_DEB822_FILE" "write-rollback-source-config" "APT write failure restores deb822 source"
  assert_file_contains "$APT_CONF_FILE" "write-rollback-apt-config" "APT write failure restores previous apt config"

  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  printf 'prior-source-config\n' >"$APT_DEB822_FILE"
  printf 'prior-apt-config\n' >"$APT_CONF_FILE"
  local rollback_code=0
  (
    apt-get() { return 1; }
    DRY_RUN=false
    SKIP_UPDATE=false
    SELECTED_MIRROR="https://broken.example/ubuntu"
    SELECTED_TIME="0.001"
    _apply_changes >/dev/null 2>&1
  ) || rollback_code=$?
  assert_exit_code 3 "$rollback_code" "failed apt-get update returns network exit code after rollback"
  assert_file_contains "$APT_SOURCES_FILE" "archive.ubuntu.com" "failed update restores legacy sources.list"
  assert_file_contains "$APT_DEB822_FILE" "prior-source-config" "failed update restores prior deb822 content"
  assert_file_contains "$APT_CONF_FILE" "prior-apt-config" "failed update restores prior apt config"

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
