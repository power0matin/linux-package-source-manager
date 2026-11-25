#!/usr/bin/env bash
#
# Linux Package Source Manager — Offline regression and safety tests
#
# Run: bash tests/run_tests.sh

set -Eeuo pipefail

# This test intentionally sources the script and mutates its globals/functions.
# shellcheck disable=SC2034,SC2329

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR
SCRIPT="${PROJECT_DIR}/src/linux-package-source-manager.sh"
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
  local output code banner_source terminal_source readme_source logo_asset_state icon_asset_state menu_source
  banner_source="$(sed -n '/^_print_banner() {/,/^}/p' "$SCRIPT")"
  assert_contains "LINUX PACKAGE SOURCE MANAGER" "$banner_source" "terminal banner displays the product name"
  assert_contains "APT | PyPI | npm | pnpm | Yarn | Docker / OCI" "$banner_source" "terminal banner lists supported ecosystems"
  if LC_ALL=C grep -q '[^ -~]' <<<"$banner_source"; then
    assert_equal "ASCII-only" "contains non-ASCII" "terminal banner uses ASCII-safe characters"
  else
    assert_equal "ASCII-only" "ASCII-only" "terminal banner uses ASCII-safe characters"
  fi

  terminal_source="$(
    sed -n \
      -e '/^_start_spinner() {/,/^}/p' \
      -e '/^_print_progress_bar() {/,/^}/p' \
      -e '/^_print_divider() {/,/^}/p' \
      -e '/^_print_section_header() {/,/^}/p' \
      -e '/^need_root() {/,/^}/p' \
      -e '/^_test_mirror() {/,/^}/p' \
      -e '/^_print_summary() {/,/^}/p' \
      -e '/^_print_status_report() {/,/^}/p' \
      -e '/^_doctor_report() {/,/^}/p' \
      "$SCRIPT"
  )"
  if LC_ALL=C grep -q '[^ -~]' <<<"$terminal_source"; then
    assert_equal "ASCII-only" "contains non-ASCII" "SSH terminal UI uses ASCII-safe characters"
  else
    assert_equal "ASCII-only" "ASCII-only" "SSH terminal UI uses ASCII-safe characters"
  fi

  readme_source="$(cat "$PROJECT_DIR/README.md")"
  [[ -s "$SCRIPT" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "main application source is stored under src/"
  [[ ! -e "$PROJECT_DIR/linux-package-source-manager.sh" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "duplicate application source is absent from repository root"
  [[ -s "$PROJECT_DIR/docs/ROADMAP.md" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "roadmap is stored under docs/"
  [[ ! -e "$PROJECT_DIR/ROADMAP.md" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "duplicate roadmap is absent from repository root"
  assert_contains "docs/ROADMAP.md" "$readme_source" "README links to the roadmap in docs/"
  if grep -Fq '<pre align="center">' <<<"$readme_source"; then
    assert_equal "monogram absent" "monogram present" "README does not include the removed ASCII monogram"
  else
    assert_equal "monogram absent" "monogram absent" "README does not include the removed ASCII monogram"
  fi
  assert_contains "bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)" "$readme_source" "README documents the recommended bootstrap"
  assert_contains "assets/logo.png" "$readme_source" "README displays the Tux LPSM logo"
  [[ -s "$PROJECT_DIR/assets/logo.png" ]] && logo_asset_state="present" || logo_asset_state="missing"
  assert_equal "present" "$logo_asset_state" "Tux LPSM logo asset exists"
  [[ -s "$PROJECT_DIR/assets/icon.png" ]] && icon_asset_state="present" || icon_asset_state="missing"
  assert_equal "present" "$icon_asset_state" "Tux LPSM square icon asset exists"
  assert_contains "sha256sum -c linux-package-source-manager.sh.sha256" "$readme_source" "README documents checksum verification"

  output="$(bash "$SCRIPT" --help 2>&1)"
  assert_contains "Linux Package Source Manager" "$output" "help displays product name"
  assert_contains "https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh" "$output" "help prints the verified bootstrap URL"
  assert_contains "bash <(curl -fsSL" "$output" "help shows the short interactive install command"
  assert_contains "--mirror https://archive.ubuntu.com/ubuntu --yes" "$output" "help shows an explicit non-interactive action"
  assert_contains "--restore" "$output" "help displays restore option"

  output="$(bash "$SCRIPT" --version 2>&1)"
  assert_contains "3.0.8" "$output" "version matches script version"
  menu_source="$(sed -n '/^_menu_manage_mirrors() {/,/^main() {/p' "$SCRIPT")"
  if grep -Eq '"back"[[:space:]]+"(Back|Cancel|Back to main menu)"|"quit"[[:space:]]+"Exit"|^[[:space:]]*(back|quit)\)' <<<"$menu_source"; then
    assert_equal "no duplicate navigation" "duplicate navigation" "interactive menus do not define separate Back or Exit actions"
  else
    assert_equal "no duplicate navigation" "no duplicate navigation" "interactive menus do not define separate Back or Exit actions"
  fi
  assert_contains '_menu_choose --zero-label "Exit"' "$menu_source" "main menu uses zero as its Exit action"
  assert_contains "--menu" "$(bash "$SCRIPT" --help 2>&1)" "help documents interactive menu"
  assert_contains "--doctor" "$(bash "$SCRIPT" --help 2>&1)" "help documents doctor command"
  assert_contains "--yes" "$(bash "$SCRIPT" --help 2>&1)" "help documents explicit non-interactive confirmation"
  assert_contains "--refresh-catalog" "$(bash "$SCRIPT" --help 2>&1)" "help documents mirror index refresh"
  assert_contains "--official-only" "$(bash "$SCRIPT" --help 2>&1)" "help documents official-only benchmark profile"
  assert_contains "--add-mirror" "$(bash "$SCRIPT" --help 2>&1)" "help documents custom mirror management"
  assert_contains "--python-status" "$(bash "$SCRIPT" --help 2>&1)" "help documents Python diagnostics"
  assert_contains "--python-test-index" "$(bash "$SCRIPT" --help 2>&1)" "help documents Python index verification"
  assert_contains "--python-set-index" "$(bash "$SCRIPT" --help 2>&1)" "help documents Python index configuration"

  assert_contains "--node-status" "$(bash "$SCRIPT" --help 2>&1)" "help documents Node.js registry diagnostics"
  assert_contains "--node-set-registry" "$(bash "$SCRIPT" --help 2>&1)" "help documents Node.js registry configuration"
  code=0
  bash "$SCRIPT" --node-client invalid --node-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown Node.js client is rejected"
  code=0
  bash "$SCRIPT" --node-scope invalid --node-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown Node.js scope is rejected"
  code=0
  bash "$SCRIPT" --node-status --node-reset-registry >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "conflicting Node.js actions are rejected before execution"
  code=0
  bash "$SCRIPT" --node-test-registry http://registry.npmjs.org/ >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "insecure Node.js registry is rejected before network access"
  code=0
  bash "$SCRIPT" --node-set-registry https://registry.npmjs.org/ --node-scope project >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "project registry requires an explicit project directory"
  code=0
  bash "$SCRIPT" --node-status --doctor >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Node.js command cannot be combined with APT doctor"
  code=0
  bash "$SCRIPT" --node-status --official-only >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Node.js command rejects APT mirror profile flags"
  code=0
  bash "$SCRIPT" --node-status --apt-retries 5 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Node.js command rejects APT apply options"
  code=0
  bash "$SCRIPT" --node-status --country us >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Node.js command rejects APT benchmark filters"
  code=0
  bash "$SCRIPT" --node-status --python-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Node.js and Python command modes cannot be combined"
  output="$(bash "$SCRIPT" --node-status --json 2>&1)"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["schema_version"] == 1 and d["command"] == "node-status" and "registry_hosts" in d and "environment_overrides" in d' "$output"
  assert_exit_code 0 "$?" "Node.js status JSON follows its schema"

  assert_contains "--docker-status" "$(bash "$SCRIPT" --help 2>&1)" "help documents Docker / OCI status"
  assert_contains "--docker-set-mirror" "$(bash "$SCRIPT" --help 2>&1)" "help documents safe Docker mirror configuration"
  code=0
  bash "$SCRIPT" --docker-status --docker-reset-mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "conflicting Docker actions are rejected"
  code=0
  bash "$SCRIPT" --docker-restore >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker restore requires an explicit snapshot path"
  code=0
  bash "$SCRIPT" --docker-test-mirror http://mirror.example/ >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker mirror probe rejects plain HTTP before network access"
  code=0
  bash "$SCRIPT" --docker-set-mirror https://mirror.example/ --apt-retries 5 >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker configuration rejects APT network options"
  code=0
  bash "$SCRIPT" --docker-status --node-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker and Node.js command modes cannot be combined"
  code=0
  bash "$SCRIPT" --docker-status --official-only >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker status rejects APT benchmark options"
  code=0
  bash "$SCRIPT" --docker-restart --dry-run >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker restart cannot be combined with dry-run"

  code=0
  bash "$SCRIPT" --python-client unknown --python-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown Python client is rejected"
  code=0
  bash "$SCRIPT" --python-scope invalid --python-status >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "unknown Python scope is rejected"
  code=0
  bash "$SCRIPT" --python-test-index http://pypi.org/simple/ >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "insecure HTTP Python index is rejected before network access"
  code=0
  bash "$SCRIPT" --python-status --doctor >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Python command cannot be combined with APT doctor"
  output="$(bash "$SCRIPT" --python-status --json 2>&1)"
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["schema_version"] == 1 and d["command"] == "python-status" and "environment_overrides" in d' "$output"
  assert_exit_code 0 "$?" "Python status JSON follows its schema"

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

  # shellcheck source=../src/linux-package-source-manager.sh
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
    printf '# Power APT Boost test fixture\nAcquire::Languages "none";\n# prior-apt-config\n' >"$APT_CONF_FILE"
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

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Architectures: amd64' "$APT_DEB822_FILE"
  sed -i '/^Components:/a Languages: none' "$APT_DEB822_FILE"
  printf '# Local comment that must survive a mirror switch\\n' >>"$APT_DEB822_FILE"
  local optional_status=0 optional_content
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || optional_status=$?
  assert_exit_code 0 "$optional_status" "managed Deb822 accepts safe optional fields"
  assert_file_contains "$APT_DEB822_FILE" 'Architectures: amd64' "managed Deb822 preserves Architectures"
  assert_file_contains "$APT_DEB822_FILE" 'Languages: none' "managed Deb822 preserves Languages"
  assert_file_contains "$APT_DEB822_FILE" '# Local comment that must survive a mirror switch' "managed Deb822 preserves user comments"
  assert_file_contains "$APT_DEB822_FILE" '# Mirror: https://new.example/ubuntu' "managed Deb822 updates its recorded mirror"
  assert_equal "1" "$(grep -c '^URIs: https://new.example/ubuntu
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

  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK=false
  dpkg() { printf 'arm64\n'; }
  export -f dpkg
  local ports_mode=1 ports_mirrors
  _uses_ports_archive && ports_mode=0
  assert_exit_code 0 "$ports_mode" "non-x86 architecture uses the Ubuntu ports archive"
  ports_mirrors="$(_get_mirrors)"
  assert_contains "https://ports.ubuntu.com/ubuntu-ports" "$ports_mirrors" "ports catalog is available for non-x86 architecture"
  unset -f dpkg

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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# write-rollback-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# Power APT Boost test fixture\n# current-network-will-be-restored\n' >"$APT_CONF_FILE"
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

test_terminal_menu_progress() {
  local menu_output value code
  local menu_log="${_TEST_ROOT}/menu-output.log"
  local progress_log="${_TEST_ROOT}/progress-output.log"

  menu_output=""
  _menu_choose "Menu test" "Choose one option" \
    "first" "First option" \
    "second" "Second option" \
    <<<"invalid
02" >"${_TEST_ROOT}/menu-choice.out" 2>"$menu_log" || true
  menu_output="$(cat "${_TEST_ROOT}/menu-choice.out")"
  assert_equal "second" "$menu_output" "terminal menu maps numeric input to the selected option"
  assert_file_contains "$menu_log" "1) First option" "terminal menu displays numbered options"
  assert_file_contains "$menu_log" "2) Second option" "terminal menu displays every numbered option"
  assert_file_contains "$menu_log" "Invalid selection" "terminal menu rejects non-numeric input"

  code=0
  _menu_choose "Menu test" "Choose one option" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits a menu without selecting an action"
  assert_file_contains "$menu_log" "0) Back" "submenu zero entry is labeled Back"

  code=0
  _menu_choose --zero-label "Exit" "Main menu test" "Choose an action" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits the main menu"
  assert_file_contains "$menu_log" "0) Exit" "main menu zero entry is labeled Exit"

  value="$(_menu_input "Input test" "Enter a value" "fallback" <<<"")"
  assert_equal "fallback" "$value" "terminal input accepts the displayed default"

  _menu_message "Completed" "The operation has finished." <<<"" 2>"$menu_log"
  assert_file_contains "$menu_log" "Press Enter to return to the menu" "completion messages wait for Enter"

  _print_task_progress "Mirror checks" 2 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "[2/3]" "task progress displays the completed and total counts"
  assert_file_contains "$progress_log" "ETA" "task progress displays an estimated remaining time"
  _print_task_progress "Mirror checks" 3 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "done" "task progress marks the final check as complete"
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

  cat >"${body}.static-main" <<'EOF'
Origin: Ubuntu
Label: Ubuntu
Suite: noble
Codename: noble
Date: Thu, 25 Apr 2024 15:10:33 UTC
EOF
  output="$(_validate_release_metadata "${body}.static-main" "noble" "noble")"
  assert_contains "valid|ok|static-suite-no-valid-until" "$output" "immutable Ubuntu base suite without Valid-Until remains valid after initial release"

  cat >"${body}.stale-dynamic" <<EOF
Origin: Ubuntu
Label: Ubuntu
Suite: noble-updates
Codename: noble
Date: $(date -u -d '9 days ago' -R)
EOF
  output="$(_validate_release_metadata "${body}.stale-dynamic" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|stale_release_metadata|stale" "$output" "dynamic Ubuntu updates suite without Valid-Until is still rejected when stale"

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
  local before after code progress_log
  local original_quiet="$QUIET" original_spinner="$NO_SPINNER" original_workers="$BENCH_WORKERS"
  progress_log="${_TEST_ROOT}/benchmark-progress.log"
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

  QUIET=false
  _select_mirror >/dev/null 2>"$progress_log"
  assert_file_contains "$progress_log" "[1/3] Mirror verification" "benchmark reports the first completed mirror"
  assert_file_contains "$progress_log" "[2/3] Mirror verification" "benchmark reports the second completed mirror"
  assert_file_contains "$progress_log" "[3/3] Mirror verification" "benchmark reports completion of every mirror"
  assert_file_contains "$progress_log" "ETA" "benchmark reports estimated remaining time while checks are pending"

  unset -f _load_mirror_catalog _get_mirrors _test_mirror
  QUIET="$original_quiet"
  NO_SPINNER="$original_spinner"
  BENCH_WORKERS="$original_workers"
}

test_python_manager_safety() {
  local valid output code path original_xdg xdg_was_set original_pip_index pip_index_was_set
  local original_pip_config pip_config_was_set snapshot before after
  original_xdg="${XDG_STATE_HOME-}"
  xdg_was_set="${XDG_STATE_HOME+x}"
  original_pip_index="${PIP_INDEX_URL-}"
  pip_index_was_set="${PIP_INDEX_URL+x}"
  original_pip_config="${PIP_CONFIG_FILE-}"
  pip_config_was_set="${PIP_CONFIG_FILE+x}"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  valid="$(_python_validate_index_url "https://pypi.org/simple")"
  assert_equal "https://pypi.org/simple/" "$valid" "Python index URL is normalized"
  code=0
  _python_validate_index_url "http://pypi.org/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects insecure HTTP"
  code=0
  _python_validate_index_url "https://user:secret@example.com/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects embedded credentials"
  code=0
  _python_validate_index_url "https://example.com/packages/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index requires a simple endpoint"
  code=0
  _python_validate_index_url "https://example.com/simple/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects query strings"
  output="$(_python_url_label "https://user:secret@example.com:8443/private/simple/")"
  assert_equal "https://example.com:8443/private/simple/" "$output" "Python index display masks credentials"
  POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED=true
  code=0
  _python_is_externally_managed || code=$?
  assert_exit_code 0 "$code" "PEP 668 guard recognizes externally-managed test marker"
  unset POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED

  _python_is_externally_managed() { return 0; }
  id() { printf '0'; }
  PYTHON_SCOPE=global
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "PEP 668 blocks global pip configuration"
  unset -f _python_is_externally_managed id
  PYTHON_SCOPE=auto

  export XDG_STATE_HOME="${_TEST_ROOT}/python-state"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  export PIP_INDEX_URL="https://user:secret@example.com/simple/"
  PYTHON_SCOPE=user
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "pip configuration refuses an environment index override"
  unset PIP_INDEX_URL
  PYTHON_SCOPE=auto

  FAKE_PIP_INDEX="https://new.example/simple/"
  _python_pip_get() { printf '%s' "$FAKE_PIP_INDEX"; }
  _python_pip_set() { FAKE_PIP_INDEX="$2"; }
  _python_pip_unset() { FAKE_PIP_INDEX=""; }

  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  FAKE_PIP_INDEX="https://manually-changed.example/simple/"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "pip snapshot refuses to overwrite a manually changed value"
  assert_equal "https://manually-changed.example/simple/" "$FAKE_PIP_INDEX" "pip conflict leaves the newer value untouched"

  FAKE_PIP_INDEX="https://new.example/simple/"
  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "pip snapshot restores a matching managed value"
  assert_equal "https://old.example/simple/" "$FAKE_PIP_INDEX" "pip snapshot restores the prior index"

  path="${_TEST_ROOT}/python-toml/pyproject.toml"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'TOML'
[project]
name = "fixture-project"

[[tool.uv.index]]
name = "private"
url = "https://private.example/simple/"
default = false

[tool.uv.sources]
private-package = { index = "private" }
TOML
  before="$(sha256sum "$path")"
  if python3 -c 'import tomllib' >/dev/null 2>&1 || python3 -c 'import tomli' >/dev/null 2>&1; then
    output="$(_python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv preview displays a managed source block"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv preview leaves the project file unchanged"

    _python_toml_edit write uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" "[[tool.uv.index]]" "uv project source is written to the correct TOML table"
    assert_file_contains "$path" 'name = "fixture-project"' "uv edit preserves unrelated project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "uv edit preserves an existing private index"
    assert_file_contains "$path" 'private-package = { index = "private" }' "uv edit preserves explicit project index pins"
    code=0
    _python_toml_edit write uv project "$path" "https://other.example/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "uv refuses a duplicate managed index/source name"

    before="$(sha256sum "$path")"
    output="$(_python_toml_edit remove-preview uv project "$path" "" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv reset preview identifies only the managed source"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv reset preview leaves the project file unchanged"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_snapshot_mark_after "$snapshot" uv "$path"
    printf '\n# external edit\n' >>"$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 8 "$code" "TOML snapshot refuses to overwrite a manually changed project file"
    assert_file_contains "$path" "# external edit" "TOML restore conflict leaves the manual edit intact"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    _python_snapshot_mark_after "$snapshot" uv "$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 0 "$code" "TOML snapshot restores a matching managed configuration"
    assert_file_contains "$path" "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "TOML snapshot restores the original managed source"

    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'name = "fixture-project"' "uv reset preserves unrelated TOML"
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "uv reset removes only the managed source block"

    path="${_TEST_ROOT}/python-toml/poetry/pyproject.toml"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<'TOML'
[tool.poetry]
name = "fixture-poetry"

[[tool.poetry.source]]
name = "private"
url = "https://private.example/simple/"
priority = "explicit"
TOML
    _python_toml_edit write poetry project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'priority = "supplemental"' "Poetry source uses the supplemental priority"
    assert_file_contains "$path" 'name = "fixture-poetry"' "Poetry edit preserves existing project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "Poetry edit preserves private source URLs"
    assert_file_contains "$path" 'priority = "explicit"' "Poetry edit preserves private source priority"
    _python_toml_edit remove poetry project "$path" "" "pab-test" supplemental >/dev/null
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "Poetry reset removes the app-managed source block"
  else
    code=0
    _python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "TOML editing fails closed when no parser is installed"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "unsupported TOML parser leaves the project file unchanged"
  fi

  if [[ "$pip_index_was_set" == x ]]; then export PIP_INDEX_URL="$original_pip_index"; else unset PIP_INDEX_URL; fi
  if [[ "$pip_config_was_set" == x ]]; then export PIP_CONFIG_FILE="$original_pip_config"; else unset PIP_CONFIG_FILE; fi
  if [[ "$xdg_was_set" == x ]]; then export XDG_STATE_HOME="$original_xdg"; else unset XDG_STATE_HOME; fi
  unset -f _python_pip_get _python_pip_set _python_pip_unset
}

_node_test_ini_set() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN { prefix=key "="; found=0 }
    index($0,prefix)==1 { if (!found) print prefix value; found=1; next }
    { print }
    END { if (!found) print prefix value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_classic_set() {
  local file="$1" value="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v value="$value" '
    BEGIN { found=0 }
    /^registry[[:space:]]+/ { if (!found) print "registry " value; found=1; next }
    { print }
    END { if (!found) print "registry " value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_yaml_set() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
key, value = sys.argv[2:]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
updated = []
found = False
for line in lines:
    if line.startswith(key + ":"):
        if not found:
            updated.append(f'{key}: "{value}"')
            found = True
    else:
        updated.append(line)
if not found:
    updated.append(f'{key}: "{value}"')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
}

test_node_manager_safety() {
  local original_home="$HOME" original_xdg_state="${XDG_STATE_HOME-}" original_xdg_config="${XDG_CONFIG_HOME-}"
  local home_set="${HOME+x}" xdg_state_set="${XDG_STATE_HOME+x}" xdg_config_set="${XDG_CONFIG_HOME+x}"
  local -a override_names=(npm_config_registry NPM_CONFIG_REGISTRY npm_config_userconfig NPM_CONFIG_USERCONFIG
    npm_config_globalconfig NPM_CONFIG_GLOBALCONFIG pnpm_config_registry PNPM_CONFIG_REGISTRY
    YARN_NPM_REGISTRY_SERVER YARN_RC_FILENAME YARN_IGNORE_PATH)
  local -a override_values=()
  local name output code url snapshot before after path
  for name in "${override_names[@]}"; do
    override_values+=("${!name-}")
    unset "$name"
  done

  HOME="${_TEST_ROOT}/node-home"
  XDG_CONFIG_HOME="$HOME/.config"
  XDG_STATE_HOME="${_TEST_ROOT}/node-state"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME
  DRY_RUN=false
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/pnpm" "${_TEST_ROOT}/node-project"
  printf '%s\n' '{"name":"node-fixture","publishConfig":{"registry":"https://publish.example/"}}' >"${_TEST_ROOT}/node-project/package.json"

  output="$(_node_validate_registry_url "https://registry.npmjs.org")"
  assert_equal "https://registry.npmjs.org/" "$output" "Node.js registry URL is normalized"
  code=0
  _node_validate_registry_url "http://registry.npmjs.org/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects plain HTTP"
  code=0
  _node_validate_registry_url "https://user:secret@registry.example/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects embedded credentials"
  code=0
  _node_validate_registry_url "https://registry.example/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects query strings"
  code=0
  _node_validate_registry_url "https://registry.example/#fragment" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects fragments"
  output="$(_node_url_label "https://user:secret@registry.example:8443/path/?token=hidden#fragment")"
  assert_equal "https://registry.example:8443" "$output" "Node.js registry display exposes only the origin"
  output="$(_node_url_label "https://registry.example/tenant-secret/path/")"
  assert_equal "https://registry.example" "$output" "Node.js registry display never exposes path credentials"
  output="$(_node_url_label "undefined")"
  assert_equal "not configured" "$output" "Node.js registry display handles unset values"
  output="$(_node_validate_package_name "@acme/valid-package")"
  assert_equal "@acme/valid-package" "$output" "Node.js package validator accepts scoped package names"
  code=0
  _node_validate_package_name "../escape" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js package validator rejects traversal names"

  npm() {
    if [[ "$1 $2 $3" == "config get userconfig" ]]; then
      printf '%s/.npmrc\n' "$HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  pnpm() {
    if [[ "$1 $2 $3" == "config get globalconfig" ]]; then
      printf '%s/pnpm/rc\n' "$XDG_CONFIG_HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  NODE_TEST_YARN_VERSION="1.22.22"
  yarn() {
    if [[ "$1" == "--version" ]]; then
      printf '%s\n' "$NODE_TEST_YARN_VERSION"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$PWD/.yarnrc"
      sed -n 's/^registry[[:space:]][[:space:]]*//p' "$file" 2>/dev/null | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config get npmRegistryServer" ]]; then
      local file="$PWD/.yarnrc.yml"
      sed -n 's/^npmRegistryServer:[[:space:]]*//p' "$file" 2>/dev/null | tr -d '"' | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.yarnrc"
      [[ "$PWD" == "$HOME" || "$*" == *"--global"* ]] || file="$PWD/.yarnrc"
      _node_test_yarn_classic_set "$file" "$4"
      return $?
    fi
    if [[ "$1 $2 $3" == "config set npmRegistryServer" ]]; then
      local file="$HOME/.yarnrc.yml"
      [[ "$PWD" == "$HOME" || "$*" == *"--home"* ]] || file="$PWD/.yarnrc.yml"
      _node_test_yarn_yaml_set "$file" npmRegistryServer "$4"
      return $?
    fi
    return 2
  }

  _node_probe_registry() { return 0; }
  _confirm_action() { return 0; }

  path="$HOME/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://registry.before.example/
@internal:registry=https://packages.internal.example/
//registry.before.example/:_authToken=NODE_SECRET_SENTINEL
NPMRC
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  NODE_CLIENT=npm NODE_SCOPE=user NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_YARN_FLAVOR=""
  _node_apply_registry set "https://registry.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://registry.after.example/" "npm user registry changes the default registry"
  assert_file_contains "$path" "@internal:registry=https://packages.internal.example/" "npm preserves scoped registry entries"
  assert_file_contains "$path" "NODE_SECRET_SENTINEL" "npm preserves auth token values"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "npm preserves config file permissions"
  snapshot="$(cat "$(_node_state_path npm user "$path")")"
  cp "$path" "$_TEST_ROOT/npm-after.npmrc"
  printf '%s\n' '# external change' >>"$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "npm restore refuses an externally modified file"
  assert_file_contains "$path" "# external change" "npm restore conflict preserves the external edit"
  cp "$_TEST_ROOT/npm-after.npmrc" "$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "npm reset restores its prior config"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "npm restore reproduces the original file bytes"

  path="${_TEST_ROOT}/node-project/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://project.before.example/
@private:registry=https://private.project.example/
//private.project.example/:_authToken=PROJECT_SECRET_SENTINEL
NPMRC
  NODE_CLIENT=pnpm NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://project.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://project.after.example/" "pnpm project scope changes the default registry"
  assert_file_contains "$path" "@private:registry=https://private.project.example/" "pnpm preserves scoped registries"
  assert_file_contains "$path" "PROJECT_SECRET_SENTINEL" "pnpm preserves project auth tokens"
  assert_file_contains "${_TEST_ROOT}/node-project/package.json" '"registry":"https://publish.example/"' "pnpm leaves package publishConfig untouched"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm project rollback restores the original .npmrc"

  XDG_CONFIG_HOME="${_TEST_ROOT}/external-xdg-config"
  export XDG_CONFIG_HOME
  mkdir -p "$XDG_CONFIG_HOME/pnpm"
  path="$XDG_CONFIG_HOME/pnpm/rc"
  printf '%s\n' "registry=https://pnpm.before.example/" >"$path"
  NODE_CLIENT=pnpm NODE_SCOPE=user NODE_PROJECT_DIR=""
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://pnpm.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://pnpm.after.example/" "pnpm user scope honors an external XDG_CONFIG_HOME"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm external XDG config is restored exactly"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME
  path="$HOME/.yarnrc"
  cat >"$path" <<'YARNRC'
registry https://classic.before.example
unsafeHttpWhitelist
  - internal.example
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=user NODE_PROJECT_DIR=""
  NODE_TEST_YARN_VERSION="1.22.22"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal classic "$NODE_YARN_FLAVOR" "Yarn 1 is identified as Classic"
  _node_apply_registry set "https://classic.after.example/" >/dev/null
  assert_file_contains "$path" "registry https://classic.after.example/" "Yarn Classic user registry changes"
  assert_file_contains "$path" "unsafeHttpWhitelist" "Yarn Classic preserves unrelated configuration"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Classic rollback restores the original file"

  path="${_TEST_ROOT}/node-project/.yarnrc.yml"
  cat >"$path" <<'YARNRC'
npmRegistryServer: "https://berry.before.example"
npmPublishRegistry: "https://publish.berry.example"
npmScopes:
  internal:
    npmRegistryServer: "https://scoped.berry.example"
    npmAuthToken: "BERRY_SECRET_SENTINEL"
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  NODE_TEST_YARN_VERSION="4.5.0"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal berry "$NODE_YARN_FLAVOR" "Yarn 2+ is identified as Berry"
  _node_apply_registry set "https://berry.after.example/" >/dev/null
  assert_file_contains "$path" 'npmRegistryServer: "https://berry.after.example/"' "Yarn Berry project registry changes"
  assert_file_contains "$path" 'npmPublishRegistry: "https://publish.berry.example"' "Yarn Berry preserves publish registry"
  assert_file_contains "$path" "https://scoped.berry.example" "Yarn Berry preserves scoped registry"
  assert_file_contains "$path" "BERRY_SECRET_SENTINEL" "Yarn Berry preserves scoped auth tokens"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Berry rollback restores the original file"

  NODE_REQUESTED=false NODE_ACTION="" NODE_CLIENT=npm NODE_SCOPE=user NODE_REGISTRY_URL=""
  NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_RESTORE_PATH="" NODE_TARGET_FILE="" NODE_YARN_FLAVOR=""
  DRY_RUN=true
  unset -f npm pnpm yarn _node_probe_registry _confirm_action
  unset -f _node_test_ini_set _node_test_yarn_classic_set _node_test_yarn_yaml_set
  if [[ "$home_set" == x ]]; then export HOME="$original_home"; else unset HOME; fi
  if [[ "$xdg_state_set" == x ]]; then export XDG_STATE_HOME="$original_xdg_state"; else unset XDG_STATE_HOME; fi
  if [[ "$xdg_config_set" == x ]]; then export XDG_CONFIG_HOME="$original_xdg_config"; else unset XDG_CONFIG_HOME; fi
  for ((code = 0; code < ${#override_names[@]}; code++)); do
    name="${override_names[$code]}"
    if [[ -n "${override_values[$code]}" ]]; then export "$name=${override_values[$code]}"; else unset "$name"; fi
  done
}

test_docker_manager_safety() {
  local path="$DOCKER_DAEMON_CONFIG" before after code output restart_log backup_mode
  mkdir -p "$DOCKER_CONFIG_DIR" "$APT_SOURCES_DIR"
  chmod 0750 "$BACKUP_BASE"
  _docker_require_backup_base
  backup_mode="$(stat -c '%a' "$BACKUP_BASE")"
  assert_equal "750" "$backup_mode" "Docker backup setup preserves the shared APT backup parent permissions"
  cat >"${APT_SOURCES_DIR}/docker.sources" <<'DOCKERSOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKERSOURCES

  _docker_scan_apt_sources
  assert_equal "1" "$DOCKER_APT_SOURCE_COUNT" "Docker Engine APT source is detected separately"
  assert_contains "noble" "${DOCKER_APT_SOURCE_SUITES[*]}" "Docker APT suite is reported"
  output="$(_docker_validate_mirror_url "https://mirror.gcr.io/")"
  assert_equal "https://mirror.gcr.io" "$output" "Docker mirror origin is normalized"
  code=0
  _docker_validate_mirror_url "http://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects plain HTTP"
  code=0
  _docker_validate_mirror_url "https://user:secret@mirror.example" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects embedded credentials"
  code=0
  _docker_validate_mirror_url "https://mirror.example/tenant" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects URL paths"
  code=0
  _docker_validate_mirror_url "https://mirror.example/?token=hidden" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects query strings"
  output="$(_docker_url_origin_label "https://user:secret@mirror.example:8443/private/path?token=hidden")"
  assert_equal "https://mirror.example:8443" "$output" "Docker mirror labels hide paths and credentials"

  _docker_probe_mirror() {
    DOCKER_PROBE_STATUS=401
    DOCKER_PROBE_HOST="$(_docker_url_origin_label "$1")"
    return 0
  }
  _confirm_action() { return 0; }
  dockerd() {
    [[ "${DOCKER_TEST_DOCKERD_FAIL:-false}" != true ]] || return 1
    return 0
  }

  cat >"$path" <<'DAEMONJSON'
{
  "debug": true,
  "log-driver": "json-file",
  "registry-mirrors": ["https://existing.example"]
}
DAEMONJSON
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  _docker_read_config
  assert_equal "valid" "$DOCKER_CONFIG_STATUS" "Docker daemon JSON object is recognized"
  assert_equal "1" "${#DOCKER_CONFIG_MIRROR_ORIGINS[@]}" "Existing registry mirror list is read"
  assert_equal "https://existing.example" "${DOCKER_CONFIG_MIRROR_ORIGINS[0]}" "Existing mirror output is origin-only"
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=false
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  assert_file_contains "$path" '"debug": true' "Docker merge preserves unrelated boolean settings"
  assert_file_contains "$path" '"log-driver": "json-file"' "Docker merge preserves unrelated daemon settings"
  assert_file_contains "$path" '"https://existing.example"' "Docker merge preserves existing registry mirrors"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker merge adds the selected mirror"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker daemon config permissions are preserved"
  python3 - "$path" <<'PY' || code=$?
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["debug"] is True
assert data["log-driver"] == "json-file"
assert data["registry-mirrors"] == [
    "https://existing.example",
    "https://mirror.gcr.io",
]
PY
  assert_exit_code 0 "${code:-0}" "Docker daemon JSON remains valid and preserves the full mirror array"
  [[ -f "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker configuration saves a rollback state pointer"
  restart_log="${_TEST_ROOT}/docker-systemctl.log"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Saving daemon.json never restarts Docker"

  cp "$path" "${_TEST_ROOT}/docker-after.json"
  printf '%s\n' " " >>"$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "Docker rollback refuses an externally modified daemon.json"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker rollback conflict preserves external edits"
  cp "${_TEST_ROOT}/docker-after.json" "$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Docker rollback succeeds when the after-hash still matches"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Docker rollback restores daemon.json byte-for-byte"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker reset clears the app-managed state pointer"

  rm -f -- "$path"
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  [[ -f "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker can create daemon.json when the Docker config directory exists"
  _docker_reset_mirror >/dev/null
  [[ ! -e "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker rollback removes a config file that did not exist before"

  printf '%s\n' '{invalid-json' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses malformed daemon.json"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Malformed daemon.json remains untouched"

  printf '%s\n' '{"registry-mirrors":"not-an-array"}' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a non-array registry-mirrors value"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Invalid registry-mirrors type remains untouched"

  printf '%s\n' '{"debug":true}' >"$path"
  before="$(sha256sum "$path")"
  DOCKER_TEST_DOCKERD_FAIL=true
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker manager refuses config rejected by dockerd --validate"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Failed dockerd validation leaves daemon.json unchanged"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Failed pre-write validation does not save active state"
  DOCKER_TEST_DOCKERD_FAIL=false

  rm -f -- "$path"
  ln -s "${_TEST_ROOT}/docker-symlink-target.json" "$path"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a symlinked daemon.json target"
  [[ -L "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Rejected Docker symlink is left untouched"
  rm -f -- "$path"
  printf '%s\n' '{"debug":true}' >"$path"

  JSON_OUTPUT=true
  output="$(_docker_status_report)"
  python3 - "$output" <<'PY' || code=$?
import json
import sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
assert data["command"] == "docker-status"
assert data["docker_engine_apt"]["source_records"] == 1
assert data["daemon"]["config_status"] == "valid"
assert isinstance(data["daemon"]["registry_mirrors"], list)
PY
  assert_exit_code 0 "${code:-0}" "Docker status JSON follows schema version 1"
  JSON_OUTPUT=false

  systemctl() {
    case "$1" in
    is-active) return 0 ;;
    restart) printf '%s\n' "restart docker" >>"$restart_log" ;;
    *) return 1 ;;
    esac
  }
  _confirm_action() {
    local answer=""
    if [[ "$YES" == true ]]; then
      return 0
    fi
    if ! _is_interactive; then
      return "$EXIT_USAGE"
    fi
    IFS= read -r answer || answer=""
    case "${answer,,}" in
    y | yes) return 0 ;;
    *) return "$EXIT_CANCELLED" ;;
    esac
  }
  YES=false
  _is_interactive() { return 1; }
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Non-interactive Docker restart requires explicit --yes"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Unapproved Docker restart never calls systemctl restart"
  _is_interactive() { return 0; }
  code=0
  printf 'n\n' | _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 10 "$code" "Interactive Docker restart can be declined"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Declined Docker restart never calls systemctl restart"
  YES=true
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Explicitly approved Docker restart is executed"
  assert_file_contains "$restart_log" "restart docker" "Docker restart uses the docker service unit"

  unset -f systemctl _docker_probe_mirror dockerd
  unset -f _confirm_action
  DOCKER_REQUESTED=false DOCKER_ACTION="" DOCKER_MIRROR_URL="" DOCKER_RESTORE_PATH=""
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=true
  YES=false
  JSON_OUTPUT=false
}

_run_test_group() {
  local current="$1" total="$2" label="$3" test_function="$4"
  local started="$SECONDS" elapsed eta=0
  printf '\n[%d/%d] Running %s...\n' "$current" "$total" "$label"
  "$test_function"
  elapsed=$((SECONDS - started))
  if ((current < total)); then
    eta=$(((elapsed * (total - current) + current - 1) / current))
    printf '[%d/%d] Completed %s in %ds | estimated remaining ~%ds\n' \
      "$current" "$total" "$label" "$elapsed" "$eta"
  else
    printf '[%d/%d] Completed %s in %ds | all test groups finished\n' \
      "$current" "$total" "$label" "$elapsed"
  fi
}

main() {
  printf '\nLinux Package Source Manager — Offline Test Suite\n'
  printf '%s\n' '===================================='
  _run_test_group 1 9 "CLI validation" test_cli
  _run_test_group 2 9 "Filesystem and configuration safety" test_filesystem_operations
  _run_test_group 3 9 "Terminal menu and task progress" test_terminal_menu_progress
  _run_test_group 4 9 "Probe parsing and mirror list criteria" test_probe_parser_and_list_criteria
  _run_test_group 5 9 "Catalog and Release metadata" test_catalog_and_release_metadata
  _run_test_group 6 9 "Mirror benchmark and read-only safety" test_benchmark_selection_and_read_only_safety
  _run_test_group 7 9 "Python package source manager" test_python_manager_safety
  _run_test_group 8 9 "Node.js registry manager" test_node_manager_safety
  _run_test_group 9 9 "Docker / OCI manager" test_docker_manager_safety
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"
 "$APT_DEB822_FILE")" "managed Deb822 updates both archive URI fields"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Trusted: yes' "$APT_DEB822_FILE"
  local trusted_before trusted_after trusted_status=0
  trusted_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || trusted_status=$?
  trusted_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$trusted_status" "managed Deb822 rejects signature-bypass fields"
  assert_equal "$trusted_before" "$trusted_after" "rejected signature-bypass field leaves source file unchanged"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Allow-Insecure: yes' "$APT_DEB822_FILE"
  local insecure_before insecure_after insecure_status=0
  insecure_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || insecure_status=$?
  insecure_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$insecure_status" "managed Deb822 rejects Allow-Insecure"
  assert_equal "$insecure_before" "$insecure_after" "Allow-Insecure rejection preserves source file"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Check-Valid-Until: no' "$APT_DEB822_FILE"
  local freshness_before freshness_after freshness_status=0
  freshness_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || freshness_status=$?
  freshness_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$freshness_status" "managed Deb822 rejects disabled Release freshness checks"
  assert_equal "$freshness_before" "$freshness_after" "freshness-check rejection preserves source file"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a X-Local-Option: keep' "$APT_DEB822_FILE"
  local unknown_before unknown_after unknown_status=0
  unknown_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || unknown_status=$?
  unknown_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$unknown_status" "managed Deb822 rejects unsupported fields"
  assert_equal "$unknown_before" "$unknown_after" "unsupported field rejection preserves source file"

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

  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK=false
  dpkg() { printf 'arm64\n'; }
  export -f dpkg
  local ports_mode=1 ports_mirrors
  _uses_ports_archive && ports_mode=0
  assert_exit_code 0 "$ports_mode" "non-x86 architecture uses the Ubuntu ports archive"
  ports_mirrors="$(_get_mirrors)"
  assert_contains "https://ports.ubuntu.com/ubuntu-ports" "$ports_mirrors" "ports catalog is available for non-x86 architecture"
  unset -f dpkg

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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# write-rollback-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# Power APT Boost test fixture\n# current-network-will-be-restored\n' >"$APT_CONF_FILE"
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

test_terminal_menu_progress() {
  local menu_output value code
  local menu_log="${_TEST_ROOT}/menu-output.log"
  local progress_log="${_TEST_ROOT}/progress-output.log"

  menu_output=""
  _menu_choose "Menu test" "Choose one option" \
    "first" "First option" \
    "second" "Second option" \
    <<<"invalid
02" >"${_TEST_ROOT}/menu-choice.out" 2>"$menu_log" || true
  menu_output="$(cat "${_TEST_ROOT}/menu-choice.out")"
  assert_equal "second" "$menu_output" "terminal menu maps numeric input to the selected option"
  assert_file_contains "$menu_log" "1) First option" "terminal menu displays numbered options"
  assert_file_contains "$menu_log" "2) Second option" "terminal menu displays every numbered option"
  assert_file_contains "$menu_log" "Invalid selection" "terminal menu rejects non-numeric input"

  code=0
  _menu_choose "Menu test" "Choose one option" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits a menu without selecting an action"
  assert_file_contains "$menu_log" "0) Back" "submenu zero entry is labeled Back"

  code=0
  _menu_choose --zero-label "Exit" "Main menu test" "Choose an action" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits the main menu"
  assert_file_contains "$menu_log" "0) Exit" "main menu zero entry is labeled Exit"

  value="$(_menu_input "Input test" "Enter a value" "fallback" <<<"")"
  assert_equal "fallback" "$value" "terminal input accepts the displayed default"

  _menu_message "Completed" "The operation has finished." <<<"" 2>"$menu_log"
  assert_file_contains "$menu_log" "Press Enter to return to the menu" "completion messages wait for Enter"

  _print_task_progress "Mirror checks" 2 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "[2/3]" "task progress displays the completed and total counts"
  assert_file_contains "$progress_log" "ETA" "task progress displays an estimated remaining time"
  _print_task_progress "Mirror checks" 3 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "done" "task progress marks the final check as complete"
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

  cat >"${body}.static-main" <<'EOF'
Origin: Ubuntu
Label: Ubuntu
Suite: noble
Codename: noble
Date: Thu, 25 Apr 2024 15:10:33 UTC
EOF
  output="$(_validate_release_metadata "${body}.static-main" "noble" "noble")"
  assert_contains "valid|ok|static-suite-no-valid-until" "$output" "immutable Ubuntu base suite without Valid-Until remains valid after initial release"

  cat >"${body}.stale-dynamic" <<EOF
Origin: Ubuntu
Label: Ubuntu
Suite: noble-updates
Codename: noble
Date: $(date -u -d '9 days ago' -R)
EOF
  output="$(_validate_release_metadata "${body}.stale-dynamic" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|stale_release_metadata|stale" "$output" "dynamic Ubuntu updates suite without Valid-Until is still rejected when stale"

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
  local before after code progress_log
  local original_quiet="$QUIET" original_spinner="$NO_SPINNER" original_workers="$BENCH_WORKERS"
  progress_log="${_TEST_ROOT}/benchmark-progress.log"
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

  QUIET=false
  _select_mirror >/dev/null 2>"$progress_log"
  assert_file_contains "$progress_log" "[1/3] Mirror verification" "benchmark reports the first completed mirror"
  assert_file_contains "$progress_log" "[2/3] Mirror verification" "benchmark reports the second completed mirror"
  assert_file_contains "$progress_log" "[3/3] Mirror verification" "benchmark reports completion of every mirror"
  assert_file_contains "$progress_log" "ETA" "benchmark reports estimated remaining time while checks are pending"

  unset -f _load_mirror_catalog _get_mirrors _test_mirror
  QUIET="$original_quiet"
  NO_SPINNER="$original_spinner"
  BENCH_WORKERS="$original_workers"
}

test_python_manager_safety() {
  local valid output code path original_xdg xdg_was_set original_pip_index pip_index_was_set
  local original_pip_config pip_config_was_set snapshot before after
  original_xdg="${XDG_STATE_HOME-}"
  xdg_was_set="${XDG_STATE_HOME+x}"
  original_pip_index="${PIP_INDEX_URL-}"
  pip_index_was_set="${PIP_INDEX_URL+x}"
  original_pip_config="${PIP_CONFIG_FILE-}"
  pip_config_was_set="${PIP_CONFIG_FILE+x}"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  valid="$(_python_validate_index_url "https://pypi.org/simple")"
  assert_equal "https://pypi.org/simple/" "$valid" "Python index URL is normalized"
  code=0
  _python_validate_index_url "http://pypi.org/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects insecure HTTP"
  code=0
  _python_validate_index_url "https://user:secret@example.com/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects embedded credentials"
  code=0
  _python_validate_index_url "https://example.com/packages/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index requires a simple endpoint"
  code=0
  _python_validate_index_url "https://example.com/simple/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects query strings"
  output="$(_python_url_label "https://user:secret@example.com:8443/private/simple/")"
  assert_equal "https://example.com:8443/private/simple/" "$output" "Python index display masks credentials"
  POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED=true
  code=0
  _python_is_externally_managed || code=$?
  assert_exit_code 0 "$code" "PEP 668 guard recognizes externally-managed test marker"
  unset POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED

  _python_is_externally_managed() { return 0; }
  id() { printf '0'; }
  PYTHON_SCOPE=global
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "PEP 668 blocks global pip configuration"
  unset -f _python_is_externally_managed id
  PYTHON_SCOPE=auto

  export XDG_STATE_HOME="${_TEST_ROOT}/python-state"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  export PIP_INDEX_URL="https://user:secret@example.com/simple/"
  PYTHON_SCOPE=user
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "pip configuration refuses an environment index override"
  unset PIP_INDEX_URL
  PYTHON_SCOPE=auto

  FAKE_PIP_INDEX="https://new.example/simple/"
  _python_pip_get() { printf '%s' "$FAKE_PIP_INDEX"; }
  _python_pip_set() { FAKE_PIP_INDEX="$2"; }
  _python_pip_unset() { FAKE_PIP_INDEX=""; }

  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  FAKE_PIP_INDEX="https://manually-changed.example/simple/"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "pip snapshot refuses to overwrite a manually changed value"
  assert_equal "https://manually-changed.example/simple/" "$FAKE_PIP_INDEX" "pip conflict leaves the newer value untouched"

  FAKE_PIP_INDEX="https://new.example/simple/"
  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "pip snapshot restores a matching managed value"
  assert_equal "https://old.example/simple/" "$FAKE_PIP_INDEX" "pip snapshot restores the prior index"

  path="${_TEST_ROOT}/python-toml/pyproject.toml"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'TOML'
[project]
name = "fixture-project"

[[tool.uv.index]]
name = "private"
url = "https://private.example/simple/"
default = false

[tool.uv.sources]
private-package = { index = "private" }
TOML
  before="$(sha256sum "$path")"
  if python3 -c 'import tomllib' >/dev/null 2>&1 || python3 -c 'import tomli' >/dev/null 2>&1; then
    output="$(_python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv preview displays a managed source block"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv preview leaves the project file unchanged"

    _python_toml_edit write uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" "[[tool.uv.index]]" "uv project source is written to the correct TOML table"
    assert_file_contains "$path" 'name = "fixture-project"' "uv edit preserves unrelated project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "uv edit preserves an existing private index"
    assert_file_contains "$path" 'private-package = { index = "private" }' "uv edit preserves explicit project index pins"
    code=0
    _python_toml_edit write uv project "$path" "https://other.example/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "uv refuses a duplicate managed index/source name"

    before="$(sha256sum "$path")"
    output="$(_python_toml_edit remove-preview uv project "$path" "" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv reset preview identifies only the managed source"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv reset preview leaves the project file unchanged"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_snapshot_mark_after "$snapshot" uv "$path"
    printf '\n# external edit\n' >>"$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 8 "$code" "TOML snapshot refuses to overwrite a manually changed project file"
    assert_file_contains "$path" "# external edit" "TOML restore conflict leaves the manual edit intact"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    _python_snapshot_mark_after "$snapshot" uv "$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 0 "$code" "TOML snapshot restores a matching managed configuration"
    assert_file_contains "$path" "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "TOML snapshot restores the original managed source"

    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'name = "fixture-project"' "uv reset preserves unrelated TOML"
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "uv reset removes only the managed source block"

    path="${_TEST_ROOT}/python-toml/poetry/pyproject.toml"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<'TOML'
[tool.poetry]
name = "fixture-poetry"

[[tool.poetry.source]]
name = "private"
url = "https://private.example/simple/"
priority = "explicit"
TOML
    _python_toml_edit write poetry project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'priority = "supplemental"' "Poetry source uses the supplemental priority"
    assert_file_contains "$path" 'name = "fixture-poetry"' "Poetry edit preserves existing project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "Poetry edit preserves private source URLs"
    assert_file_contains "$path" 'priority = "explicit"' "Poetry edit preserves private source priority"
    _python_toml_edit remove poetry project "$path" "" "pab-test" supplemental >/dev/null
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "Poetry reset removes the app-managed source block"
  else
    code=0
    _python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "TOML editing fails closed when no parser is installed"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "unsupported TOML parser leaves the project file unchanged"
  fi

  if [[ "$pip_index_was_set" == x ]]; then export PIP_INDEX_URL="$original_pip_index"; else unset PIP_INDEX_URL; fi
  if [[ "$pip_config_was_set" == x ]]; then export PIP_CONFIG_FILE="$original_pip_config"; else unset PIP_CONFIG_FILE; fi
  if [[ "$xdg_was_set" == x ]]; then export XDG_STATE_HOME="$original_xdg"; else unset XDG_STATE_HOME; fi
  unset -f _python_pip_get _python_pip_set _python_pip_unset
}

_node_test_ini_set() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN { prefix=key "="; found=0 }
    index($0,prefix)==1 { if (!found) print prefix value; found=1; next }
    { print }
    END { if (!found) print prefix value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_classic_set() {
  local file="$1" value="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v value="$value" '
    BEGIN { found=0 }
    /^registry[[:space:]]+/ { if (!found) print "registry " value; found=1; next }
    { print }
    END { if (!found) print "registry " value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_yaml_set() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
key, value = sys.argv[2:]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
updated = []
found = False
for line in lines:
    if line.startswith(key + ":"):
        if not found:
            updated.append(f'{key}: "{value}"')
            found = True
    else:
        updated.append(line)
if not found:
    updated.append(f'{key}: "{value}"')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
}

test_node_manager_safety() {
  local original_home="$HOME" original_xdg_state="${XDG_STATE_HOME-}" original_xdg_config="${XDG_CONFIG_HOME-}"
  local home_set="${HOME+x}" xdg_state_set="${XDG_STATE_HOME+x}" xdg_config_set="${XDG_CONFIG_HOME+x}"
  local -a override_names=(npm_config_registry NPM_CONFIG_REGISTRY npm_config_userconfig NPM_CONFIG_USERCONFIG
    npm_config_globalconfig NPM_CONFIG_GLOBALCONFIG pnpm_config_registry PNPM_CONFIG_REGISTRY
    YARN_NPM_REGISTRY_SERVER YARN_RC_FILENAME YARN_IGNORE_PATH)
  local -a override_values=()
  local name output code url snapshot before after path
  for name in "${override_names[@]}"; do
    override_values+=("${!name-}")
    unset "$name"
  done

  HOME="${_TEST_ROOT}/node-home"
  XDG_CONFIG_HOME="$HOME/.config"
  XDG_STATE_HOME="${_TEST_ROOT}/node-state"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME
  DRY_RUN=false
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/pnpm" "${_TEST_ROOT}/node-project"
  printf '%s\n' '{"name":"node-fixture","publishConfig":{"registry":"https://publish.example/"}}' >"${_TEST_ROOT}/node-project/package.json"

  output="$(_node_validate_registry_url "https://registry.npmjs.org")"
  assert_equal "https://registry.npmjs.org/" "$output" "Node.js registry URL is normalized"
  code=0
  _node_validate_registry_url "http://registry.npmjs.org/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects plain HTTP"
  code=0
  _node_validate_registry_url "https://user:secret@registry.example/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects embedded credentials"
  code=0
  _node_validate_registry_url "https://registry.example/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects query strings"
  code=0
  _node_validate_registry_url "https://registry.example/#fragment" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects fragments"
  output="$(_node_url_label "https://user:secret@registry.example:8443/path/?token=hidden#fragment")"
  assert_equal "https://registry.example:8443" "$output" "Node.js registry display exposes only the origin"
  output="$(_node_url_label "https://registry.example/tenant-secret/path/")"
  assert_equal "https://registry.example" "$output" "Node.js registry display never exposes path credentials"
  output="$(_node_url_label "undefined")"
  assert_equal "not configured" "$output" "Node.js registry display handles unset values"
  output="$(_node_validate_package_name "@acme/valid-package")"
  assert_equal "@acme/valid-package" "$output" "Node.js package validator accepts scoped package names"
  code=0
  _node_validate_package_name "../escape" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js package validator rejects traversal names"

  npm() {
    if [[ "$1 $2 $3" == "config get userconfig" ]]; then
      printf '%s/.npmrc\n' "$HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  pnpm() {
    if [[ "$1 $2 $3" == "config get globalconfig" ]]; then
      printf '%s/pnpm/rc\n' "$XDG_CONFIG_HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  NODE_TEST_YARN_VERSION="1.22.22"
  yarn() {
    if [[ "$1" == "--version" ]]; then
      printf '%s\n' "$NODE_TEST_YARN_VERSION"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$PWD/.yarnrc"
      sed -n 's/^registry[[:space:]][[:space:]]*//p' "$file" 2>/dev/null | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config get npmRegistryServer" ]]; then
      local file="$PWD/.yarnrc.yml"
      sed -n 's/^npmRegistryServer:[[:space:]]*//p' "$file" 2>/dev/null | tr -d '"' | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.yarnrc"
      [[ "$PWD" == "$HOME" || "$*" == *"--global"* ]] || file="$PWD/.yarnrc"
      _node_test_yarn_classic_set "$file" "$4"
      return $?
    fi
    if [[ "$1 $2 $3" == "config set npmRegistryServer" ]]; then
      local file="$HOME/.yarnrc.yml"
      [[ "$PWD" == "$HOME" || "$*" == *"--home"* ]] || file="$PWD/.yarnrc.yml"
      _node_test_yarn_yaml_set "$file" npmRegistryServer "$4"
      return $?
    fi
    return 2
  }

  _node_probe_registry() { return 0; }
  _confirm_action() { return 0; }

  path="$HOME/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://registry.before.example/
@internal:registry=https://packages.internal.example/
//registry.before.example/:_authToken=NODE_SECRET_SENTINEL
NPMRC
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  NODE_CLIENT=npm NODE_SCOPE=user NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_YARN_FLAVOR=""
  _node_apply_registry set "https://registry.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://registry.after.example/" "npm user registry changes the default registry"
  assert_file_contains "$path" "@internal:registry=https://packages.internal.example/" "npm preserves scoped registry entries"
  assert_file_contains "$path" "NODE_SECRET_SENTINEL" "npm preserves auth token values"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "npm preserves config file permissions"
  snapshot="$(cat "$(_node_state_path npm user "$path")")"
  cp "$path" "$_TEST_ROOT/npm-after.npmrc"
  printf '%s\n' '# external change' >>"$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "npm restore refuses an externally modified file"
  assert_file_contains "$path" "# external change" "npm restore conflict preserves the external edit"
  cp "$_TEST_ROOT/npm-after.npmrc" "$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "npm reset restores its prior config"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "npm restore reproduces the original file bytes"

  path="${_TEST_ROOT}/node-project/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://project.before.example/
@private:registry=https://private.project.example/
//private.project.example/:_authToken=PROJECT_SECRET_SENTINEL
NPMRC
  NODE_CLIENT=pnpm NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://project.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://project.after.example/" "pnpm project scope changes the default registry"
  assert_file_contains "$path" "@private:registry=https://private.project.example/" "pnpm preserves scoped registries"
  assert_file_contains "$path" "PROJECT_SECRET_SENTINEL" "pnpm preserves project auth tokens"
  assert_file_contains "${_TEST_ROOT}/node-project/package.json" '"registry":"https://publish.example/"' "pnpm leaves package publishConfig untouched"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm project rollback restores the original .npmrc"

  XDG_CONFIG_HOME="${_TEST_ROOT}/external-xdg-config"
  export XDG_CONFIG_HOME
  mkdir -p "$XDG_CONFIG_HOME/pnpm"
  path="$XDG_CONFIG_HOME/pnpm/rc"
  printf '%s\n' "registry=https://pnpm.before.example/" >"$path"
  NODE_CLIENT=pnpm NODE_SCOPE=user NODE_PROJECT_DIR=""
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://pnpm.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://pnpm.after.example/" "pnpm user scope honors an external XDG_CONFIG_HOME"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm external XDG config is restored exactly"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME
  path="$HOME/.yarnrc"
  cat >"$path" <<'YARNRC'
registry https://classic.before.example
unsafeHttpWhitelist
  - internal.example
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=user NODE_PROJECT_DIR=""
  NODE_TEST_YARN_VERSION="1.22.22"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal classic "$NODE_YARN_FLAVOR" "Yarn 1 is identified as Classic"
  _node_apply_registry set "https://classic.after.example/" >/dev/null
  assert_file_contains "$path" "registry https://classic.after.example/" "Yarn Classic user registry changes"
  assert_file_contains "$path" "unsafeHttpWhitelist" "Yarn Classic preserves unrelated configuration"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Classic rollback restores the original file"

  path="${_TEST_ROOT}/node-project/.yarnrc.yml"
  cat >"$path" <<'YARNRC'
npmRegistryServer: "https://berry.before.example"
npmPublishRegistry: "https://publish.berry.example"
npmScopes:
  internal:
    npmRegistryServer: "https://scoped.berry.example"
    npmAuthToken: "BERRY_SECRET_SENTINEL"
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  NODE_TEST_YARN_VERSION="4.5.0"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal berry "$NODE_YARN_FLAVOR" "Yarn 2+ is identified as Berry"
  _node_apply_registry set "https://berry.after.example/" >/dev/null
  assert_file_contains "$path" 'npmRegistryServer: "https://berry.after.example/"' "Yarn Berry project registry changes"
  assert_file_contains "$path" 'npmPublishRegistry: "https://publish.berry.example"' "Yarn Berry preserves publish registry"
  assert_file_contains "$path" "https://scoped.berry.example" "Yarn Berry preserves scoped registry"
  assert_file_contains "$path" "BERRY_SECRET_SENTINEL" "Yarn Berry preserves scoped auth tokens"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Berry rollback restores the original file"

  NODE_REQUESTED=false NODE_ACTION="" NODE_CLIENT=npm NODE_SCOPE=user NODE_REGISTRY_URL=""
  NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_RESTORE_PATH="" NODE_TARGET_FILE="" NODE_YARN_FLAVOR=""
  DRY_RUN=true
  unset -f npm pnpm yarn _node_probe_registry _confirm_action
  unset -f _node_test_ini_set _node_test_yarn_classic_set _node_test_yarn_yaml_set
  if [[ "$home_set" == x ]]; then export HOME="$original_home"; else unset HOME; fi
  if [[ "$xdg_state_set" == x ]]; then export XDG_STATE_HOME="$original_xdg_state"; else unset XDG_STATE_HOME; fi
  if [[ "$xdg_config_set" == x ]]; then export XDG_CONFIG_HOME="$original_xdg_config"; else unset XDG_CONFIG_HOME; fi
  for ((code = 0; code < ${#override_names[@]}; code++)); do
    name="${override_names[$code]}"
    if [[ -n "${override_values[$code]}" ]]; then export "$name=${override_values[$code]}"; else unset "$name"; fi
  done
}

test_docker_manager_safety() {
  local path="$DOCKER_DAEMON_CONFIG" before after code output restart_log backup_mode
  mkdir -p "$DOCKER_CONFIG_DIR" "$APT_SOURCES_DIR"
  chmod 0750 "$BACKUP_BASE"
  _docker_require_backup_base
  backup_mode="$(stat -c '%a' "$BACKUP_BASE")"
  assert_equal "750" "$backup_mode" "Docker backup setup preserves the shared APT backup parent permissions"
  cat >"${APT_SOURCES_DIR}/docker.sources" <<'DOCKERSOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKERSOURCES

  _docker_scan_apt_sources
  assert_equal "1" "$DOCKER_APT_SOURCE_COUNT" "Docker Engine APT source is detected separately"
  assert_contains "noble" "${DOCKER_APT_SOURCE_SUITES[*]}" "Docker APT suite is reported"
  output="$(_docker_validate_mirror_url "https://mirror.gcr.io/")"
  assert_equal "https://mirror.gcr.io" "$output" "Docker mirror origin is normalized"
  code=0
  _docker_validate_mirror_url "http://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects plain HTTP"
  code=0
  _docker_validate_mirror_url "https://user:secret@mirror.example" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects embedded credentials"
  code=0
  _docker_validate_mirror_url "https://mirror.example/tenant" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects URL paths"
  code=0
  _docker_validate_mirror_url "https://mirror.example/?token=hidden" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects query strings"
  output="$(_docker_url_origin_label "https://user:secret@mirror.example:8443/private/path?token=hidden")"
  assert_equal "https://mirror.example:8443" "$output" "Docker mirror labels hide paths and credentials"

  _docker_probe_mirror() {
    DOCKER_PROBE_STATUS=401
    DOCKER_PROBE_HOST="$(_docker_url_origin_label "$1")"
    return 0
  }
  _confirm_action() { return 0; }
  dockerd() {
    [[ "${DOCKER_TEST_DOCKERD_FAIL:-false}" != true ]] || return 1
    return 0
  }

  cat >"$path" <<'DAEMONJSON'
{
  "debug": true,
  "log-driver": "json-file",
  "registry-mirrors": ["https://existing.example"]
}
DAEMONJSON
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  _docker_read_config
  assert_equal "valid" "$DOCKER_CONFIG_STATUS" "Docker daemon JSON object is recognized"
  assert_equal "1" "${#DOCKER_CONFIG_MIRROR_ORIGINS[@]}" "Existing registry mirror list is read"
  assert_equal "https://existing.example" "${DOCKER_CONFIG_MIRROR_ORIGINS[0]}" "Existing mirror output is origin-only"
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=false
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  assert_file_contains "$path" '"debug": true' "Docker merge preserves unrelated boolean settings"
  assert_file_contains "$path" '"log-driver": "json-file"' "Docker merge preserves unrelated daemon settings"
  assert_file_contains "$path" '"https://existing.example"' "Docker merge preserves existing registry mirrors"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker merge adds the selected mirror"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker daemon config permissions are preserved"
  python3 - "$path" <<'PY' || code=$?
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["debug"] is True
assert data["log-driver"] == "json-file"
assert data["registry-mirrors"] == [
    "https://existing.example",
    "https://mirror.gcr.io",
]
PY
  assert_exit_code 0 "${code:-0}" "Docker daemon JSON remains valid and preserves the full mirror array"
  [[ -f "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker configuration saves a rollback state pointer"
  restart_log="${_TEST_ROOT}/docker-systemctl.log"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Saving daemon.json never restarts Docker"

  cp "$path" "${_TEST_ROOT}/docker-after.json"
  printf '%s\n' " " >>"$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "Docker rollback refuses an externally modified daemon.json"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker rollback conflict preserves external edits"
  cp "${_TEST_ROOT}/docker-after.json" "$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Docker rollback succeeds when the after-hash still matches"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Docker rollback restores daemon.json byte-for-byte"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker reset clears the app-managed state pointer"

  rm -f -- "$path"
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  [[ -f "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker can create daemon.json when the Docker config directory exists"
  _docker_reset_mirror >/dev/null
  [[ ! -e "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker rollback removes a config file that did not exist before"

  printf '%s\n' '{invalid-json' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses malformed daemon.json"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Malformed daemon.json remains untouched"

  printf '%s\n' '{"registry-mirrors":"not-an-array"}' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a non-array registry-mirrors value"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Invalid registry-mirrors type remains untouched"

  printf '%s\n' '{"debug":true}' >"$path"
  before="$(sha256sum "$path")"
  DOCKER_TEST_DOCKERD_FAIL=true
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker manager refuses config rejected by dockerd --validate"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Failed dockerd validation leaves daemon.json unchanged"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Failed pre-write validation does not save active state"
  DOCKER_TEST_DOCKERD_FAIL=false

  rm -f -- "$path"
  ln -s "${_TEST_ROOT}/docker-symlink-target.json" "$path"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a symlinked daemon.json target"
  [[ -L "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Rejected Docker symlink is left untouched"
  rm -f -- "$path"
  printf '%s\n' '{"debug":true}' >"$path"

  JSON_OUTPUT=true
  output="$(_docker_status_report)"
  python3 - "$output" <<'PY' || code=$?
import json
import sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
assert data["command"] == "docker-status"
assert data["docker_engine_apt"]["source_records"] == 1
assert data["daemon"]["config_status"] == "valid"
assert isinstance(data["daemon"]["registry_mirrors"], list)
PY
  assert_exit_code 0 "${code:-0}" "Docker status JSON follows schema version 1"
  JSON_OUTPUT=false

  systemctl() {
    case "$1" in
    is-active) return 0 ;;
    restart) printf '%s\n' "restart docker" >>"$restart_log" ;;
    *) return 1 ;;
    esac
  }
  _confirm_action() {
    local answer=""
    if [[ "$YES" == true ]]; then
      return 0
    fi
    if ! _is_interactive; then
      return "$EXIT_USAGE"
    fi
    IFS= read -r answer || answer=""
    case "${answer,,}" in
    y | yes) return 0 ;;
    *) return "$EXIT_CANCELLED" ;;
    esac
  }
  YES=false
  _is_interactive() { return 1; }
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Non-interactive Docker restart requires explicit --yes"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Unapproved Docker restart never calls systemctl restart"
  _is_interactive() { return 0; }
  code=0
  printf 'n\n' | _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 10 "$code" "Interactive Docker restart can be declined"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Declined Docker restart never calls systemctl restart"
  YES=true
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Explicitly approved Docker restart is executed"
  assert_file_contains "$restart_log" "restart docker" "Docker restart uses the docker service unit"

  unset -f systemctl _docker_probe_mirror dockerd
  unset -f _confirm_action
  DOCKER_REQUESTED=false DOCKER_ACTION="" DOCKER_MIRROR_URL="" DOCKER_RESTORE_PATH=""
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=true
  YES=false
  JSON_OUTPUT=false
}

_run_test_group() {
  local current="$1" total="$2" label="$3" test_function="$4"
  local started="$SECONDS" elapsed eta=0
  printf '\n[%d/%d] Running %s...\n' "$current" "$total" "$label"
  "$test_function"
  elapsed=$((SECONDS - started))
  if ((current < total)); then
    eta=$(((elapsed * (total - current) + current - 1) / current))
    printf '[%d/%d] Completed %s in %ds | estimated remaining ~%ds\n' \
      "$current" "$total" "$label" "$elapsed" "$eta"
  else
    printf '[%d/%d] Completed %s in %ds | all test groups finished\n' \
      "$current" "$total" "$label" "$elapsed"
  fi
}

main() {
  printf '\nLinux Package Source Manager — Offline Test Suite\n'
  printf '%s\n' '===================================='
  _run_test_group 1 9 "CLI validation" test_cli
  _run_test_group 2 9 "Filesystem and configuration safety" test_filesystem_operations
  _run_test_group 3 9 "Terminal menu and task progress" test_terminal_menu_progress
  _run_test_group 4 9 "Probe parsing and mirror list criteria" test_probe_parser_and_list_criteria
  _run_test_group 5 9 "Catalog and Release metadata" test_catalog_and_release_metadata
  _run_test_group 6 9 "Mirror benchmark and read-only safety" test_benchmark_selection_and_read_only_safety
  _run_test_group 7 9 "Python package source manager" test_python_manager_safety
  _run_test_group 8 9 "Node.js registry manager" test_node_manager_safety
  _run_test_group 9 9 "Docker / OCI manager" test_docker_manager_safety
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"
 "$APT_DEB822_FILE")" "managed Deb822 updates archive URI only"
  assert_file_contains "$APT_DEB822_FILE" 'URIs: https://security.ubuntu.com/ubuntu' "managed Deb822 preserves security archive URI"

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

  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK=false
  dpkg() { printf 'arm64\n'; }
  export -f dpkg
  local ports_mode=1 ports_mirrors
  _uses_ports_archive && ports_mode=0
  assert_exit_code 0 "$ports_mode" "non-x86 architecture uses the Ubuntu ports archive"
  ports_mirrors="$(_get_mirrors)"
  assert_contains "https://ports.ubuntu.com/ubuntu-ports" "$ports_mirrors" "ports catalog is available for non-x86 architecture"
  unset -f dpkg

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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# write-rollback-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# Power APT Boost test fixture\n# current-network-will-be-restored\n' >"$APT_CONF_FILE"
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

test_terminal_menu_progress() {
  local menu_output value code
  local menu_log="${_TEST_ROOT}/menu-output.log"
  local progress_log="${_TEST_ROOT}/progress-output.log"

  menu_output=""
  _menu_choose "Menu test" "Choose one option" \
    "first" "First option" \
    "second" "Second option" \
    <<<"invalid
02" >"${_TEST_ROOT}/menu-choice.out" 2>"$menu_log" || true
  menu_output="$(cat "${_TEST_ROOT}/menu-choice.out")"
  assert_equal "second" "$menu_output" "terminal menu maps numeric input to the selected option"
  assert_file_contains "$menu_log" "1) First option" "terminal menu displays numbered options"
  assert_file_contains "$menu_log" "2) Second option" "terminal menu displays every numbered option"
  assert_file_contains "$menu_log" "Invalid selection" "terminal menu rejects non-numeric input"

  code=0
  _menu_choose "Menu test" "Choose one option" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits a menu without selecting an action"
  assert_file_contains "$menu_log" "0) Back" "submenu zero entry is labeled Back"

  code=0
  _menu_choose --zero-label "Exit" "Main menu test" "Choose an action" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits the main menu"
  assert_file_contains "$menu_log" "0) Exit" "main menu zero entry is labeled Exit"

  value="$(_menu_input "Input test" "Enter a value" "fallback" <<<"")"
  assert_equal "fallback" "$value" "terminal input accepts the displayed default"

  _menu_message "Completed" "The operation has finished." <<<"" 2>"$menu_log"
  assert_file_contains "$menu_log" "Press Enter to return to the menu" "completion messages wait for Enter"

  _print_task_progress "Mirror checks" 2 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "[2/3]" "task progress displays the completed and total counts"
  assert_file_contains "$progress_log" "ETA" "task progress displays an estimated remaining time"
  _print_task_progress "Mirror checks" 3 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "done" "task progress marks the final check as complete"
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

  cat >"${body}.static-main" <<'EOF'
Origin: Ubuntu
Label: Ubuntu
Suite: noble
Codename: noble
Date: Thu, 25 Apr 2024 15:10:33 UTC
EOF
  output="$(_validate_release_metadata "${body}.static-main" "noble" "noble")"
  assert_contains "valid|ok|static-suite-no-valid-until" "$output" "immutable Ubuntu base suite without Valid-Until remains valid after initial release"

  cat >"${body}.stale-dynamic" <<EOF
Origin: Ubuntu
Label: Ubuntu
Suite: noble-updates
Codename: noble
Date: $(date -u -d '9 days ago' -R)
EOF
  output="$(_validate_release_metadata "${body}.stale-dynamic" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|stale_release_metadata|stale" "$output" "dynamic Ubuntu updates suite without Valid-Until is still rejected when stale"

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
  local before after code progress_log
  local original_quiet="$QUIET" original_spinner="$NO_SPINNER" original_workers="$BENCH_WORKERS"
  progress_log="${_TEST_ROOT}/benchmark-progress.log"
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

  QUIET=false
  _select_mirror >/dev/null 2>"$progress_log"
  assert_file_contains "$progress_log" "[1/3] Mirror verification" "benchmark reports the first completed mirror"
  assert_file_contains "$progress_log" "[2/3] Mirror verification" "benchmark reports the second completed mirror"
  assert_file_contains "$progress_log" "[3/3] Mirror verification" "benchmark reports completion of every mirror"
  assert_file_contains "$progress_log" "ETA" "benchmark reports estimated remaining time while checks are pending"

  unset -f _load_mirror_catalog _get_mirrors _test_mirror
  QUIET="$original_quiet"
  NO_SPINNER="$original_spinner"
  BENCH_WORKERS="$original_workers"
}

test_python_manager_safety() {
  local valid output code path original_xdg xdg_was_set original_pip_index pip_index_was_set
  local original_pip_config pip_config_was_set snapshot before after
  original_xdg="${XDG_STATE_HOME-}"
  xdg_was_set="${XDG_STATE_HOME+x}"
  original_pip_index="${PIP_INDEX_URL-}"
  pip_index_was_set="${PIP_INDEX_URL+x}"
  original_pip_config="${PIP_CONFIG_FILE-}"
  pip_config_was_set="${PIP_CONFIG_FILE+x}"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  valid="$(_python_validate_index_url "https://pypi.org/simple")"
  assert_equal "https://pypi.org/simple/" "$valid" "Python index URL is normalized"
  code=0
  _python_validate_index_url "http://pypi.org/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects insecure HTTP"
  code=0
  _python_validate_index_url "https://user:secret@example.com/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects embedded credentials"
  code=0
  _python_validate_index_url "https://example.com/packages/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index requires a simple endpoint"
  code=0
  _python_validate_index_url "https://example.com/simple/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects query strings"
  output="$(_python_url_label "https://user:secret@example.com:8443/private/simple/")"
  assert_equal "https://example.com:8443/private/simple/" "$output" "Python index display masks credentials"
  POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED=true
  code=0
  _python_is_externally_managed || code=$?
  assert_exit_code 0 "$code" "PEP 668 guard recognizes externally-managed test marker"
  unset POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED

  _python_is_externally_managed() { return 0; }
  id() { printf '0'; }
  PYTHON_SCOPE=global
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "PEP 668 blocks global pip configuration"
  unset -f _python_is_externally_managed id
  PYTHON_SCOPE=auto

  export XDG_STATE_HOME="${_TEST_ROOT}/python-state"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  export PIP_INDEX_URL="https://user:secret@example.com/simple/"
  PYTHON_SCOPE=user
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "pip configuration refuses an environment index override"
  unset PIP_INDEX_URL
  PYTHON_SCOPE=auto

  FAKE_PIP_INDEX="https://new.example/simple/"
  _python_pip_get() { printf '%s' "$FAKE_PIP_INDEX"; }
  _python_pip_set() { FAKE_PIP_INDEX="$2"; }
  _python_pip_unset() { FAKE_PIP_INDEX=""; }

  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  FAKE_PIP_INDEX="https://manually-changed.example/simple/"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "pip snapshot refuses to overwrite a manually changed value"
  assert_equal "https://manually-changed.example/simple/" "$FAKE_PIP_INDEX" "pip conflict leaves the newer value untouched"

  FAKE_PIP_INDEX="https://new.example/simple/"
  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "pip snapshot restores a matching managed value"
  assert_equal "https://old.example/simple/" "$FAKE_PIP_INDEX" "pip snapshot restores the prior index"

  path="${_TEST_ROOT}/python-toml/pyproject.toml"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'TOML'
[project]
name = "fixture-project"

[[tool.uv.index]]
name = "private"
url = "https://private.example/simple/"
default = false

[tool.uv.sources]
private-package = { index = "private" }
TOML
  before="$(sha256sum "$path")"
  if python3 -c 'import tomllib' >/dev/null 2>&1 || python3 -c 'import tomli' >/dev/null 2>&1; then
    output="$(_python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv preview displays a managed source block"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv preview leaves the project file unchanged"

    _python_toml_edit write uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" "[[tool.uv.index]]" "uv project source is written to the correct TOML table"
    assert_file_contains "$path" 'name = "fixture-project"' "uv edit preserves unrelated project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "uv edit preserves an existing private index"
    assert_file_contains "$path" 'private-package = { index = "private" }' "uv edit preserves explicit project index pins"
    code=0
    _python_toml_edit write uv project "$path" "https://other.example/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "uv refuses a duplicate managed index/source name"

    before="$(sha256sum "$path")"
    output="$(_python_toml_edit remove-preview uv project "$path" "" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv reset preview identifies only the managed source"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv reset preview leaves the project file unchanged"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_snapshot_mark_after "$snapshot" uv "$path"
    printf '\n# external edit\n' >>"$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 8 "$code" "TOML snapshot refuses to overwrite a manually changed project file"
    assert_file_contains "$path" "# external edit" "TOML restore conflict leaves the manual edit intact"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    _python_snapshot_mark_after "$snapshot" uv "$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 0 "$code" "TOML snapshot restores a matching managed configuration"
    assert_file_contains "$path" "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "TOML snapshot restores the original managed source"

    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'name = "fixture-project"' "uv reset preserves unrelated TOML"
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "uv reset removes only the managed source block"

    path="${_TEST_ROOT}/python-toml/poetry/pyproject.toml"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<'TOML'
[tool.poetry]
name = "fixture-poetry"

[[tool.poetry.source]]
name = "private"
url = "https://private.example/simple/"
priority = "explicit"
TOML
    _python_toml_edit write poetry project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'priority = "supplemental"' "Poetry source uses the supplemental priority"
    assert_file_contains "$path" 'name = "fixture-poetry"' "Poetry edit preserves existing project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "Poetry edit preserves private source URLs"
    assert_file_contains "$path" 'priority = "explicit"' "Poetry edit preserves private source priority"
    _python_toml_edit remove poetry project "$path" "" "pab-test" supplemental >/dev/null
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "Poetry reset removes the app-managed source block"
  else
    code=0
    _python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "TOML editing fails closed when no parser is installed"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "unsupported TOML parser leaves the project file unchanged"
  fi

  if [[ "$pip_index_was_set" == x ]]; then export PIP_INDEX_URL="$original_pip_index"; else unset PIP_INDEX_URL; fi
  if [[ "$pip_config_was_set" == x ]]; then export PIP_CONFIG_FILE="$original_pip_config"; else unset PIP_CONFIG_FILE; fi
  if [[ "$xdg_was_set" == x ]]; then export XDG_STATE_HOME="$original_xdg"; else unset XDG_STATE_HOME; fi
  unset -f _python_pip_get _python_pip_set _python_pip_unset
}

_node_test_ini_set() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN { prefix=key "="; found=0 }
    index($0,prefix)==1 { if (!found) print prefix value; found=1; next }
    { print }
    END { if (!found) print prefix value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_classic_set() {
  local file="$1" value="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v value="$value" '
    BEGIN { found=0 }
    /^registry[[:space:]]+/ { if (!found) print "registry " value; found=1; next }
    { print }
    END { if (!found) print "registry " value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_yaml_set() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
key, value = sys.argv[2:]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
updated = []
found = False
for line in lines:
    if line.startswith(key + ":"):
        if not found:
            updated.append(f'{key}: "{value}"')
            found = True
    else:
        updated.append(line)
if not found:
    updated.append(f'{key}: "{value}"')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
}

test_node_manager_safety() {
  local original_home="$HOME" original_xdg_state="${XDG_STATE_HOME-}" original_xdg_config="${XDG_CONFIG_HOME-}"
  local home_set="${HOME+x}" xdg_state_set="${XDG_STATE_HOME+x}" xdg_config_set="${XDG_CONFIG_HOME+x}"
  local -a override_names=(npm_config_registry NPM_CONFIG_REGISTRY npm_config_userconfig NPM_CONFIG_USERCONFIG
    npm_config_globalconfig NPM_CONFIG_GLOBALCONFIG pnpm_config_registry PNPM_CONFIG_REGISTRY
    YARN_NPM_REGISTRY_SERVER YARN_RC_FILENAME YARN_IGNORE_PATH)
  local -a override_values=()
  local name output code url snapshot before after path
  for name in "${override_names[@]}"; do
    override_values+=("${!name-}")
    unset "$name"
  done

  HOME="${_TEST_ROOT}/node-home"
  XDG_CONFIG_HOME="$HOME/.config"
  XDG_STATE_HOME="${_TEST_ROOT}/node-state"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME
  DRY_RUN=false
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/pnpm" "${_TEST_ROOT}/node-project"
  printf '%s\n' '{"name":"node-fixture","publishConfig":{"registry":"https://publish.example/"}}' >"${_TEST_ROOT}/node-project/package.json"

  output="$(_node_validate_registry_url "https://registry.npmjs.org")"
  assert_equal "https://registry.npmjs.org/" "$output" "Node.js registry URL is normalized"
  code=0
  _node_validate_registry_url "http://registry.npmjs.org/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects plain HTTP"
  code=0
  _node_validate_registry_url "https://user:secret@registry.example/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects embedded credentials"
  code=0
  _node_validate_registry_url "https://registry.example/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects query strings"
  code=0
  _node_validate_registry_url "https://registry.example/#fragment" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects fragments"
  output="$(_node_url_label "https://user:secret@registry.example:8443/path/?token=hidden#fragment")"
  assert_equal "https://registry.example:8443" "$output" "Node.js registry display exposes only the origin"
  output="$(_node_url_label "https://registry.example/tenant-secret/path/")"
  assert_equal "https://registry.example" "$output" "Node.js registry display never exposes path credentials"
  output="$(_node_url_label "undefined")"
  assert_equal "not configured" "$output" "Node.js registry display handles unset values"
  output="$(_node_validate_package_name "@acme/valid-package")"
  assert_equal "@acme/valid-package" "$output" "Node.js package validator accepts scoped package names"
  code=0
  _node_validate_package_name "../escape" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js package validator rejects traversal names"

  npm() {
    if [[ "$1 $2 $3" == "config get userconfig" ]]; then
      printf '%s/.npmrc\n' "$HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  pnpm() {
    if [[ "$1 $2 $3" == "config get globalconfig" ]]; then
      printf '%s/pnpm/rc\n' "$XDG_CONFIG_HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  NODE_TEST_YARN_VERSION="1.22.22"
  yarn() {
    if [[ "$1" == "--version" ]]; then
      printf '%s\n' "$NODE_TEST_YARN_VERSION"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$PWD/.yarnrc"
      sed -n 's/^registry[[:space:]][[:space:]]*//p' "$file" 2>/dev/null | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config get npmRegistryServer" ]]; then
      local file="$PWD/.yarnrc.yml"
      sed -n 's/^npmRegistryServer:[[:space:]]*//p' "$file" 2>/dev/null | tr -d '"' | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.yarnrc"
      [[ "$PWD" == "$HOME" || "$*" == *"--global"* ]] || file="$PWD/.yarnrc"
      _node_test_yarn_classic_set "$file" "$4"
      return $?
    fi
    if [[ "$1 $2 $3" == "config set npmRegistryServer" ]]; then
      local file="$HOME/.yarnrc.yml"
      [[ "$PWD" == "$HOME" || "$*" == *"--home"* ]] || file="$PWD/.yarnrc.yml"
      _node_test_yarn_yaml_set "$file" npmRegistryServer "$4"
      return $?
    fi
    return 2
  }

  _node_probe_registry() { return 0; }
  _confirm_action() { return 0; }

  path="$HOME/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://registry.before.example/
@internal:registry=https://packages.internal.example/
//registry.before.example/:_authToken=NODE_SECRET_SENTINEL
NPMRC
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  NODE_CLIENT=npm NODE_SCOPE=user NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_YARN_FLAVOR=""
  _node_apply_registry set "https://registry.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://registry.after.example/" "npm user registry changes the default registry"
  assert_file_contains "$path" "@internal:registry=https://packages.internal.example/" "npm preserves scoped registry entries"
  assert_file_contains "$path" "NODE_SECRET_SENTINEL" "npm preserves auth token values"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "npm preserves config file permissions"
  snapshot="$(cat "$(_node_state_path npm user "$path")")"
  cp "$path" "$_TEST_ROOT/npm-after.npmrc"
  printf '%s\n' '# external change' >>"$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "npm restore refuses an externally modified file"
  assert_file_contains "$path" "# external change" "npm restore conflict preserves the external edit"
  cp "$_TEST_ROOT/npm-after.npmrc" "$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "npm reset restores its prior config"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "npm restore reproduces the original file bytes"

  path="${_TEST_ROOT}/node-project/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://project.before.example/
@private:registry=https://private.project.example/
//private.project.example/:_authToken=PROJECT_SECRET_SENTINEL
NPMRC
  NODE_CLIENT=pnpm NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://project.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://project.after.example/" "pnpm project scope changes the default registry"
  assert_file_contains "$path" "@private:registry=https://private.project.example/" "pnpm preserves scoped registries"
  assert_file_contains "$path" "PROJECT_SECRET_SENTINEL" "pnpm preserves project auth tokens"
  assert_file_contains "${_TEST_ROOT}/node-project/package.json" '"registry":"https://publish.example/"' "pnpm leaves package publishConfig untouched"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm project rollback restores the original .npmrc"

  XDG_CONFIG_HOME="${_TEST_ROOT}/external-xdg-config"
  export XDG_CONFIG_HOME
  mkdir -p "$XDG_CONFIG_HOME/pnpm"
  path="$XDG_CONFIG_HOME/pnpm/rc"
  printf '%s\n' "registry=https://pnpm.before.example/" >"$path"
  NODE_CLIENT=pnpm NODE_SCOPE=user NODE_PROJECT_DIR=""
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://pnpm.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://pnpm.after.example/" "pnpm user scope honors an external XDG_CONFIG_HOME"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm external XDG config is restored exactly"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME
  path="$HOME/.yarnrc"
  cat >"$path" <<'YARNRC'
registry https://classic.before.example
unsafeHttpWhitelist
  - internal.example
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=user NODE_PROJECT_DIR=""
  NODE_TEST_YARN_VERSION="1.22.22"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal classic "$NODE_YARN_FLAVOR" "Yarn 1 is identified as Classic"
  _node_apply_registry set "https://classic.after.example/" >/dev/null
  assert_file_contains "$path" "registry https://classic.after.example/" "Yarn Classic user registry changes"
  assert_file_contains "$path" "unsafeHttpWhitelist" "Yarn Classic preserves unrelated configuration"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Classic rollback restores the original file"

  path="${_TEST_ROOT}/node-project/.yarnrc.yml"
  cat >"$path" <<'YARNRC'
npmRegistryServer: "https://berry.before.example"
npmPublishRegistry: "https://publish.berry.example"
npmScopes:
  internal:
    npmRegistryServer: "https://scoped.berry.example"
    npmAuthToken: "BERRY_SECRET_SENTINEL"
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  NODE_TEST_YARN_VERSION="4.5.0"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal berry "$NODE_YARN_FLAVOR" "Yarn 2+ is identified as Berry"
  _node_apply_registry set "https://berry.after.example/" >/dev/null
  assert_file_contains "$path" 'npmRegistryServer: "https://berry.after.example/"' "Yarn Berry project registry changes"
  assert_file_contains "$path" 'npmPublishRegistry: "https://publish.berry.example"' "Yarn Berry preserves publish registry"
  assert_file_contains "$path" "https://scoped.berry.example" "Yarn Berry preserves scoped registry"
  assert_file_contains "$path" "BERRY_SECRET_SENTINEL" "Yarn Berry preserves scoped auth tokens"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Berry rollback restores the original file"

  NODE_REQUESTED=false NODE_ACTION="" NODE_CLIENT=npm NODE_SCOPE=user NODE_REGISTRY_URL=""
  NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_RESTORE_PATH="" NODE_TARGET_FILE="" NODE_YARN_FLAVOR=""
  DRY_RUN=true
  unset -f npm pnpm yarn _node_probe_registry _confirm_action
  unset -f _node_test_ini_set _node_test_yarn_classic_set _node_test_yarn_yaml_set
  if [[ "$home_set" == x ]]; then export HOME="$original_home"; else unset HOME; fi
  if [[ "$xdg_state_set" == x ]]; then export XDG_STATE_HOME="$original_xdg_state"; else unset XDG_STATE_HOME; fi
  if [[ "$xdg_config_set" == x ]]; then export XDG_CONFIG_HOME="$original_xdg_config"; else unset XDG_CONFIG_HOME; fi
  for ((code = 0; code < ${#override_names[@]}; code++)); do
    name="${override_names[$code]}"
    if [[ -n "${override_values[$code]}" ]]; then export "$name=${override_values[$code]}"; else unset "$name"; fi
  done
}

test_docker_manager_safety() {
  local path="$DOCKER_DAEMON_CONFIG" before after code output restart_log backup_mode
  mkdir -p "$DOCKER_CONFIG_DIR" "$APT_SOURCES_DIR"
  chmod 0750 "$BACKUP_BASE"
  _docker_require_backup_base
  backup_mode="$(stat -c '%a' "$BACKUP_BASE")"
  assert_equal "750" "$backup_mode" "Docker backup setup preserves the shared APT backup parent permissions"
  cat >"${APT_SOURCES_DIR}/docker.sources" <<'DOCKERSOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKERSOURCES

  _docker_scan_apt_sources
  assert_equal "1" "$DOCKER_APT_SOURCE_COUNT" "Docker Engine APT source is detected separately"
  assert_contains "noble" "${DOCKER_APT_SOURCE_SUITES[*]}" "Docker APT suite is reported"
  output="$(_docker_validate_mirror_url "https://mirror.gcr.io/")"
  assert_equal "https://mirror.gcr.io" "$output" "Docker mirror origin is normalized"
  code=0
  _docker_validate_mirror_url "http://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects plain HTTP"
  code=0
  _docker_validate_mirror_url "https://user:secret@mirror.example" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects embedded credentials"
  code=0
  _docker_validate_mirror_url "https://mirror.example/tenant" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects URL paths"
  code=0
  _docker_validate_mirror_url "https://mirror.example/?token=hidden" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects query strings"
  output="$(_docker_url_origin_label "https://user:secret@mirror.example:8443/private/path?token=hidden")"
  assert_equal "https://mirror.example:8443" "$output" "Docker mirror labels hide paths and credentials"

  _docker_probe_mirror() {
    DOCKER_PROBE_STATUS=401
    DOCKER_PROBE_HOST="$(_docker_url_origin_label "$1")"
    return 0
  }
  _confirm_action() { return 0; }
  dockerd() {
    [[ "${DOCKER_TEST_DOCKERD_FAIL:-false}" != true ]] || return 1
    return 0
  }

  cat >"$path" <<'DAEMONJSON'
{
  "debug": true,
  "log-driver": "json-file",
  "registry-mirrors": ["https://existing.example"]
}
DAEMONJSON
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  _docker_read_config
  assert_equal "valid" "$DOCKER_CONFIG_STATUS" "Docker daemon JSON object is recognized"
  assert_equal "1" "${#DOCKER_CONFIG_MIRROR_ORIGINS[@]}" "Existing registry mirror list is read"
  assert_equal "https://existing.example" "${DOCKER_CONFIG_MIRROR_ORIGINS[0]}" "Existing mirror output is origin-only"
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=false
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  assert_file_contains "$path" '"debug": true' "Docker merge preserves unrelated boolean settings"
  assert_file_contains "$path" '"log-driver": "json-file"' "Docker merge preserves unrelated daemon settings"
  assert_file_contains "$path" '"https://existing.example"' "Docker merge preserves existing registry mirrors"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker merge adds the selected mirror"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker daemon config permissions are preserved"
  python3 - "$path" <<'PY' || code=$?
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["debug"] is True
assert data["log-driver"] == "json-file"
assert data["registry-mirrors"] == [
    "https://existing.example",
    "https://mirror.gcr.io",
]
PY
  assert_exit_code 0 "${code:-0}" "Docker daemon JSON remains valid and preserves the full mirror array"
  [[ -f "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker configuration saves a rollback state pointer"
  restart_log="${_TEST_ROOT}/docker-systemctl.log"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Saving daemon.json never restarts Docker"

  cp "$path" "${_TEST_ROOT}/docker-after.json"
  printf '%s\n' " " >>"$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "Docker rollback refuses an externally modified daemon.json"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker rollback conflict preserves external edits"
  cp "${_TEST_ROOT}/docker-after.json" "$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Docker rollback succeeds when the after-hash still matches"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Docker rollback restores daemon.json byte-for-byte"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker reset clears the app-managed state pointer"

  rm -f -- "$path"
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  [[ -f "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker can create daemon.json when the Docker config directory exists"
  _docker_reset_mirror >/dev/null
  [[ ! -e "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker rollback removes a config file that did not exist before"

  printf '%s\n' '{invalid-json' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses malformed daemon.json"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Malformed daemon.json remains untouched"

  printf '%s\n' '{"registry-mirrors":"not-an-array"}' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a non-array registry-mirrors value"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Invalid registry-mirrors type remains untouched"

  printf '%s\n' '{"debug":true}' >"$path"
  before="$(sha256sum "$path")"
  DOCKER_TEST_DOCKERD_FAIL=true
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker manager refuses config rejected by dockerd --validate"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Failed dockerd validation leaves daemon.json unchanged"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Failed pre-write validation does not save active state"
  DOCKER_TEST_DOCKERD_FAIL=false

  rm -f -- "$path"
  ln -s "${_TEST_ROOT}/docker-symlink-target.json" "$path"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a symlinked daemon.json target"
  [[ -L "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Rejected Docker symlink is left untouched"
  rm -f -- "$path"
  printf '%s\n' '{"debug":true}' >"$path"

  JSON_OUTPUT=true
  output="$(_docker_status_report)"
  python3 - "$output" <<'PY' || code=$?
import json
import sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
assert data["command"] == "docker-status"
assert data["docker_engine_apt"]["source_records"] == 1
assert data["daemon"]["config_status"] == "valid"
assert isinstance(data["daemon"]["registry_mirrors"], list)
PY
  assert_exit_code 0 "${code:-0}" "Docker status JSON follows schema version 1"
  JSON_OUTPUT=false

  systemctl() {
    case "$1" in
    is-active) return 0 ;;
    restart) printf '%s\n' "restart docker" >>"$restart_log" ;;
    *) return 1 ;;
    esac
  }
  _confirm_action() {
    local answer=""
    if [[ "$YES" == true ]]; then
      return 0
    fi
    if ! _is_interactive; then
      return "$EXIT_USAGE"
    fi
    IFS= read -r answer || answer=""
    case "${answer,,}" in
    y | yes) return 0 ;;
    *) return "$EXIT_CANCELLED" ;;
    esac
  }
  YES=false
  _is_interactive() { return 1; }
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Non-interactive Docker restart requires explicit --yes"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Unapproved Docker restart never calls systemctl restart"
  _is_interactive() { return 0; }
  code=0
  printf 'n\n' | _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 10 "$code" "Interactive Docker restart can be declined"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Declined Docker restart never calls systemctl restart"
  YES=true
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Explicitly approved Docker restart is executed"
  assert_file_contains "$restart_log" "restart docker" "Docker restart uses the docker service unit"

  unset -f systemctl _docker_probe_mirror dockerd
  unset -f _confirm_action
  DOCKER_REQUESTED=false DOCKER_ACTION="" DOCKER_MIRROR_URL="" DOCKER_RESTORE_PATH=""
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=true
  YES=false
  JSON_OUTPUT=false
}

_run_test_group() {
  local current="$1" total="$2" label="$3" test_function="$4"
  local started="$SECONDS" elapsed eta=0
  printf '\n[%d/%d] Running %s...\n' "$current" "$total" "$label"
  "$test_function"
  elapsed=$((SECONDS - started))
  if ((current < total)); then
    eta=$(((elapsed * (total - current) + current - 1) / current))
    printf '[%d/%d] Completed %s in %ds | estimated remaining ~%ds\n' \
      "$current" "$total" "$label" "$elapsed" "$eta"
  else
    printf '[%d/%d] Completed %s in %ds | all test groups finished\n' \
      "$current" "$total" "$label" "$elapsed"
  fi
}

main() {
  printf '\nLinux Package Source Manager — Offline Test Suite\n'
  printf '%s\n' '===================================='
  _run_test_group 1 9 "CLI validation" test_cli
  _run_test_group 2 9 "Filesystem and configuration safety" test_filesystem_operations
  _run_test_group 3 9 "Terminal menu and task progress" test_terminal_menu_progress
  _run_test_group 4 9 "Probe parsing and mirror list criteria" test_probe_parser_and_list_criteria
  _run_test_group 5 9 "Catalog and Release metadata" test_catalog_and_release_metadata
  _run_test_group 6 9 "Mirror benchmark and read-only safety" test_benchmark_selection_and_read_only_safety
  _run_test_group 7 9 "Python package source manager" test_python_manager_safety
  _run_test_group 8 9 "Node.js registry manager" test_node_manager_safety
  _run_test_group 9 9 "Docker / OCI manager" test_docker_manager_safety
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"
 "$APT_DEB822_FILE")" "managed Deb822 updates both archive URI fields"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Trusted: yes' "$APT_DEB822_FILE"
  local trusted_before trusted_after trusted_status=0
  trusted_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || trusted_status=$?
  trusted_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$trusted_status" "managed Deb822 rejects signature-bypass fields"
  assert_equal "$trusted_before" "$trusted_after" "rejected signature-bypass field leaves source file unchanged"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Allow-Insecure: yes' "$APT_DEB822_FILE"
  local insecure_before insecure_after insecure_status=0
  insecure_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || insecure_status=$?
  insecure_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$insecure_status" "managed Deb822 rejects Allow-Insecure"
  assert_equal "$insecure_before" "$insecure_after" "Allow-Insecure rejection preserves source file"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a Check-Valid-Until: no' "$APT_DEB822_FILE"
  local freshness_before freshness_after freshness_status=0
  freshness_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || freshness_status=$?
  freshness_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$freshness_status" "managed Deb822 rejects disabled Release freshness checks"
  assert_equal "$freshness_before" "$freshness_after" "freshness-check rejection preserves source file"

  write_managed_source_fixture "https://old.example/ubuntu"
  sed -i '/^Signed-By:/a X-Local-Option: keep' "$APT_DEB822_FILE"
  local unknown_before unknown_after unknown_status=0
  unknown_before="$(sha256sum "$APT_DEB822_FILE")"
  _write_apt_sources "https://new.example/ubuntu" >/dev/null 2>&1 || unknown_status=$?
  unknown_after="$(sha256sum "$APT_DEB822_FILE")"
  assert_exit_code 1 "$unknown_status" "managed Deb822 rejects unsupported fields"
  assert_equal "$unknown_before" "$unknown_after" "unsupported field rejection preserves source file"

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

  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK=false
  dpkg() { printf 'arm64\n'; }
  export -f dpkg
  local ports_mode=1 ports_mirrors
  _uses_ports_archive && ports_mode=0
  assert_exit_code 0 "$ports_mode" "non-x86 architecture uses the Ubuntu ports archive"
  ports_mirrors="$(_get_mirrors)"
  assert_contains "https://ports.ubuntu.com/ubuntu-ports" "$ports_mirrors" "ports catalog is available for non-x86 architecture"
  unset -f dpkg

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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# write-rollback-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# prior-apt-config\n' >>"$APT_CONF_FILE"
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
  printf '# Power APT Boost test fixture\n# current-network-will-be-restored\n' >"$APT_CONF_FILE"
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

test_terminal_menu_progress() {
  local menu_output value code
  local menu_log="${_TEST_ROOT}/menu-output.log"
  local progress_log="${_TEST_ROOT}/progress-output.log"

  menu_output=""
  _menu_choose "Menu test" "Choose one option" \
    "first" "First option" \
    "second" "Second option" \
    <<<"invalid
02" >"${_TEST_ROOT}/menu-choice.out" 2>"$menu_log" || true
  menu_output="$(cat "${_TEST_ROOT}/menu-choice.out")"
  assert_equal "second" "$menu_output" "terminal menu maps numeric input to the selected option"
  assert_file_contains "$menu_log" "1) First option" "terminal menu displays numbered options"
  assert_file_contains "$menu_log" "2) Second option" "terminal menu displays every numbered option"
  assert_file_contains "$menu_log" "Invalid selection" "terminal menu rejects non-numeric input"

  code=0
  _menu_choose "Menu test" "Choose one option" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits a menu without selecting an action"
  assert_file_contains "$menu_log" "0) Back" "submenu zero entry is labeled Back"

  code=0
  _menu_choose --zero-label "Exit" "Main menu test" "Choose an action" "first" "First option" <<<"0" >/dev/null 2>"$menu_log" || code=$?
  assert_exit_code 1 "$code" "zero exits the main menu"
  assert_file_contains "$menu_log" "0) Exit" "main menu zero entry is labeled Exit"

  value="$(_menu_input "Input test" "Enter a value" "fallback" <<<"")"
  assert_equal "fallback" "$value" "terminal input accepts the displayed default"

  _menu_message "Completed" "The operation has finished." <<<"" 2>"$menu_log"
  assert_file_contains "$menu_log" "Press Enter to return to the menu" "completion messages wait for Enter"

  _print_task_progress "Mirror checks" 2 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "[2/3]" "task progress displays the completed and total counts"
  assert_file_contains "$progress_log" "ETA" "task progress displays an estimated remaining time"
  _print_task_progress "Mirror checks" 3 3 0 2>"$progress_log"
  assert_file_contains "$progress_log" "done" "task progress marks the final check as complete"
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

  cat >"${body}.static-main" <<'EOF'
Origin: Ubuntu
Label: Ubuntu
Suite: noble
Codename: noble
Date: Thu, 25 Apr 2024 15:10:33 UTC
EOF
  output="$(_validate_release_metadata "${body}.static-main" "noble" "noble")"
  assert_contains "valid|ok|static-suite-no-valid-until" "$output" "immutable Ubuntu base suite without Valid-Until remains valid after initial release"

  cat >"${body}.stale-dynamic" <<EOF
Origin: Ubuntu
Label: Ubuntu
Suite: noble-updates
Codename: noble
Date: $(date -u -d '9 days ago' -R)
EOF
  output="$(_validate_release_metadata "${body}.stale-dynamic" "noble" "noble-updates" 2>/dev/null || true)"
  assert_contains "invalid|stale_release_metadata|stale" "$output" "dynamic Ubuntu updates suite without Valid-Until is still rejected when stale"

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
  local before after code progress_log
  local original_quiet="$QUIET" original_spinner="$NO_SPINNER" original_workers="$BENCH_WORKERS"
  progress_log="${_TEST_ROOT}/benchmark-progress.log"
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

  QUIET=false
  _select_mirror >/dev/null 2>"$progress_log"
  assert_file_contains "$progress_log" "[1/3] Mirror verification" "benchmark reports the first completed mirror"
  assert_file_contains "$progress_log" "[2/3] Mirror verification" "benchmark reports the second completed mirror"
  assert_file_contains "$progress_log" "[3/3] Mirror verification" "benchmark reports completion of every mirror"
  assert_file_contains "$progress_log" "ETA" "benchmark reports estimated remaining time while checks are pending"

  unset -f _load_mirror_catalog _get_mirrors _test_mirror
  QUIET="$original_quiet"
  NO_SPINNER="$original_spinner"
  BENCH_WORKERS="$original_workers"
}

test_python_manager_safety() {
  local valid output code path original_xdg xdg_was_set original_pip_index pip_index_was_set
  local original_pip_config pip_config_was_set snapshot before after
  original_xdg="${XDG_STATE_HOME-}"
  xdg_was_set="${XDG_STATE_HOME+x}"
  original_pip_index="${PIP_INDEX_URL-}"
  pip_index_was_set="${PIP_INDEX_URL+x}"
  original_pip_config="${PIP_CONFIG_FILE-}"
  pip_config_was_set="${PIP_CONFIG_FILE+x}"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  valid="$(_python_validate_index_url "https://pypi.org/simple")"
  assert_equal "https://pypi.org/simple/" "$valid" "Python index URL is normalized"
  code=0
  _python_validate_index_url "http://pypi.org/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects insecure HTTP"
  code=0
  _python_validate_index_url "https://user:secret@example.com/simple/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects embedded credentials"
  code=0
  _python_validate_index_url "https://example.com/packages/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index requires a simple endpoint"
  code=0
  _python_validate_index_url "https://example.com/simple/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Python index rejects query strings"
  output="$(_python_url_label "https://user:secret@example.com:8443/private/simple/")"
  assert_equal "https://example.com:8443/private/simple/" "$output" "Python index display masks credentials"
  POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED=true
  code=0
  _python_is_externally_managed || code=$?
  assert_exit_code 0 "$code" "PEP 668 guard recognizes externally-managed test marker"
  unset POWER_APT_BOOST_TEST_EXTERNALLY_MANAGED

  _python_is_externally_managed() { return 0; }
  id() { printf '0'; }
  PYTHON_SCOPE=global
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "PEP 668 blocks global pip configuration"
  unset -f _python_is_externally_managed id
  PYTHON_SCOPE=auto

  export XDG_STATE_HOME="${_TEST_ROOT}/python-state"
  unset PIP_INDEX_URL PIP_CONFIG_FILE
  export PIP_INDEX_URL="https://user:secret@example.com/simple/"
  PYTHON_SCOPE=user
  code=0
  _python_resolve_pip_scope >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "pip configuration refuses an environment index override"
  unset PIP_INDEX_URL
  PYTHON_SCOPE=auto

  FAKE_PIP_INDEX="https://new.example/simple/"
  _python_pip_get() { printf '%s' "$FAKE_PIP_INDEX"; }
  _python_pip_set() { FAKE_PIP_INDEX="$2"; }
  _python_pip_unset() { FAKE_PIP_INDEX=""; }

  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  FAKE_PIP_INDEX="https://manually-changed.example/simple/"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "pip snapshot refuses to overwrite a manually changed value"
  assert_equal "https://manually-changed.example/simple/" "$FAKE_PIP_INDEX" "pip conflict leaves the newer value untouched"

  FAKE_PIP_INDEX="https://new.example/simple/"
  snapshot="$(_python_snapshot_create pip user global.index-url true "https://old.example/simple/")"
  _python_snapshot_mark_after "$snapshot" pip "" "$FAKE_PIP_INDEX"
  code=0
  _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "pip snapshot restores a matching managed value"
  assert_equal "https://old.example/simple/" "$FAKE_PIP_INDEX" "pip snapshot restores the prior index"

  path="${_TEST_ROOT}/python-toml/pyproject.toml"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'TOML'
[project]
name = "fixture-project"

[[tool.uv.index]]
name = "private"
url = "https://private.example/simple/"
default = false

[tool.uv.sources]
private-package = { index = "private" }
TOML
  before="$(sha256sum "$path")"
  if python3 -c 'import tomllib' >/dev/null 2>&1 || python3 -c 'import tomli' >/dev/null 2>&1; then
    output="$(_python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv preview displays a managed source block"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv preview leaves the project file unchanged"

    _python_toml_edit write uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" "[[tool.uv.index]]" "uv project source is written to the correct TOML table"
    assert_file_contains "$path" 'name = "fixture-project"' "uv edit preserves unrelated project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "uv edit preserves an existing private index"
    assert_file_contains "$path" 'private-package = { index = "private" }' "uv edit preserves explicit project index pins"
    code=0
    _python_toml_edit write uv project "$path" "https://other.example/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "uv refuses a duplicate managed index/source name"

    before="$(sha256sum "$path")"
    output="$(_python_toml_edit remove-preview uv project "$path" "" "pab-test" supplemental)"
    assert_contains "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$output" "uv reset preview identifies only the managed source"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "uv reset preview leaves the project file unchanged"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_snapshot_mark_after "$snapshot" uv "$path"
    printf '\n# external edit\n' >>"$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 8 "$code" "TOML snapshot refuses to overwrite a manually changed project file"
    assert_file_contains "$path" "# external edit" "TOML restore conflict leaves the manual edit intact"

    snapshot="$(_python_snapshot_create uv project "$path" true)"
    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    _python_snapshot_mark_after "$snapshot" uv "$path"
    code=0
    _python_restore_snapshot "$snapshot" >/dev/null 2>&1 || code=$?
    assert_exit_code 0 "$code" "TOML snapshot restores a matching managed configuration"
    assert_file_contains "$path" "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "TOML snapshot restores the original managed source"

    _python_toml_edit remove uv project "$path" "" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'name = "fixture-project"' "uv reset preserves unrelated TOML"
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "uv reset removes only the managed source block"

    path="${_TEST_ROOT}/python-toml/poetry/pyproject.toml"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<'TOML'
[tool.poetry]
name = "fixture-poetry"

[[tool.poetry.source]]
name = "private"
url = "https://private.example/simple/"
priority = "explicit"
TOML
    _python_toml_edit write poetry project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null
    assert_file_contains "$path" 'priority = "supplemental"' "Poetry source uses the supplemental priority"
    assert_file_contains "$path" 'name = "fixture-poetry"' "Poetry edit preserves existing project metadata"
    assert_file_contains "$path" 'url = "https://private.example/simple/"' "Poetry edit preserves private source URLs"
    assert_file_contains "$path" 'priority = "explicit"' "Poetry edit preserves private source priority"
    _python_toml_edit remove poetry project "$path" "" "pab-test" supplemental >/dev/null
    code=0
    grep -q "BEGIN POWER APT BOOST MANAGED PYTHON SOURCE" "$path" || code=1
    assert_exit_code 1 "$code" "Poetry reset removes the app-managed source block"
  else
    code=0
    _python_toml_edit preview uv project "$path" "https://pypi.org/simple/" "pab-test" supplemental >/dev/null 2>&1 || code=$?
    assert_exit_code 2 "$code" "TOML editing fails closed when no parser is installed"
    after="$(sha256sum "$path")"
    assert_equal "$before" "$after" "unsupported TOML parser leaves the project file unchanged"
  fi

  if [[ "$pip_index_was_set" == x ]]; then export PIP_INDEX_URL="$original_pip_index"; else unset PIP_INDEX_URL; fi
  if [[ "$pip_config_was_set" == x ]]; then export PIP_CONFIG_FILE="$original_pip_config"; else unset PIP_CONFIG_FILE; fi
  if [[ "$xdg_was_set" == x ]]; then export XDG_STATE_HOME="$original_xdg"; else unset XDG_STATE_HOME; fi
  unset -f _python_pip_get _python_pip_set _python_pip_unset
}

_node_test_ini_set() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN { prefix=key "="; found=0 }
    index($0,prefix)==1 { if (!found) print prefix value; found=1; next }
    { print }
    END { if (!found) print prefix value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_classic_set() {
  local file="$1" value="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.node-test.XXXXXXXX")" || return 1
  awk -v value="$value" '
    BEGIN { found=0 }
    /^registry[[:space:]]+/ { if (!found) print "registry " value; found=1; next }
    { print }
    END { if (!found) print "registry " value }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  local rc=$?
  rm -f -- "$tmp"
  return "$rc"
}

_node_test_yarn_yaml_set() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
key, value = sys.argv[2:]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
updated = []
found = False
for line in lines:
    if line.startswith(key + ":"):
        if not found:
            updated.append(f'{key}: "{value}"')
            found = True
    else:
        updated.append(line)
if not found:
    updated.append(f'{key}: "{value}"')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
}

test_node_manager_safety() {
  local original_home="$HOME" original_xdg_state="${XDG_STATE_HOME-}" original_xdg_config="${XDG_CONFIG_HOME-}"
  local home_set="${HOME+x}" xdg_state_set="${XDG_STATE_HOME+x}" xdg_config_set="${XDG_CONFIG_HOME+x}"
  local -a override_names=(npm_config_registry NPM_CONFIG_REGISTRY npm_config_userconfig NPM_CONFIG_USERCONFIG
    npm_config_globalconfig NPM_CONFIG_GLOBALCONFIG pnpm_config_registry PNPM_CONFIG_REGISTRY
    YARN_NPM_REGISTRY_SERVER YARN_RC_FILENAME YARN_IGNORE_PATH)
  local -a override_values=()
  local name output code url snapshot before after path
  for name in "${override_names[@]}"; do
    override_values+=("${!name-}")
    unset "$name"
  done

  HOME="${_TEST_ROOT}/node-home"
  XDG_CONFIG_HOME="$HOME/.config"
  XDG_STATE_HOME="${_TEST_ROOT}/node-state"
  export HOME XDG_CONFIG_HOME XDG_STATE_HOME
  DRY_RUN=false
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/pnpm" "${_TEST_ROOT}/node-project"
  printf '%s\n' '{"name":"node-fixture","publishConfig":{"registry":"https://publish.example/"}}' >"${_TEST_ROOT}/node-project/package.json"

  output="$(_node_validate_registry_url "https://registry.npmjs.org")"
  assert_equal "https://registry.npmjs.org/" "$output" "Node.js registry URL is normalized"
  code=0
  _node_validate_registry_url "http://registry.npmjs.org/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects plain HTTP"
  code=0
  _node_validate_registry_url "https://user:secret@registry.example/" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects embedded credentials"
  code=0
  _node_validate_registry_url "https://registry.example/?token=secret" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects query strings"
  code=0
  _node_validate_registry_url "https://registry.example/#fragment" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js registry rejects fragments"
  output="$(_node_url_label "https://user:secret@registry.example:8443/path/?token=hidden#fragment")"
  assert_equal "https://registry.example:8443" "$output" "Node.js registry display exposes only the origin"
  output="$(_node_url_label "https://registry.example/tenant-secret/path/")"
  assert_equal "https://registry.example" "$output" "Node.js registry display never exposes path credentials"
  output="$(_node_url_label "undefined")"
  assert_equal "not configured" "$output" "Node.js registry display handles unset values"
  output="$(_node_validate_package_name "@acme/valid-package")"
  assert_equal "@acme/valid-package" "$output" "Node.js package validator accepts scoped package names"
  code=0
  _node_validate_package_name "../escape" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Node.js package validator rejects traversal names"

  npm() {
    if [[ "$1 $2 $3" == "config get userconfig" ]]; then
      printf '%s/.npmrc\n' "$HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.npmrc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  pnpm() {
    if [[ "$1 $2 $3" == "config get globalconfig" ]]; then
      printf '%s/pnpm/rc\n' "$XDG_CONFIG_HOME"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      awk -F= '$1=="registry" {v=substr($0,index($0,"=")+1)} END {if(v!="") print v; else print "undefined"}' "$file" 2>/dev/null
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$XDG_CONFIG_HOME/pnpm/rc"
      [[ "$*" != *"--location=project"* ]] || file="$PWD/.npmrc"
      _node_test_ini_set "$file" registry "$4"
      return $?
    fi
    return 2
  }

  NODE_TEST_YARN_VERSION="1.22.22"
  yarn() {
    if [[ "$1" == "--version" ]]; then
      printf '%s\n' "$NODE_TEST_YARN_VERSION"
      return 0
    fi
    if [[ "$1 $2 $3" == "config get registry" ]]; then
      local file="$PWD/.yarnrc"
      sed -n 's/^registry[[:space:]][[:space:]]*//p' "$file" 2>/dev/null | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config get npmRegistryServer" ]]; then
      local file="$PWD/.yarnrc.yml"
      sed -n 's/^npmRegistryServer:[[:space:]]*//p' "$file" 2>/dev/null | tr -d '"' | head -n 1
      return 0
    fi
    if [[ "$1 $2 $3" == "config set registry" ]]; then
      local file="$HOME/.yarnrc"
      [[ "$PWD" == "$HOME" || "$*" == *"--global"* ]] || file="$PWD/.yarnrc"
      _node_test_yarn_classic_set "$file" "$4"
      return $?
    fi
    if [[ "$1 $2 $3" == "config set npmRegistryServer" ]]; then
      local file="$HOME/.yarnrc.yml"
      [[ "$PWD" == "$HOME" || "$*" == *"--home"* ]] || file="$PWD/.yarnrc.yml"
      _node_test_yarn_yaml_set "$file" npmRegistryServer "$4"
      return $?
    fi
    return 2
  }

  _node_probe_registry() { return 0; }
  _confirm_action() { return 0; }

  path="$HOME/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://registry.before.example/
@internal:registry=https://packages.internal.example/
//registry.before.example/:_authToken=NODE_SECRET_SENTINEL
NPMRC
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  NODE_CLIENT=npm NODE_SCOPE=user NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_YARN_FLAVOR=""
  _node_apply_registry set "https://registry.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://registry.after.example/" "npm user registry changes the default registry"
  assert_file_contains "$path" "@internal:registry=https://packages.internal.example/" "npm preserves scoped registry entries"
  assert_file_contains "$path" "NODE_SECRET_SENTINEL" "npm preserves auth token values"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "npm preserves config file permissions"
  snapshot="$(cat "$(_node_state_path npm user "$path")")"
  cp "$path" "$_TEST_ROOT/npm-after.npmrc"
  printf '%s\n' '# external change' >>"$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "npm restore refuses an externally modified file"
  assert_file_contains "$path" "# external change" "npm restore conflict preserves the external edit"
  cp "$_TEST_ROOT/npm-after.npmrc" "$path"
  code=0
  _node_apply_registry reset >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "npm reset restores its prior config"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "npm restore reproduces the original file bytes"

  path="${_TEST_ROOT}/node-project/.npmrc"
  cat >"$path" <<'NPMRC'
registry=https://project.before.example/
@private:registry=https://private.project.example/
//private.project.example/:_authToken=PROJECT_SECRET_SENTINEL
NPMRC
  NODE_CLIENT=pnpm NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://project.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://project.after.example/" "pnpm project scope changes the default registry"
  assert_file_contains "$path" "@private:registry=https://private.project.example/" "pnpm preserves scoped registries"
  assert_file_contains "$path" "PROJECT_SECRET_SENTINEL" "pnpm preserves project auth tokens"
  assert_file_contains "${_TEST_ROOT}/node-project/package.json" '"registry":"https://publish.example/"' "pnpm leaves package publishConfig untouched"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm project rollback restores the original .npmrc"

  XDG_CONFIG_HOME="${_TEST_ROOT}/external-xdg-config"
  export XDG_CONFIG_HOME
  mkdir -p "$XDG_CONFIG_HOME/pnpm"
  path="$XDG_CONFIG_HOME/pnpm/rc"
  printf '%s\n' "registry=https://pnpm.before.example/" >"$path"
  NODE_CLIENT=pnpm NODE_SCOPE=user NODE_PROJECT_DIR=""
  before="$(sha256sum "$path")"
  _node_apply_registry set "https://pnpm.after.example/" >/dev/null
  assert_file_contains "$path" "registry=https://pnpm.after.example/" "pnpm user scope honors an external XDG_CONFIG_HOME"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "pnpm external XDG config is restored exactly"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME
  path="$HOME/.yarnrc"
  cat >"$path" <<'YARNRC'
registry https://classic.before.example
unsafeHttpWhitelist
  - internal.example
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=user NODE_PROJECT_DIR=""
  NODE_TEST_YARN_VERSION="1.22.22"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal classic "$NODE_YARN_FLAVOR" "Yarn 1 is identified as Classic"
  _node_apply_registry set "https://classic.after.example/" >/dev/null
  assert_file_contains "$path" "registry https://classic.after.example/" "Yarn Classic user registry changes"
  assert_file_contains "$path" "unsafeHttpWhitelist" "Yarn Classic preserves unrelated configuration"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Classic rollback restores the original file"

  path="${_TEST_ROOT}/node-project/.yarnrc.yml"
  cat >"$path" <<'YARNRC'
npmRegistryServer: "https://berry.before.example"
npmPublishRegistry: "https://publish.berry.example"
npmScopes:
  internal:
    npmRegistryServer: "https://scoped.berry.example"
    npmAuthToken: "BERRY_SECRET_SENTINEL"
YARNRC
  NODE_CLIENT=yarn NODE_SCOPE=project NODE_PROJECT_DIR="${_TEST_ROOT}/node-project"
  NODE_TEST_YARN_VERSION="4.5.0"
  before="$(sha256sum "$path")"
  _node_yarn_flavor
  assert_equal berry "$NODE_YARN_FLAVOR" "Yarn 2+ is identified as Berry"
  _node_apply_registry set "https://berry.after.example/" >/dev/null
  assert_file_contains "$path" 'npmRegistryServer: "https://berry.after.example/"' "Yarn Berry project registry changes"
  assert_file_contains "$path" 'npmPublishRegistry: "https://publish.berry.example"' "Yarn Berry preserves publish registry"
  assert_file_contains "$path" "https://scoped.berry.example" "Yarn Berry preserves scoped registry"
  assert_file_contains "$path" "BERRY_SECRET_SENTINEL" "Yarn Berry preserves scoped auth tokens"
  _node_apply_registry reset >/dev/null
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Yarn Berry rollback restores the original file"

  NODE_REQUESTED=false NODE_ACTION="" NODE_CLIENT=npm NODE_SCOPE=user NODE_REGISTRY_URL=""
  NODE_PROJECT_DIR="" NODE_TEST_PACKAGE=is-number NODE_RESTORE_PATH="" NODE_TARGET_FILE="" NODE_YARN_FLAVOR=""
  DRY_RUN=true
  unset -f npm pnpm yarn _node_probe_registry _confirm_action
  unset -f _node_test_ini_set _node_test_yarn_classic_set _node_test_yarn_yaml_set
  if [[ "$home_set" == x ]]; then export HOME="$original_home"; else unset HOME; fi
  if [[ "$xdg_state_set" == x ]]; then export XDG_STATE_HOME="$original_xdg_state"; else unset XDG_STATE_HOME; fi
  if [[ "$xdg_config_set" == x ]]; then export XDG_CONFIG_HOME="$original_xdg_config"; else unset XDG_CONFIG_HOME; fi
  for ((code = 0; code < ${#override_names[@]}; code++)); do
    name="${override_names[$code]}"
    if [[ -n "${override_values[$code]}" ]]; then export "$name=${override_values[$code]}"; else unset "$name"; fi
  done
}

test_docker_manager_safety() {
  local path="$DOCKER_DAEMON_CONFIG" before after code output restart_log backup_mode
  mkdir -p "$DOCKER_CONFIG_DIR" "$APT_SOURCES_DIR"
  chmod 0750 "$BACKUP_BASE"
  _docker_require_backup_base
  backup_mode="$(stat -c '%a' "$BACKUP_BASE")"
  assert_equal "750" "$backup_mode" "Docker backup setup preserves the shared APT backup parent permissions"
  cat >"${APT_SOURCES_DIR}/docker.sources" <<'DOCKERSOURCES'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKERSOURCES

  _docker_scan_apt_sources
  assert_equal "1" "$DOCKER_APT_SOURCE_COUNT" "Docker Engine APT source is detected separately"
  assert_contains "noble" "${DOCKER_APT_SOURCE_SUITES[*]}" "Docker APT suite is reported"
  output="$(_docker_validate_mirror_url "https://mirror.gcr.io/")"
  assert_equal "https://mirror.gcr.io" "$output" "Docker mirror origin is normalized"
  code=0
  _docker_validate_mirror_url "http://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects plain HTTP"
  code=0
  _docker_validate_mirror_url "https://user:secret@mirror.example" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects embedded credentials"
  code=0
  _docker_validate_mirror_url "https://mirror.example/tenant" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects URL paths"
  code=0
  _docker_validate_mirror_url "https://mirror.example/?token=hidden" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker mirror validator rejects query strings"
  output="$(_docker_url_origin_label "https://user:secret@mirror.example:8443/private/path?token=hidden")"
  assert_equal "https://mirror.example:8443" "$output" "Docker mirror labels hide paths and credentials"

  _docker_probe_mirror() {
    DOCKER_PROBE_STATUS=401
    DOCKER_PROBE_HOST="$(_docker_url_origin_label "$1")"
    return 0
  }
  _confirm_action() { return 0; }
  dockerd() {
    [[ "${DOCKER_TEST_DOCKERD_FAIL:-false}" != true ]] || return 1
    return 0
  }

  cat >"$path" <<'DAEMONJSON'
{
  "debug": true,
  "log-driver": "json-file",
  "registry-mirrors": ["https://existing.example"]
}
DAEMONJSON
  chmod 0640 "$path"
  before="$(sha256sum "$path")"
  _docker_read_config
  assert_equal "valid" "$DOCKER_CONFIG_STATUS" "Docker daemon JSON object is recognized"
  assert_equal "1" "${#DOCKER_CONFIG_MIRROR_ORIGINS[@]}" "Existing registry mirror list is read"
  assert_equal "https://existing.example" "${DOCKER_CONFIG_MIRROR_ORIGINS[0]}" "Existing mirror output is origin-only"
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=false
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  assert_file_contains "$path" '"debug": true' "Docker merge preserves unrelated boolean settings"
  assert_file_contains "$path" '"log-driver": "json-file"' "Docker merge preserves unrelated daemon settings"
  assert_file_contains "$path" '"https://existing.example"' "Docker merge preserves existing registry mirrors"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker merge adds the selected mirror"
  [[ "$(stat -c '%a' "$path")" == 640 ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker daemon config permissions are preserved"
  python3 - "$path" <<'PY' || code=$?
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["debug"] is True
assert data["log-driver"] == "json-file"
assert data["registry-mirrors"] == [
    "https://existing.example",
    "https://mirror.gcr.io",
]
PY
  assert_exit_code 0 "${code:-0}" "Docker daemon JSON remains valid and preserves the full mirror array"
  [[ -f "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker configuration saves a rollback state pointer"
  restart_log="${_TEST_ROOT}/docker-systemctl.log"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Saving daemon.json never restarts Docker"

  cp "$path" "${_TEST_ROOT}/docker-after.json"
  printf '%s\n' " " >>"$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 8 "$code" "Docker rollback refuses an externally modified daemon.json"
  assert_file_contains "$path" '"https://mirror.gcr.io"' "Docker rollback conflict preserves external edits"
  cp "${_TEST_ROOT}/docker-after.json" "$path"
  code=0
  _docker_reset_mirror >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Docker rollback succeeds when the after-hash still matches"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Docker rollback restores daemon.json byte-for-byte"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker reset clears the app-managed state pointer"

  rm -f -- "$path"
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null
  [[ -f "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker can create daemon.json when the Docker config directory exists"
  _docker_reset_mirror >/dev/null
  [[ ! -e "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Docker rollback removes a config file that did not exist before"

  printf '%s\n' '{invalid-json' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses malformed daemon.json"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Malformed daemon.json remains untouched"

  printf '%s\n' '{"registry-mirrors":"not-an-array"}' >"$path"
  before="$(sha256sum "$path")"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a non-array registry-mirrors value"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Invalid registry-mirrors type remains untouched"

  printf '%s\n' '{"debug":true}' >"$path"
  before="$(sha256sum "$path")"
  DOCKER_TEST_DOCKERD_FAIL=true
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 1 "$code" "Docker manager refuses config rejected by dockerd --validate"
  after="$(sha256sum "$path")"
  assert_equal "$before" "$after" "Failed dockerd validation leaves daemon.json unchanged"
  [[ ! -e "$DOCKER_STATE_FILE" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Failed pre-write validation does not save active state"
  DOCKER_TEST_DOCKERD_FAIL=false

  rm -f -- "$path"
  ln -s "${_TEST_ROOT}/docker-symlink-target.json" "$path"
  code=0
  _docker_apply_mirror "https://mirror.gcr.io" >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Docker manager refuses a symlinked daemon.json target"
  [[ -L "$path" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Rejected Docker symlink is left untouched"
  rm -f -- "$path"
  printf '%s\n' '{"debug":true}' >"$path"

  JSON_OUTPUT=true
  output="$(_docker_status_report)"
  python3 - "$output" <<'PY' || code=$?
import json
import sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
assert data["command"] == "docker-status"
assert data["docker_engine_apt"]["source_records"] == 1
assert data["daemon"]["config_status"] == "valid"
assert isinstance(data["daemon"]["registry_mirrors"], list)
PY
  assert_exit_code 0 "${code:-0}" "Docker status JSON follows schema version 1"
  JSON_OUTPUT=false

  systemctl() {
    case "$1" in
    is-active) return 0 ;;
    restart) printf '%s\n' "restart docker" >>"$restart_log" ;;
    *) return 1 ;;
    esac
  }
  _confirm_action() {
    local answer=""
    if [[ "$YES" == true ]]; then
      return 0
    fi
    if ! _is_interactive; then
      return "$EXIT_USAGE"
    fi
    IFS= read -r answer || answer=""
    case "${answer,,}" in
    y | yes) return 0 ;;
    *) return "$EXIT_CANCELLED" ;;
    esac
  }
  YES=false
  _is_interactive() { return 1; }
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 2 "$code" "Non-interactive Docker restart requires explicit --yes"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Unapproved Docker restart never calls systemctl restart"
  _is_interactive() { return 0; }
  code=0
  printf 'n\n' | _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 10 "$code" "Interactive Docker restart can be declined"
  [[ ! -e "$restart_log" ]] && code=0 || code=1
  assert_exit_code 0 "$code" "Declined Docker restart never calls systemctl restart"
  YES=true
  code=0
  _docker_restart_daemon >/dev/null 2>&1 || code=$?
  assert_exit_code 0 "$code" "Explicitly approved Docker restart is executed"
  assert_file_contains "$restart_log" "restart docker" "Docker restart uses the docker service unit"

  unset -f systemctl _docker_probe_mirror dockerd
  unset -f _confirm_action
  DOCKER_REQUESTED=false DOCKER_ACTION="" DOCKER_MIRROR_URL="" DOCKER_RESTORE_PATH=""
  DOCKER_TEST_DOCKERD_FAIL=false
  DRY_RUN=true
  YES=false
  JSON_OUTPUT=false
}

_run_test_group() {
  local current="$1" total="$2" label="$3" test_function="$4"
  local started="$SECONDS" elapsed eta=0
  printf '\n[%d/%d] Running %s...\n' "$current" "$total" "$label"
  "$test_function"
  elapsed=$((SECONDS - started))
  if ((current < total)); then
    eta=$(((elapsed * (total - current) + current - 1) / current))
    printf '[%d/%d] Completed %s in %ds | estimated remaining ~%ds\n' \
      "$current" "$total" "$label" "$elapsed" "$eta"
  else
    printf '[%d/%d] Completed %s in %ds | all test groups finished\n' \
      "$current" "$total" "$label" "$elapsed"
  fi
}

main() {
  printf '\nLinux Package Source Manager — Offline Test Suite\n'
  printf '%s\n' '===================================='
  _run_test_group 1 9 "CLI validation" test_cli
  _run_test_group 2 9 "Filesystem and configuration safety" test_filesystem_operations
  _run_test_group 3 9 "Terminal menu and task progress" test_terminal_menu_progress
  _run_test_group 4 9 "Probe parsing and mirror list criteria" test_probe_parser_and_list_criteria
  _run_test_group 5 9 "Catalog and Release metadata" test_catalog_and_release_metadata
  _run_test_group 6 9 "Mirror benchmark and read-only safety" test_benchmark_selection_and_read_only_safety
  _run_test_group 7 9 "Python package source manager" test_python_manager_safety
  _run_test_group 8 9 "Node.js registry manager" test_node_manager_safety
  _run_test_group 9 9 "Docker / OCI manager" test_docker_manager_safety
  printf '\nResults: %d passed, %d failed, %d total\n' "$_tests_passed" "$_tests_failed" "$_tests_run"
  [[ "$_tests_failed" -eq 0 ]]
}

main "$@"
