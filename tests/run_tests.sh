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

assert_equal() {
  local expected="$1" actual="$2" name="$3"
  ((_tests_run += 1))
  if [[ "$actual" == "$expected" ]]; then
    ((_tests_passed += 1))
    printf '%bPASS%b %s\n' "$GREEN" "$RESET" "$name"
  else
    ((_tests_failed += 1))
    printf '%bFAIL%b %s (values differ)\n' "$RED" "$RESET" "$name"
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
  assert_contains "--refresh-catalog" "$(bash "$SCRIPT" --help 2>&1)" "help documents mirror index refresh"
  assert_contains "--official-only" "$(bash "$SCRIPT" --help 2>&1)" "help documents official-only benchmark profile"
  assert_contains "--add-mirror" "$(bash "$SCRIPT" --help 2>&1)" "help documents custom mirror management"

  code=0
  bash "$SCRIPT" </dev/null >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "default non-interactive invocation never blocks or mutates"

  code=0
  bash "$SCRIPT" --menu </dev/null >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "explicit menu rejects non-interactive input"

  code=0
  bash "$SCRIPT" --mirror https://mirror.example.invalid/ubuntu </dev/null >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "non-interactive mirror apply requires explicit yes before probing"

  code=0
  bash "$SCRIPT" --status --doctor >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "conflicting report modes are rejected"

  code=0
  bash "$SCRIPT" --restore --dry-run >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "restore cannot be combined with dry-run"

  code=0
  bash "$SCRIPT" --restore --skip-update >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "restore cannot be combined with skip-update"

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

  code=0
  bash "$SCRIPT" --workers 0 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "worker count below the limit is rejected"

  code=0
  bash "$SCRIPT" --workers 9 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "worker count above the limit is rejected"

  code=0
  bash "$SCRIPT" --retries 4 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "retry count above the limit is rejected"

  code=0
  bash "$SCRIPT" --status --official-only >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "read-only status rejects benchmark profile flags"

  code=0
  bash "$SCRIPT" --disable-mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "custom mirror management requires a mirror ID"
  code=0
  bash "$SCRIPT" --apt-retries 11 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "APT retry count above maximum is rejected"
  code=0
  bash "$SCRIPT" --proxy http://user:secret@proxy.example:8080 --dry-run >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "proxy credentials are rejected"
  code=0
  bash "$SCRIPT" --clear-proxy --proxy http://127.0.0.1:3128 --dry-run >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "proxy set and clear options cannot be combined"
  code=0
  bash "$SCRIPT" --restore --restore-scope invalid >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown selective restore scope is rejected"
  code=0
  bash "$SCRIPT" --network-diagnostics >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "live diagnostics require doctor mode"
  code=0
  bash "$SCRIPT" --prune-backups 0 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "backup retention count below one is rejected"

}

test_filesystem_operations() {
  _TEST_ROOT="$(mktemp -d)"
  export POWER_APT_BOOST_TEST_MODE=1
  export POWER_APT_BOOST_TEST_ROOT="$_TEST_ROOT"
  export POWER_APT_BOOST_SOURCE_ONLY=1

  # shellcheck source=../power-apt-boost.sh
  source "$SCRIPT"
  _setup_colors
  apt-get() {
    local arg
    for arg in "$@"; do
      [[ "$arg" != --print-uris ]] || return 0
    done
    return 1
  }
  write_managed_source_fixture() {
    local mirror="${1:-https://old.example/ubuntu}"
    cat >"$APT_DEB822_FILE" <<SOURCES
# Power APT Boost test fixture
# Mirror: $mirror
Types: deb
URIs: $mirror
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: $KEYRING_PATH

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: $KEYRING_PATH
SOURCES
  }
  write_managed_config_fixture() {
    mkdir -p "$APT_CONF_DIR"
    printf '# Power APT Boost test fixture\nprior-apt-config\n' >"$APT_CONF_FILE"
  }
  mkdir -p "$APT_ETC_DIR" "$APT_SOURCES_DIR"
  printf 'cancel-before-state\n' >"$APT_DEB822_FILE"

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
  before_cancel="$(sha256sum "$APT_DEB822_FILE")"
  _is_interactive() { return 0; }
  YES=false
  _confirm_apply <"$cancel_input" >/dev/null 2>&1 || cancel_status=$?
  unset -f _is_interactive
  after_cancel="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 10 "$cancel_status" "declining an apply preview returns cancelled"
  assert_equal "$before_cancel" "$after_cancel" "cancel leaves APT configuration content unchanged"

  local escaped_json
  escaped_json="$(mktemp "${TMPDIR:-/tmp}/power-apt-boost-json.XXXXXX")"
  local escaped_value
  escaped_value='quote " slash \\ literal'
  printf '{"value":%s}\n' "$(_json_quote "$escaped_value")" >"$escaped_json"
  local json_escape_status=0
  python3 - "$escaped_json" "$escaped_value" <<'PY' || json_escape_status=$?
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    actual = json.load(stream)["value"]
assert actual == sys.argv[2]
PY
  assert_exit_code 0 "$json_escape_status" "JSON quoting round-trips quotes and backslashes"
  rm -f "$escaped_json"

  printf 'deb http://old.example/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  write_managed_source_fixture
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
  APT_RETRIES=6
  APT_PROXY="http://127.0.0.1:3128"
  CLEAR_APT_PROXY=false
  _write_apt_config
  assert_file_contains "$APT_CONF_FILE" 'Acquire::Retries "6";' "APT config applies configured retry count"
  assert_file_contains "$APT_CONF_FILE" 'Acquire::http::Proxy "http://127.0.0.1:3128";' "APT config applies explicit proxy"
  APT_PROXY=""
  _write_apt_config
  assert_file_contains "$APT_CONF_FILE" 'Acquire::https::Proxy "http://127.0.0.1:3128";' "unspecified proxy setting preserves existing managed proxy"
  CLEAR_APT_PROXY=true
  _write_apt_config
  assert_file_contains "$APT_CONF_FILE" 'Acquire::https::Proxy "DIRECT";' "clear-proxy explicitly bypasses APT proxies"
  CLEAR_APT_PROXY=false
  APT_RETRIES=3
  local proxy_result proxy_status=0
  proxy_result="$(_validate_proxy_url "https://proxy.example:8443")"
  assert_equal "https://proxy.example:8443" "$proxy_result" "proxy URL validator accepts a host and port"
  _validate_proxy_url "http://user:secret@proxy.example:3128" >/dev/null 2>&1 || proxy_status=$?
  assert_exit_code 1 "$proxy_status" "proxy URL validator rejects embedded credentials"
  printf 'deb [arch=amd64 signed-by=/usr/share/keyrings/example.gpg] https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  write_managed_source_fixture "https://archive.ubuntu.com/ubuntu"
  CODENAME=noble
  _write_apt_sources "https://archive.ubuntu.com/ubuntu" >/dev/null 2>&1
  assert_file_contains "$APT_SOURCES_FILE" "signed-by=/usr/share/keyrings/example.gpg" "legacy Ubuntu source options are preserved"
  rm -f "$APT_SOURCES_FILE"

  printf '# Power APT Boost test fixture\n# Mirror: https://archive.ubuntu.com/ubuntu\nAcquire::Languages "none";\nAcquire::Custom::Option "keep";\n' >"$APT_CONF_FILE"
  local unmanaged_config_status=0
  _write_apt_config >/dev/null 2>&1 || unmanaged_config_status=$?
  assert_exit_code 1 "$unmanaged_config_status" "managed APT config refuses an unexpected custom directive"
  assert_file_contains "$APT_CONF_FILE" 'Acquire::Custom::Option "keep";' "refused APT config overwrite leaves custom directive intact"
  write_managed_config_fixture

  dpkg() { printf 'mips64el\n'; }
  local unsupported_arch_status=0
  _apt_architecture_supported || unsupported_arch_status=$?
  assert_exit_code 1 "$unsupported_arch_status" "unsupported architecture does not default to standard archive"
  unset -f dpkg

  dpkg() { printf 'arm64\n'; }
  local ports_mode=1 ports_mirrors
  _uses_ports_archive && ports_mode=0
  assert_exit_code 0 "$ports_mode" "non-x86 architecture uses the Ubuntu ports archive"
  ports_mirrors="$(_get_mirrors)"
  assert_contains "https://ports.ubuntu.com/ubuntu-ports" "$ports_mirrors" "ports catalog is available for non-x86 architecture"
  unset -f dpkg


  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK=false
  COUNTRY_FILTER=ir
  local iran_mirrors
  iran_mirrors="$(_get_mirrors)"
  assert_contains "https://mirror.arvancloud.ir/ubuntu" "$iran_mirrors" "Iran filter includes provider mirrors"
  assert_contains "https://mirror.iranserver.com/ubuntu" "$iran_mirrors" "Iran filter includes IranServer"
  COUNTRY_FILTER=""
  assert_contains "https://archive.ubuntu.com/ubuntu" "$(_get_mirrors)" "unfiltered catalog includes global mirror"
  rm -f "$APT_SOURCES_FILE" "$APT_DEB822_FILE"
  rm -f "$APT_SOURCES_DIR"/*.list "$APT_SOURCES_DIR"/*.sources
  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  cat >"${APT_SOURCES_DIR}/inventory-thirdparty.list" <<'LIST'
deb https://packages.example.test/apt stable main
LIST
  cat >"${APT_SOURCES_DIR}/inventory-duplicate.sources" <<'SOURCES'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: noble
Components: main
SOURCES
  _collect_source_inventory
  assert_equal "3" "$APT_SOURCE_TOTAL" "APT inventory counts active source records"
  assert_equal "2" "$APT_SOURCE_UBUNTU" "APT inventory classifies Ubuntu archive sources"
  assert_equal "1" "$APT_SOURCE_THIRD_PARTY" "APT inventory classifies third-party sources"
  assert_equal "1" "$APT_SOURCE_DUPLICATES" "APT inventory detects duplicate URI/suite records"
  rm -f "${APT_SOURCES_DIR}/inventory-thirdparty.list" "${APT_SOURCES_DIR}/inventory-duplicate.sources"


  NO_SPINNER=true
  _start_spinner "test"
  local spinner_code=1
  [[ -z "$_spinner_pid" ]] && spinner_code=0
  assert_exit_code 0 "$spinner_code" "no-spinner prevents spinner startup"

  mkdir -p "$APT_SOURCES_DIR" "$APT_CONF_DIR" "${_SYSTEM_ROOT}/var/lib/apt/lists" "${_SYSTEM_ROOT}/var/cache/apt/archives"
  printf 'cached-index\n' >"${_SYSTEM_ROOT}/var/lib/apt/lists/fixture-index"
  printf 'cached-package\n' >"${_SYSTEM_ROOT}/var/cache/apt/archives/fixture.deb"
  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n' >"$APT_SOURCES_FILE"
  write_managed_source_fixture "https://archive.ubuntu.com/ubuntu"
  printf 'prior-source-config\n' >>"$APT_DEB822_FILE"
  write_managed_config_fixture
  printf 'prior-apt-config\n' >>"$APT_CONF_FILE"
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
  assert_file_contains "$APT_DEB822_FILE" 'Suites: noble noble-updates noble-backports' "Ubuntu archive stanza keeps security suite separate"
  assert_file_contains "$APT_DEB822_FILE" 'URIs: https://security.ubuntu.com/ubuntu' "security suite uses the dedicated Ubuntu archive"
  printf '\nTypes: deb\nURIs: https://thirdparty.example.test/ubuntu\nSuites: stable\nComponents: main\n' >>"$APT_DEB822_FILE"
  local unmanaged_before unmanaged_after unmanaged_status=0
  unmanaged_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://example.invalid/ubuntu" >/dev/null 2>&1 || unmanaged_status=$?
  unmanaged_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$unmanaged_status" "APT writer refuses an extra repository in a managed Deb822 file"
  assert_equal "$unmanaged_before" "$unmanaged_after" "refused managed source overwrite leaves the file unchanged"

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

  printf 'deb https://archive.ubuntu.com/ubuntu noble main\n# write-rollback-sources-list\n' >"$APT_SOURCES_FILE"
  write_managed_source_fixture "https://archive.ubuntu.com/ubuntu"
  printf 'write-rollback-source-config\n' >>"$APT_DEB822_FILE"
  write_managed_config_fixture
  printf 'write-rollback-apt-config\n' >>"$APT_CONF_FILE"
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
  write_managed_source_fixture "https://archive.ubuntu.com/ubuntu"
  printf 'prior-source-config\n' >>"$APT_DEB822_FILE"
  write_managed_config_fixture
  printf 'prior-apt-config\n' >>"$APT_CONF_FILE"
  local rollback_code=0
  SELECTED_MIRROR="https://broken.example/ubuntu"
  SELECTED_TIME="0.001"
  (
    apt-get() {
      local arg
      for arg in "$@"; do
        [[ "$arg" != --print-uris ]] || return 0
      done
      return 1
    }
    DRY_RUN=false
    SKIP_UPDATE=false
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
  write_managed_source_fixture "https://archive.ubuntu.com/ubuntu"
  write_managed_config_fixture
  local selective_backup selective_restore_status=0
  selective_backup="$(_create_backup)"
  write_managed_source_fixture "https://newer.example/ubuntu"
  printf '# Power APT Boost test fixture\ncurrent-network-will-be-restored\n' >"$APT_CONF_FILE"
  RESTORE_SCOPE=network
  YES=true
  _run_restore_flow >/dev/null 2>&1 || selective_restore_status=$?
  assert_exit_code 0 "$selective_restore_status" "network-only restore succeeds without apt-get update"
  assert_contains "newer.example" "$(cat "$APT_DEB822_FILE")" "network-only restore leaves APT sources untouched"
  assert_file_contains "$APT_CONF_FILE" "prior-apt-config" "network-only restore restores network settings"
  RESTORE_SCOPE=all
  YES=false

  local verified_count=0 snapshot
  _create_backup >/dev/null
  sleep 1
  printf 'snapshot-b\n' >"${APT_SOURCES_DIR}/prune-marker"
  _create_backup >/dev/null
  sleep 1
  printf 'snapshot-c\n' >"${APT_SOURCES_DIR}/prune-marker"
  _create_backup >/dev/null
  PRUNE_BACKUPS_KEEP=1
  YES=true
  _run_prune_backups >/dev/null 2>&1
  for snapshot in "$BACKUP_BASE"/*; do
    [[ -d "$snapshot" && ! -L "$snapshot" && -f "$snapshot/manifest" && -f "$snapshot/archive.sha256" ]] || continue
    grep -qx 'format=1' "$snapshot/manifest" || continue
    (cd "$snapshot" && sha256sum -c archive.sha256 >/dev/null 2>&1) || continue
    ((verified_count += 1))
  done
  assert_equal "1" "$verified_count" "backup cleanup retains only the requested newest verified snapshot"
  PRUNE_BACKUPS_KEEP=""
  YES=false
}

test_probe_parser_and_list_criteria() {
  _probe_url_code() {
    case "$1" in
    */noble/InRelease) printf '200\t0.010000\t0\t%s\tvalid\tvalid\tnot-declared\t\n' "$1" ;;
    */noble-updates/InRelease) printf '200\t0.020000\t0\t%s\tvalid\tvalid\tnot-declared\t\n' "$1" ;;
    */noble-security/InRelease) printf '200\t0.030000\t0\t%s\tvalid\tvalid\tnot-declared\t\n' "$1" ;;
    *) printf '404\t0.040000\t0\t%s\tinvalid\tunknown\tunknown\tmissing_endpoint\n' "$1" ;;
    esac
  }

  local result_file
  result_file="$(mktemp)"
  _test_mirror "https://fixture.invalid/ubuntu" "$result_file" "noble" >/dev/null 2>&1
  assert_contains "true|" "$(cat "$result_file")" "mirror tester accepts three compatible signed endpoints"
  rm -f "$result_file"

  result_file="$(mktemp)"
  _test_mirror "https://fixture.invalid/ubuntu" "$result_file" "other" >/dev/null 2>&1
  assert_contains "false|" "$(cat "$result_file")" "mirror tester rejects incompatible endpoint coverage"
  rm -f "$result_file"
}
test_catalog_and_release_metadata() {
  local code output body cache_entry user_entry mode
  local curl_args_file="${_TEST_ROOT}/catalog-curl.args"
  curl() {
    printf '%s\n' "$@" >"$curl_args_file"
    return 0
  }
  _download_catalog_file "${_TEST_ROOT}/catalog-index.download"
  unset -f curl
  assert_contains "--proto" "$(cat "$curl_args_file")" "catalog fetch defines an explicit URL protocol policy"
  assert_contains "=http,https" "$(cat "$curl_args_file")" "catalog fetch allows Ubuntu's published HTTP index"
  assert_contains "--proto-redir" "$(cat "$curl_args_file")" "catalog fetch defines a redirect protocol policy"
  assert_contains "=https" "$(cat "$curl_args_file")" "catalog fetch permits redirects only to HTTPS"

  local redirect_headers="${_TEST_ROOT}/catalog-redirects.headers"
  printf '  Location: https://index.example.test/mirrors.txt\n' >"$redirect_headers"
  code=0
  _validate_https_redirect_headers "$redirect_headers" || code=$?
  assert_exit_code 0 "$code" "wget catalog fallback accepts HTTPS redirect targets"
  printf '  Location: http://index.example.test/mirrors.txt\n' >"$redirect_headers"
  code=0
  _validate_https_redirect_headers "$redirect_headers" || code=$?
  assert_exit_code 1 "$code" "wget catalog fallback rejects HTTP redirect targets"

  body="${_TEST_ROOT}/InRelease.fixture"
  cat >"$body" <<EOF
Origin: Ubuntu
Label: Ubuntu
Suite: noble-updates
Codename: noble
Date: $(date -u -R)
Valid-Until: $(date -u -d '+2 days' -R)
EOF

  output="$(_validate_release_metadata "$body" "noble" "noble-updates")"
  assert_contains "valid|ok|valid-until" "$output" "Release metadata accepts a matching fresh Ubuntu suite"

  sed 's/^Origin: Ubuntu$/Origin: Example/' "$body" >"${body}.bad-origin"
  code=0
  _validate_release_metadata "${body}.bad-origin" "noble" "noble-updates" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Release metadata rejects a non-Ubuntu origin"

  code=0
  _validate_release_metadata "$body" "jammy" "noble-updates" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Release metadata rejects a mismatched codename"

  sed "s/^Date:.*/Date: $(date -u -d '9 days ago' -R)/" "$body" >"${body}.stale"
  output="$(_validate_release_metadata "${body}.stale" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|stale_release_metadata|stale" "$output" "Release metadata older than seven days is rejected"

  sed "s/^Valid-Until:.*/Valid-Until: $(date -u -d '1 day ago' -R)/" "$body" >"${body}.expired"
  output="$(_validate_release_metadata "${body}.expired" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|expired_release_metadata|expired" "$output" "expired Valid-Until metadata is rejected"

  assert_equal "https://example.com/ubuntu" "$(_validate_mirror_url "https://example.com/ubuntu/")" "mirror URL normalization strips trailing slash"
  code=0
  _validate_mirror_url "https://user@example.com/ubuntu" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "mirror URL validator rejects embedded credentials"
  code=0
  _validate_mirror_url "https://example.com/ubuntu?mirror=other" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "mirror URL validator rejects query strings"
  code=0
  _validate_mirror_url "https://example.com/not-ubuntu" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "mirror URL validator rejects unsupported archive roots"

  NO_CATALOG_NETWORK=true
  mkdir -p "$(dirname "$CATALOG_CACHE_FILE")"
  cache_entry="fixture-index|auto|Fixture|https://index-fixture.example/ubuntu|ubuntu-index|false|true"
  printf '# power-apt-boost-catalog-v1\n# fetched_at=%s\n%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$cache_entry" >"$CATALOG_CACHE_FILE"
  chmod 0600 "$CATALOG_CACHE_FILE"
  _load_mirror_catalog
  assert_equal "local-cache" "$CATALOG_CACHE_STATE" "offline catalog load uses a valid local cache"
  assert_contains "https://index-fixture.example/ubuntu" "${_CATALOG_URLS[*]}" "valid cached dynamic mirror is loaded"
  assert_contains "ubuntu-index" "$CATALOG_SOURCE" "catalog provenance reports the Ubuntu mirror index"

  printf '# power-apt-boost-catalog-v999\n%s\n' "$cache_entry" >"$CATALOG_CACHE_FILE"
  _load_mirror_catalog
  assert_equal "invalid-cache" "$CATALOG_CACHE_STATE" "catalog cache schema mismatch is rejected"
  code=0
  [[ " ${_CATALOG_URLS[*]} " != *" https://index-fixture.example/ubuntu "* ]] || code=1
  assert_exit_code 0 "$code" "invalid cached records are not loaded"

  printf '# power-apt-boost-catalog-v1\n# fetched_at=%s\n%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$cache_entry" >"$CATALOG_CACHE_FILE"
  chmod 0600 "$CATALOG_CACHE_FILE"
  NO_CATALOG_NETWORK=false
  REFRESH_CATALOG=true
  _download_catalog_file() { return 1; }
  _load_mirror_catalog
  unset -f _download_catalog_file
  assert_equal "stale-fallback" "$CATALOG_CACHE_STATE" "catalog discovery failure falls back to last known-good cache"
  assert_contains "https://index-fixture.example/ubuntu" "${_CATALOG_URLS[*]}" "stale fallback keeps valid cached mirrors"

  REFRESH_CATALOG=true
  _download_catalog_file() {
    printf '%s\n' "https://fresh-fixture.example/ubuntu" "https://fresh-fixture.example/not-ubuntu" "https://fresh-fixture.example/ubuntu" >"$1"
  }
  _load_mirror_catalog
  unset -f _download_catalog_file
  assert_equal "refreshed" "$CATALOG_CACHE_STATE" "successful index discovery atomically refreshes the catalog cache"
  assert_contains "https://fresh-fixture.example/ubuntu" "${_CATALOG_URLS[*]}" "valid discovered mirror is added"
  assert_equal "false" "${_CATALOG_OFFICIAL[-1]}" "discovered mirror is not mislabelled as an officially verified host"
  mode="$(stat -c '%a' "$CATALOG_CACHE_FILE")"
  assert_equal "600" "$mode" "mirror catalog cache is private to root"
  assert_contains "ubuntu-index" "$CATALOG_SOURCE" "fresh discovery is reflected in catalog provenance"

  _catalog_add_entry "user-fixture" "auto" "Fixture" "https://custom-fixture.example/ubuntu" "user" false true
  _write_user_mirror_catalog
  mode="$(stat -c '%a' "$USER_MIRRORS_FILE")"
  assert_equal "600" "$mode" "custom mirror catalog is written with private permissions"
  _load_mirror_catalog
  assert_contains "https://custom-fixture.example/ubuntu" "${_CATALOG_URLS[*]}" "custom mirror survives catalog reload"
  assert_contains "custom-fixture" "$(cat "$USER_MIRRORS_FILE")" "custom mirror is persisted as an app-owned entry"

  NO_CATALOG_NETWORK=true
  COUNTRY_FILTER=ir
  _load_mirror_catalog
  output="$(_get_mirrors)"
  assert_contains "https://mirror.arvancloud.ir/ubuntu" "$output" "Iran region filter keeps built-in Iranian mirrors"
  COUNTRY_FILTER=""
  OFFICIAL_ONLY=true
  output="$(_get_mirrors)"
  assert_contains "https://archive.ubuntu.com/ubuntu" "$output" "official-only profile retains official archive"
  code=0
  [[ "$output" != *"https://index-fixture.example/ubuntu"* ]] || code=1
  assert_exit_code 0 "$code" "official-only profile excludes unverified discovery entries"
  OFFICIAL_ONLY=false
  NO_CATALOG_NETWORK=false
}

test_benchmark_selection_and_read_only_safety() {
  local before after code
  local original_quiet="$QUIET" original_spinner="$NO_SPINNER" original_workers="$BENCH_WORKERS"
  QUIET=true
  NO_SPINNER=true
  BENCH_WORKERS=2
  CODENAME=noble
  _load_mirror_catalog() {
    CATALOG_SOURCE="fixture"
    CATALOG_CACHE_STATE="fixture"
  }
  _get_mirrors() {
    printf '%s\n' "https://slow-fixture.example/ubuntu" "https://fast-fixture.example/ubuntu" "https://unverified-fixture.example/ubuntu"
  }
  _test_mirror() {
    case "$1" in
    *slow-fixture*)
      printf 'true|0.300000|0.300000|200|200|200|0|valid-until|verified\n' >"$2"
      ;;
    *fast-fixture*)
      printf 'true|0.100000|0.100000|200|200|200|0|valid-until|verified\n' >"$2"
      ;;
    *unverified-fixture*)
      printf 'false|0.001000|0.001000|200|200|200|0|valid-until|not-fully-verified|invalid_archive_signature\n' >"$2"
      ;;
    esac
  }
  before="$(sha256sum "$APT_DEB822_FILE")"
  _select_mirror >/dev/null 2>&1
  after="$(sha256sum "$APT_DEB822_FILE")"
  assert_equal "https://fast-fixture.example/ubuntu" "$SELECTED_MIRROR" "benchmark selects the fastest eligible mirror"
  assert_equal "$before" "$after" "benchmark does not modify APT configuration"
  code=0
  [[ "$SELECTED_MIRROR" != "https://unverified-fixture.example/ubuntu" ]] || code=1
  assert_exit_code 0 "$code" "an unverified mirror cannot win with a lower latency score"
  unset -f _load_mirror_catalog _get_mirrors _test_mirror
  QUIET="$original_quiet"
  NO_SPINNER="$original_spinner"
  BENCH_WORKERS="$original_workers"
}

main() {
  printf '\nPower APT Boost — Offline Test Suite\n'
  printf '%s\n' '===================================='
  test_cli
  test_filesystem_operations
  test_probe_parser_and_list_criteria
  test_catalog_and_release_metadata
  test_benchmark_selection_and_read_only_safety
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"
