#!/usr/bin/env bash
#
# Power APT Boost — Fast Ubuntu APT mirror selector and network optimizer
#
# Author  : Matin Shahabadi
# GitHub  : https://github.com/power0matin/power-apt-boost
# License : MIT
# Version : 3.0.0
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/main/power-apt-boost.sh | sudo bash
#   sudo bash power-apt-boost.sh [OPTIONS]
#
# Run with --help for full usage information.

set -euo pipefail
IFS=$'\n\t'

# ─── Constants ────────────────────────────────────────────────────────────────

readonly APP_NAME="Power APT Boost"
readonly APP_VERSION="3.0.0"
readonly APP_SLUG="power-apt-boost"
readonly APP_AUTHOR="Matin Shahabadi"
readonly APP_GITHUB="https://github.com/power0matin/power-apt-boost"
readonly APP_LICENSE="MIT"

_TEST_MODE="${POWER_APT_BOOST_TEST_MODE:-0}"
if [[ "$_TEST_MODE" == "1" ]]; then
  _TEST_ROOT="${POWER_APT_BOOST_TEST_ROOT:-}"
  [[ "$_TEST_ROOT" == /* && "$_TEST_ROOT" != "/" ]] || {
    printf '%s\n' "POWER_APT_BOOST_TEST_ROOT must be a non-root absolute path." >&2
    exit 2
  }
  _SYSTEM_ROOT="${_TEST_ROOT%/}"
else
  _SYSTEM_ROOT=""
fi

readonly APT_ETC_DIR="${_SYSTEM_ROOT}/etc/apt"
readonly APT_SOURCES_DIR="${APT_ETC_DIR}/sources.list.d"
readonly APT_CONF_DIR="${APT_ETC_DIR}/apt.conf.d"
readonly APT_SOURCES_FILE="${APT_ETC_DIR}/sources.list"
readonly APT_DEB822_FILE="${APT_SOURCES_DIR}/ubuntu.sources"
readonly APT_CONF_FILE="${APT_CONF_DIR}/99-${APP_SLUG}"
readonly BACKUP_BASE="${_SYSTEM_ROOT}/var/backups/${APP_SLUG}"
readonly KEYRING_PATH="${_SYSTEM_ROOT}/usr/share/keyrings/ubuntu-archive-keyring.gpg"
readonly OS_RELEASE_FILE="${_SYSTEM_ROOT}/etc/os-release"
readonly APT_LOCK_FILE="${_SYSTEM_ROOT}/run/lock/${APP_SLUG}.lock"

readonly PROBE_TIMEOUT_CONNECT=5
readonly MAX_WORKERS=8

readonly EXIT_OK=0
readonly EXIT_GENERAL=1
readonly EXIT_USAGE=2
readonly EXIT_NETWORK=3
readonly EXIT_NOT_ROOT=4
readonly EXIT_NOT_UBUNTU=5
readonly EXIT_NO_MIRROR=6
readonly EXIT_BACKUP=7
readonly EXIT_RESTORE=8
readonly EXIT_CANCELLED=10

# ─── Global State ─────────────────────────────────────────────────────────────

# Detect script invocation name for restore command
set +u
_SCRIPT_NAME="${BASH_SOURCE[0]}"
set -u
if [[ "$_SCRIPT_NAME" == "bash" ]] || [[ "$_SCRIPT_NAME" == "/usr/bin/bash" ]]; then
  _SCRIPT_NAME="power-apt-boost.sh"
elif [[ "$_SCRIPT_NAME" == *"power-apt-boost"* ]]; then
  _SCRIPT_NAME="$(basename "$_SCRIPT_NAME")"
fi

CODENAME=""
SELECTED_MIRROR=""
SELECTED_TIME=""
DRY_RUN=false
SKIP_UPDATE=false
FORCE_MIRROR=""
# shellcheck disable=SC2034  # NO_SPINNER kept for --no-spinner backward compat
NO_SPINNER=false
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
RESTORE=false
RESTORE_PATH=""
TIMEOUT_TOTAL=20
COUNTRY_FILTER=""
USE_IPV6=false
LOG_FILE=""
LOG_ENABLED=false
YES=false
MENU_REQUESTED=false
STATUS_REQUESTED=false
DOCTOR_REQUESTED=false
LIST_REQUESTED=false
ACTION_REQUESTED=false

REPORT_COMMAND="apply"
REPORT_STATUS="success"
REPORT_OS_ID="unknown"
REPORT_OS_PRETTY="unknown"
REPORT_VERSION_ID="unknown"
REPORT_CODENAME="unknown"
REPORT_SOURCES_LIST="absent"
REPORT_DEB822="absent"
REPORT_MANAGED_CONFIG="absent"
REPORT_CURRENT_MIRROR=""
REPORT_BACKUP_ACCESSIBLE=false
REPORT_BACKUP_COUNT=0
REPORT_LATEST_BACKUP=""
REPORT_CHECK_NAMES=()
REPORT_CHECK_STATUSES=()
REPORT_CHECK_DETAILS=()

_tmp_dirs=()
_bg_pids=()

# ─── Color ────────────────────────────────────────────────────────────────────

_setup_colors() {
  if [[ -t 2 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    readonly COLOR_RED=$'\033[0;31m'
    readonly COLOR_GREEN=$'\033[0;32m'
    readonly COLOR_YELLOW=$'\033[0;33m'
    readonly COLOR_BLUE=$'\033[0;34m'
    readonly COLOR_MAGENTA=$'\033[0;35m'
    readonly COLOR_CYAN=$'\033[0;36m'
    readonly COLOR_WHITE=$'\033[0;37m'
    readonly COLOR_BOLD=$'\033[1m'
    readonly COLOR_DIM=$'\033[2m'
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_UL=$'\033[4m'
  else
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    # shellcheck disable=SC2034  # Available for user customization
    readonly COLOR_MAGENTA=''
    readonly COLOR_CYAN=''
    # shellcheck disable=SC2034  # Available for user customization
    readonly COLOR_WHITE=''
    readonly COLOR_BOLD=''
    readonly COLOR_DIM=''
    readonly COLOR_RESET=''
    # shellcheck disable=SC2034  # Available for user customization
    readonly COLOR_UL=''
  fi
}

# ─── Logging ──────────────────────────────────────────────────────────────────

_log_to_file() {
  if [[ "$LOG_ENABLED" == true ]] && [[ -n "$LOG_FILE" ]]; then
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

msg() {
  if [[ "$QUIET" == true ]]; then return; fi
  printf '%b\n' "$*" >&2
  _log_to_file "$*"
}

msg_color() {
  if [[ "$QUIET" == true ]]; then return; fi
  local color="$1" text="$2"
  printf '%b%b%b\n' "$color" "$text" "$COLOR_RESET" >&2
  _log_to_file "$text"
}

msg_verbose() {
  if [[ "$VERBOSE" == true ]]; then
    msg "$@"
  fi
}

info() { msg_color "$COLOR_GREEN" "[OK] $*"; }
warn() {
  msg_color "$COLOR_YELLOW" "[WARN] $*"
  _log_to_file "WARN: $*"
}
error() {
  msg_color "$COLOR_RED" "[ERROR] $*"
  _log_to_file "ERROR: $*"
}

die() {
  error "$1"
  exit "${2:-$EXIT_GENERAL}"
}

# ─── Spinners & Progress ─────────────────────────────────────────────────────

_spinner_pid=""

_start_spinner() {
  if [[ "$QUIET" == true || "$NO_SPINNER" == true ]]; then return; fi
  if ! [[ -t 2 ]]; then return; fi
  local msg="${1:-Working}"
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  (
    trap "exit 0" INT TERM
    local i=0
    while true; do
      printf "\r  ${COLOR_CYAN}%s${COLOR_RESET} %s" "${frames[$((i % ${#frames[@]}))]}" "$msg" >&2
      i=$((i + 1))
      sleep 0.1
    done
  ) &
  _spinner_pid=$!
}

_stop_spinner() {
  if [[ -n "$_spinner_pid" ]] && kill -0 "$_spinner_pid" 2>/dev/null; then
    kill "$_spinner_pid" 2>/dev/null || true
    wait "$_spinner_pid" 2>/dev/null || true
    _spinner_pid=""
    # shellcheck disable=SC2015  # Intentional: A && B || C pattern
    [[ -t 2 ]] && printf "\r\033[K" >&2 2>/dev/null || true
  fi
}

_print_progress_bar() {
  local current="$1" total="$2" width=40
  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  local bar=""
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done

  printf "\r  ${COLOR_DIM}[${COLOR_GREEN}%s${COLOR_DIM}]${COLOR_RESET} %3d%% (${current}/${total})" \
    "$bar" "$percent" >&2
}

_print_step() {
  local step_num="$1" total="$2" msg="$3"
  printf "\n  ${COLOR_BOLD}${COLOR_BLUE}[%d/%d]${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" \
    "$step_num" "$total" "$msg" >&2
}

_print_divider() {
  local char="${1:-─}" len="${2:-60}"
  printf '%*s\n' "$len" '' | tr ' ' "$char" >&2
}

_print_section_header() {
  local title="$1"
  echo "" >&2
  _print_divider "─" 60 >&2
  printf "  ${COLOR_BOLD}${COLOR_CYAN}%s${COLOR_RESET}\n" "$title" >&2
  _print_divider "─" 60 >&2
  echo "" >&2
}

# ─── Cleanup & Signals ────────────────────────────────────────────────────────

_cleanup() {
  local exit_code=$?

  # Stop spinner if running
  _stop_spinner

  # Kill all tracked background jobs
  local pid
  for pid in "${_bg_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  _bg_pids=()

  # Note: kill 0 is intentionally omitted — it would kill the script itself

  # Clean temp dirs
  local d
  for d in "${_tmp_dirs[@]}"; do
    if [[ -d "$d" ]]; then rm -rf "$d" 2>/dev/null || true; fi
  done
  _tmp_dirs=()

  if [[ -t 2 ]]; then printf "\r\033[K" >&2 2>/dev/null || true; fi

  if [[ "$LOG_ENABLED" == true ]] && [[ -n "$LOG_FILE" ]]; then
    _log_to_file "Session ended with exit code $exit_code"
  fi

  exit "$exit_code"
}

_handle_signal() {
  local signal_name="$1"
  local exit_code=130
  case "$signal_name" in
  INT) exit_code=130 ;;
  TERM) exit_code=143 ;;
  HUP) exit_code=129 ;;
  esac
  _stop_spinner
  msg ""
  msg_color "$COLOR_YELLOW" "  Interrupted by $signal_name. Cleaning up..."
  exit "$exit_code"
}

if [[ "${POWER_APT_BOOST_SOURCE_ONLY:-0}" != "1" ]]; then
  trap _cleanup EXIT
  trap '_handle_signal INT' INT
  trap '_handle_signal TERM' TERM
  trap '_handle_signal HUP' HUP
fi

# ─── Root Check ───────────────────────────────────────────────────────────────

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "" >&2
    printf '%b\n' "  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}This script must be run as root.${COLOR_RESET}\n" >&2
    printf '%b\n' "  ${COLOR_DIM}Fix:${COLOR_RESET} sudo bash ${_SCRIPT_NAME}\n" >&2
    exit "$EXIT_NOT_ROOT"
  fi

  local _hostname_output
  if _hostname_output=$(hostname 2>&1); then
    :
  elif [[ "$_hostname_output" == *"unable to resolve host"* ]]; then
    warn "Hostname resolution issue detected — this is a system config problem"
    warn "  (inconsistent hostname in /etc/hosts), not a Power APT Boost issue."
    warn "  The script will continue safely."
    warn "  Fix: add your hostname to /etc/hosts (e.g. '127.0.0.1 $(hostname 2>/dev/null || echo localhost)')"
  fi
}

# ─── Dependency Check ─────────────────────────────────────────────────────────

_check_commands() {
  local missing=() cmd
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}Missing required commands: ${COLOR_RESET}\n" >&2
    printf '%b\n' "  ${COLOR_DIM}Fix:${COLOR_RESET} These are standard Ubuntu utilities. Your system may be minimal.\n" >&2
    printf '%b\n' "  Try: ${COLOR_CYAN}apt-get install -y coreutils gawk grep${COLOR_RESET}\n" >&2
    exit "$EXIT_GENERAL"
  fi
}

_check_probe_tool() {
  command -v curl >/dev/null 2>&1 && return 0
  command -v wget >/dev/null 2>&1 && return 0
  printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}Neither curl nor wget found.${COLOR_RESET}\n" >&2
  printf '%b\n' "  ${COLOR_DIM}Fix:${COLOR_RESET} Install curl (recommended) or wget:\n" >&2
  printf '%b\n' "    ${COLOR_CYAN}apt-get install -y curl${COLOR_RESET}\n" >&2
  exit "$EXIT_GENERAL"
}

# ─── Ubuntu Detection ────────────────────────────────────────────────────────

detect_ubuntu() {
  [[ -f "$OS_RELEASE_FILE" ]] || {
    printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}$OS_RELEASE_FILE not found.${COLOR_RESET}\n" >&2
    printf '%b\n' "  ${COLOR_DIM}This script requires Ubuntu Linux.${COLOR_RESET}\n" >&2
    exit "$EXIT_NOT_UBUNTU"
  }

  # shellcheck disable=SC1090,SC1091
  source "$OS_RELEASE_FILE"

  [[ "${ID:-}" == "ubuntu" ]] || {
    printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}This script supports Ubuntu only.${COLOR_RESET}\n" >&2
    printf '%b\n' "  ${COLOR_DIM}Detected:${COLOR_RESET} ${PRETTY_NAME:-${ID:-unknown}} (${ID:-unknown})\n" >&2
    exit "$EXIT_NOT_UBUNTU"
  }
  [[ -n "${VERSION_CODENAME:-}" ]] || die "Could not detect Ubuntu version codename from $OS_RELEASE_FILE." "$EXIT_NOT_UBUNTU"

  CODENAME="$VERSION_CODENAME"
  msg_verbose "Detected Ubuntu ${VERSION_ID:-} (${CODENAME})"
}

# ─── Mirror List ──────────────────────────────────────────────────────────────

_MIRROR_CATALOG=(
  "ir|Iran|https://ir.archive.ubuntu.com/ubuntu"
  "ir|Iran|https://mirror.arvancloud.ir/ubuntu"
  "ir|Iran|https://mirror.iranserver.com/ubuntu"
  "ir|Iran|https://ubuntu.hostiran.ir/ubuntu"
  "ir|Iran|https://mirror.hostbaran.com/ubuntu"
  "ir|Iran|https://mirror.aminidc.com/ubuntu"
  "ir|Iran|https://archive.ito.gov.ir/ubuntu"
  "ir|Iran|https://archive.ubuntu.petiak.ir/ubuntu"
  "ir|Iran|https://mirror.mobinhost.com/ubuntu"
  "ir|Iran|https://linuxmirrors.ir/ubuntu"
  "ir|Iran|https://mirror.kubarcloud.com/ubuntu"
  "global|Global|https://archive.ubuntu.com/ubuntu"
  "global|Global|https://mirrors.kernel.org/ubuntu"
  "us|United States|https://us.archive.ubuntu.com/ubuntu"
  "us|United States|https://mirror.math.princeton.edu/pub/ubuntu"
  "us|United States|https://mirror.cs.uchicago.edu/ubuntu"
  "ca|Canada|https://mirror.csclub.uwaterloo.ca/ubuntu"
  "us|United States|https://mirror.rit.edu/ubuntu"
  "us|United States|https://mirror.arizona.edu/ubuntu"
  "gb|United Kingdom|https://uk.archive.ubuntu.com/ubuntu"
  "de|Germany|https://de.archive.ubuntu.com/ubuntu"
  "fr|France|https://fr.archive.ubuntu.com/ubuntu"
  "it|Italy|https://it.archive.ubuntu.com/ubuntu"
  "nl|Netherlands|https://nl.archive.ubuntu.com/ubuntu"
  "au|Australia|https://au.archive.ubuntu.com/ubuntu"
  "jp|Japan|https://jp.archive.ubuntu.com/ubuntu"
  "kr|South Korea|https://kr.archive.ubuntu.com/ubuntu"
  "in|India|https://in.archive.ubuntu.com/ubuntu"
  "br|Brazil|https://br.archive.ubuntu.com/ubuntu"
)

_get_mirrors() {
  local mirrors=()
  local entry country mirror_url
  local country_lower
  country_lower="$(printf '%s' "$COUNTRY_FILTER" | tr '[:upper:]' '[:lower:]')"

  if [[ -n "$country_lower" ]]; then
    local found_country=false
    for entry in "${_MIRROR_CATALOG[@]}"; do
      IFS='|' read -r country _ mirror_url <<<"$entry"
      if [[ "$country" == "$country_lower" ]]; then
        found_country=true
        mirrors+=("$mirror_url")
      fi
    done
    [[ "$found_country" == true ]] || die "Unsupported country code: $COUNTRY_FILTER" "$EXIT_USAGE"
  else
    for entry in "${_MIRROR_CATALOG[@]}"; do
      IFS='|' read -r country _ mirror_url <<<"$entry"
      mirrors+=("$mirror_url")
    done
  fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    mirrors=("$FORCE_MIRROR" "${mirrors[@]}")
  fi
  printf '%s\n' "${mirrors[@]}"
}

list_mirrors() {
  detect_ubuntu
  _print_section_header "AVAILABLE MIRRORS"
  local mirror_url result_file result_line rtime rstatus
  while IFS= read -r mirror_url; do
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.list.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$mirror_url" "$result_file" "$CODENAME"
    result_line="$(cat "$result_file" 2>/dev/null || true)"
    rm -f "$result_file" 2>/dev/null || true
    rtime="${result_line%% *}"
    rstatus="${result_line#* }"
    if [[ "$rstatus" == "pass" ]]; then
      printf '  %b%-8s%b %s (%ss)\n' "$COLOR_GREEN" "OK" "$COLOR_RESET" "$mirror_url" "$rtime" >&2
    else
      printf '  %b%-8s%b %s\n' "$COLOR_RED" "FAIL" "$COLOR_RESET" "$mirror_url" >&2
    fi
  done < <(_get_mirrors)
}

# ─── HTTP Probing ─────────────────────────────────────────────────────────────

_classify_curl_error() {
  local content
  content="$(cat "$1" 2>/dev/null || true)"
  case "$content" in
  *"Could not resolve host"* | *"resolve"*) echo "DNS resolution failed" ;;
  *"Connection refused"*) echo "Connection refused" ;;
  *"Connection timed out"* | *"timed out"*) echo "Connection timed out" ;;
  *"SSL"* | *"TLS"* | *"certificate"*) echo "TLS handshake failed" ;;
  *"Network is unreachable"*) echo "Network unreachable" ;;
  *"No route to host"*) echo "No route to host" ;;
  *"Empty reply from server"*) echo "Empty reply from server" ;;
  *) echo "Connection failed" ;;
  esac
}

_classify_wget_error() {
  local output="$1"
  case "$output" in
  *"Failed to resolve"* | *"Unknown host"*) echo "DNS resolution failed" ;;
  *"Connection refused"*) echo "Connection refused" ;;
  *"timed out"* | *"timed-out"*) echo "Connection timed out" ;;
  *"SSL"* | *"certificate"*) echo "TLS handshake failed" ;;
  *"Network is unreachable"*) echo "Network unreachable" ;;
  *) echo "Connection failed" ;;
  esac
}

# Writes tab-separated HTTP status, elapsed seconds and failure reason.
_probe_url_code() {
  local url="$1"
  local ip_flag="-4"
  local reason=""
  local http_code="000"
  local elapsed="0.000000"
  local connect_timeout="$PROBE_TIMEOUT_CONNECT"

  [[ "$USE_IPV6" == true ]] && ip_flag="-6"
  ((TIMEOUT_TOTAL < connect_timeout)) && connect_timeout="$TIMEOUT_TOTAL"

  if command -v curl >/dev/null 2>&1; then
    local curl_stderr curl_output
    curl_stderr="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.curlerr.XXXXXX")"
    curl_output="$(curl "$ip_flag" -L -sS \
      --connect-timeout "$connect_timeout" \
      --max-time "$TIMEOUT_TOTAL" \
      -o /dev/null -w '%{http_code}\t%{time_total}' "$url" 2>"$curl_stderr")" || true

    if [[ "$curl_output" == *$'\t'* ]]; then
      http_code="${curl_output%%$'\t'*}"
      elapsed="${curl_output#*$'\t'}"
    elif [[ -n "$curl_output" ]]; then
      http_code="$curl_output"
    fi
    if [[ "$http_code" == "000" || -z "$http_code" ]]; then
      reason="$(_classify_curl_error "$curl_stderr")"
      http_code="000"
    fi
    rm -f "$curl_stderr" 2>/dev/null || true
    printf '%s\t%s\t%s\n' "$http_code" "$elapsed" "$reason"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    local wget_output start end
    start="$(date +%s.%N)"
    wget_output="$(wget "$ip_flag" --server-response --spider \
      --timeout="$TIMEOUT_TOTAL" --tries=1 -q "$url" 2>&1)" || true
    end="$(date +%s.%N)"
    elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.6f", e-s }')"
    http_code="$(printf '%s\n' "$wget_output" | awk '/HTTP\// {code=$2} END {print code+0}')"
    [[ "$http_code" != "0" ]] || http_code="000"
    if [[ "$http_code" == "000" ]]; then
      reason="$(_classify_wget_error "$wget_output")"
    fi
    printf '%s\t%s\t%s\n' "$http_code" "$elapsed" "$reason"
    return 0
  fi

  printf '000\t%s\t%s\n' "$elapsed" "no_http_client"
}

_test_mirror() {
  local base_url="${1%/}"
  local result_file="$2"
  local codename="$3"
  local main_url="${base_url}/dists/${codename}/InRelease"
  local updates_url="${base_url}/dists/${codename}-updates/InRelease"
  local security_url="${base_url}/dists/${codename}-security/InRelease"
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/${APP_SLUG}.mirror.XXXXXX")"
  _tmp_dirs+=("$tmpdir")

  local start end elapsed
  start="$(date +%s.%N)"
  _probe_url_code "$main_url" >"$tmpdir/main" 2>"$tmpdir/main.err" &
  local pid_main=$!
  _probe_url_code "$updates_url" >"$tmpdir/updates" 2>"$tmpdir/updates.err" &
  local pid_updates=$!
  _probe_url_code "$security_url" >"$tmpdir/security" 2>"$tmpdir/security.err" &
  local pid_security=$!

  wait "$pid_main" 2>/dev/null || true
  wait "$pid_updates" 2>/dev/null || true
  wait "$pid_security" 2>/dev/null || true
  end="$(date +%s.%N)"
  elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.6f", e-s }')"

  local main_code main_time main_reason
  local updates_code updates_time updates_reason
  local security_code security_time security_reason
  IFS=$'\t' read -r main_code main_time main_reason <"$tmpdir/main" || true
  IFS=$'\t' read -r updates_code updates_time updates_reason <"$tmpdir/updates" || true
  IFS=$'\t' read -r security_code security_time security_reason <"$tmpdir/security" || true
  main_code="${main_code:-000}"
  main_time="${main_time:-0.000000}"
  updates_code="${updates_code:-000}"
  updates_time="${updates_time:-0.000000}"
  security_code="${security_code:-000}"
  security_time="${security_time:-0.000000}"
  rm -rf "$tmpdir" 2>/dev/null || true

  msg_color "$COLOR_BOLD" "  ┌─ $base_url"
  local fail_msg icon
  if [[ "$main_code" == "200" ]]; then
    icon="${COLOR_GREEN}✓${COLOR_RESET}"
    printf '  │  %b main:     HTTP %s in %ss\n' "$icon" "$main_code" "$main_time" >&2
  else
    fail_msg="main: HTTP $main_code in ${main_time}s"
    [[ -n "$main_reason" ]] && fail_msg+=" — $main_reason"
    printf '  │  %b %s\n' "${COLOR_RED}✗${COLOR_RESET}" "$fail_msg" >&2
  fi
  if [[ "$updates_code" == "200" ]]; then
    icon="${COLOR_GREEN}✓${COLOR_RESET}"
    printf '  │  %b updates:  HTTP %s in %ss\n' "$icon" "$updates_code" "$updates_time" >&2
  else
    fail_msg="updates: HTTP $updates_code in ${updates_time}s"
    [[ -n "$updates_reason" ]] && fail_msg+=" — $updates_reason"
    printf '  │  %b %s\n' "${COLOR_RED}✗${COLOR_RESET}" "$fail_msg" >&2
  fi
  if [[ "$security_code" == "200" ]]; then
    icon="${COLOR_GREEN}✓${COLOR_RESET}"
    printf '  │  %b security: HTTP %s in %ss\n' "$icon" "$security_code" "$security_time" >&2
  else
    fail_msg="security: HTTP $security_code in ${security_time}s"
    [[ -n "$security_reason" ]] && fail_msg+=" — $security_reason"
    printf '  │  %b %s\n' "${COLOR_RED}✗${COLOR_RESET}" "$fail_msg" >&2
  fi
  if [[ "$main_code" == "200" && "$updates_code" == "200" && "$security_code" == "200" ]]; then
    printf '  └─ %b PASS%b total: %ss\n' "$COLOR_GREEN" "$COLOR_RESET" "$elapsed" >&2
    printf '%s pass\n' "$elapsed" >"$result_file"
  else
    printf '  └─ %b FAIL%b total: %ss\n' "$COLOR_RED" "$COLOR_RESET" "$elapsed" >&2
    printf '%s fail\n' "$elapsed" >"$result_file"
  fi
}

# ─── Parallel Benchmark ──────────────────────────────────────────────────────

_select_mirror() {
  local mirror_list total_mirrors bench_start bench_end bench_duration

  _print_section_header "MIRROR SELECTION"

  msg "  Ubuntu codename:  ${COLOR_BOLD}${CODENAME}${COLOR_RESET}"
  echo ""

  mirror_list=$(_get_mirrors)
  total_mirrors=$(echo "$mirror_list" | wc -l)

  msg "  Mirrors to test:  ${COLOR_BOLD}${total_mirrors}${COLOR_RESET}"
  msg "  Parallel workers: ${COLOR_BOLD}${MAX_WORKERS}${COLOR_RESET}"
  echo ""

  bench_start=$(date +%s)

  # ── Create temp dir for result files ─────────────────────────
  local bench_tmpdir
  bench_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${APP_SLUG}.bench.XXXXXX")

  # ── Read mirror list into array for indexed access ───────────
  local -a mirrors
  mapfile -t mirrors <<<"$mirror_list"
  local total=${#mirrors[@]}

  _start_spinner "Testing mirrors..."

  # ── Worker: test one mirror, write result to file ────────────
  _bench_worker() {
    local idx="$1" url="$2" codename="$3" result_file="$4"
    _test_mirror "$url" "$result_file" "$codename"
  }

  # ── Dispatch mirrors to worker pool ──────────────────────────
  local idx=0
  while ((idx < total)); do
    # Fill up to MAX_WORKERS slots
    while ((${#_bg_pids[@]} < MAX_WORKERS)) && ((idx < total)); do
      _bench_worker "$idx" "${mirrors[$idx]}" "$CODENAME" \
        "${bench_tmpdir}/${idx}.result" &
      _bg_pids+=($!)
      ((idx++)) || true
    done

    # Wait for at least one worker to finish
    local new_pids=()
    local pid
    for pid in "${_bg_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      else
        wait "$pid" 2>/dev/null || true
      fi
    done
    _bg_pids=("${new_pids[@]+"${new_pids[@]}"}")
  done

  # ── Wait for remaining workers ───────────────────────────────
  for pid in "${_bg_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  _bg_pids=()

  bench_end=$(date +%s)
  bench_duration=$((bench_end - bench_start))

  _stop_spinner

  # ── Collect results and find best ────────────────────────────
  local best="" best_time="999999" tested=0 passed=0 failed=0
  local i result_line rtime rstatus
  for ((i = 0; i < total; i++)); do
    result_line=$(cat "${bench_tmpdir}/${i}.result" 2>/dev/null) || continue
    ((tested++)) || true
    rtime="${result_line%% *}"
    rstatus="${result_line#* }"
    if [[ "$rstatus" == "pass" ]]; then
      ((passed++)) || true
      if awk "BEGIN {exit !($rtime < $best_time)}"; then
        best="${mirrors[$i]}"
        best_time="$rtime"
      fi
    else
      ((failed++)) || true
    fi
  done

  rm -rf "$bench_tmpdir" 2>/dev/null || true

  # ── Print summary (matches original format exactly) ──────────
  _print_section_header "RESULTS"

  printf "  ${COLOR_DIM}%-24s${COLOR_RESET} ${COLOR_BOLD}%d${COLOR_RESET}\n" "Mirrors tested:" "$tested"
  printf "  ${COLOR_DIM}%-24s${COLOR_RESET} ${COLOR_GREEN}%d${COLOR_RESET}\n" "Successful:" "$passed"
  printf "  ${COLOR_DIM}%-24s${COLOR_RESET} ${COLOR_RED}%d${COLOR_RESET}\n" "Failed:" "$failed"
  printf "  ${COLOR_DIM}%-24s${COLOR_RESET} ${COLOR_BOLD}%ds${COLOR_RESET}\n" "Total duration:" "$bench_duration"
  echo ""

  if [[ -n "$best" ]]; then
    printf "  ${COLOR_GREEN}▸ Fastest mirror:${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$best"
    printf "  ${COLOR_GREEN}▸ Response time:${COLOR_RESET}  ${COLOR_BOLD}%ss${COLOR_RESET} (total probe time)\n" "$best_time"
  fi
  echo ""

  if [[ -z "$best" ]]; then
    printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}No working mirror found.${COLOR_RESET}\n" >&2
    printf '%b\n' "  ${COLOR_DIM}Possible causes:${COLOR_RESET}\n" >&2
    printf '%b\n' "    - Firewall blocking Ubuntu repository access\n" >&2
    printf '%b\n' "    - DNS resolution failure\n" >&2
    printf '%b\n' "    - Network connectivity issue\n" >&2
    printf '%b\n' "  ${COLOR_DIM}Fix:${COLOR_RESET} Check your network connection and try again.\n" >&2
    printf '%b\n' "  Or specify a mirror directly: ${COLOR_CYAN}sudo bash ${_SCRIPT_NAME} --mirror URL${COLOR_RESET}\n" >&2
    exit "$EXIT_NO_MIRROR"
  fi

  SELECTED_MIRROR="$best"
  SELECTED_TIME="$best_time"
}

# ─── Backup ───────────────────────────────────────────────────────────────────

_create_backup() {
  local backup_dir old_umask tar_root
  old_umask="$(umask)"
  umask 077

  if ! mkdir -p "$BACKUP_BASE" || ! chmod 0700 "$BACKUP_BASE"; then
    umask "$old_umask"
    error "Cannot create or secure backup directory: $BACKUP_BASE"
    return "$EXIT_BACKUP"
  fi
  backup_dir="$(mktemp -d "$BACKUP_BASE/$(date '+%Y-%m-%d_%H-%M-%S').XXXXXX")" || {
    umask "$old_umask"
    error "Cannot create a unique backup snapshot directory."
    return "$EXIT_BACKUP"
  }

  local sources_list_state=absent sources_dir_state=absent conf_dir_state=absent
  local -a archive_paths=()
  if [[ -e "$APT_SOURCES_FILE" || -L "$APT_SOURCES_FILE" ]]; then
    sources_list_state=present
    archive_paths+=("etc/apt/sources.list")
  fi
  if [[ -e "$APT_SOURCES_DIR" || -L "$APT_SOURCES_DIR" ]]; then
    sources_dir_state=present
    archive_paths+=("etc/apt/sources.list.d")
  fi
  if [[ -e "$APT_CONF_DIR" || -L "$APT_CONF_DIR" ]]; then
    conf_dir_state=present
    archive_paths+=("etc/apt/apt.conf.d")
  fi

  tar_root="${_SYSTEM_ROOT:-/}"
  if (("${#archive_paths[@]}" > 0)); then
    if ! tar -cpf "$backup_dir/apt-config.tar" -C "$tar_root" "${archive_paths[@]}"; then
      rm -rf "$backup_dir"
      umask "$old_umask"
      error "Failed to archive the existing APT configuration."
      return "$EXIT_BACKUP"
    fi
  elif ! tar -cpf "$backup_dir/apt-config.tar" --files-from /dev/null; then
    rm -rf "$backup_dir"
    umask "$old_umask"
    error "Failed to create an empty APT snapshot."
    return "$EXIT_BACKUP"
  fi

  if ! (cd "$backup_dir" && sha256sum apt-config.tar >archive.sha256); then
    rm -rf "$backup_dir"
    umask "$old_umask"
    error "Failed to checksum the APT snapshot."
    return "$EXIT_BACKUP"
  fi
  {
    printf 'format=1\n'
    printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'sources_list=%s\n' "$sources_list_state"
    printf 'sources_list.d=%s\n' "$sources_dir_state"
    printf 'apt.conf.d=%s\n' "$conf_dir_state"
  } >"$backup_dir/manifest"

  if ! chmod 0600 "$backup_dir/apt-config.tar" "$backup_dir/archive.sha256" "$backup_dir/manifest"; then
    rm -rf "$backup_dir"
    umask "$old_umask"
    error "Failed to secure backup files."
    return "$EXIT_BACKUP"
  fi
  umask "$old_umask"
  info "Validated backup created: $backup_dir"
  printf '%s\n' "$backup_dir"
}

_atomic_write() {
  local target="$1" mode="${2:-0644}" parent tmp
  parent="$(dirname -- "$target")"
  mkdir -p "$parent" || {
    error "Cannot create directory: $parent"
    return 1
  }
  tmp="$(mktemp "$target.tmp.XXXXXX")" || {
    error "Cannot create temporary file for $target"
    return 1
  }
  if ! cat >"$tmp"; then
    rm -f "$tmp"
    error "Cannot write temporary file for $target"
    return 1
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    if ! chown --reference="$target" "$tmp" || ! chmod --reference="$target" "$tmp"; then
      rm -f "$tmp"
      error "Cannot preserve file ownership and mode for $target"
      return 1
    fi
  elif ! chmod "$mode" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv -f -- "$tmp" "$target"; then
    rm -f "$tmp"
    error "Atomic replacement failed for $target"
    return 1
  fi
}

_write_apt_sources() {
  local mirror_url="$1"
  if [[ ! -f "$KEYRING_PATH" ]]; then
    warn "Keyring not found at $KEYRING_PATH; APT signature validation may fail."
  fi

  local has_third_party=false
  if [[ -f "$APT_SOURCES_FILE" ]]; then
    if grep -v '^\s*$' "$APT_SOURCES_FILE" 2>/dev/null |
      grep -v '^\s*#' |
      grep -v 'archive.ubuntu.com' |
      grep -v 'security.ubuntu.com' |
      grep -q . 2>/dev/null; then
      has_third_party=true
    fi
  fi

  if ! _atomic_write "$APT_DEB822_FILE" 0644 <<SOURCES; then
# Power APT Boost — Ubuntu mirror configuration
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Mirror: $mirror_url

Types: deb
URIs: $mirror_url
Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security
Components: main restricted universe multiverse
Signed-By: $KEYRING_PATH
SOURCES
    return 1
  fi

  if [[ -f "$APT_SOURCES_FILE" ]]; then
    if [[ "$has_third_party" == true ]]; then
      warn "Third-party repositories detected in sources.list; preserving the file."
    elif ! rm -f -- "$APT_SOURCES_FILE"; then
      error "Could not remove legacy Ubuntu-only sources.list."
      return 1
    fi
  fi
}

_write_apt_config() {
  local force_ip_config
  if [[ "$USE_IPV6" == true ]]; then
    force_ip_config='Acquire::ForceIPv6 "true";'
  else
    force_ip_config='Acquire::ForceIPv4 "true";'
  fi
  _atomic_write "$APT_CONF_FILE" 0644 <<APTCONF
# Power APT Boost — APT network optimization
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

$force_ip_config
Acquire::Retries "3";
Acquire::http::Timeout "$TIMEOUT_TOTAL";
Acquire::https::Timeout "$TIMEOUT_TOTAL";
Acquire::Languages "none";
APTCONF
}

_apt_target_path() {
  case "$1" in
  sources.list) printf '%s\n' "$APT_SOURCES_FILE" ;;
  sources.list.d) printf '%s\n' "$APT_SOURCES_DIR" ;;
  apt.conf.d) printf '%s\n' "$APT_CONF_DIR" ;;
  *) return 1 ;;
  esac
}

_restore_legacy_backup() {
  local backup_path="$1"
  warn "Restoring a legacy backup. Its original file-existence state cannot be verified."
  mkdir -p "$APT_ETC_DIR" "$APT_SOURCES_DIR" "$APT_CONF_DIR" || return "$EXIT_RESTORE"
  [[ ! -f "$backup_path/ubuntu.sources" ]] || cp -a "$backup_path/ubuntu.sources" "$APT_DEB822_FILE" || return "$EXIT_RESTORE"
  [[ ! -d "$backup_path/sources.list.d" ]] || cp -a "$backup_path/sources.list.d/." "$APT_SOURCES_DIR/" || return "$EXIT_RESTORE"
  [[ ! -f "$backup_path/sources.list" ]] || cp -a "$backup_path/sources.list" "$APT_SOURCES_FILE" || return "$EXIT_RESTORE"
  [[ ! -d "$backup_path/apt.conf.d" ]] || cp -a "$backup_path/apt.conf.d/." "$APT_CONF_DIR/" || return "$EXIT_RESTORE"
}

_restore_backup() {
  local backup_path="$1"
  if [[ -z "$backup_path" && -d "$BACKUP_BASE" ]]; then
    backup_path="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    local legacy_root="${_SYSTEM_ROOT}/root"
    if [[ -d "$legacy_root" ]]; then
      backup_path="$(find "$legacy_root" -maxdepth 1 -name 'apt-backup-*' -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
    fi
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    error "No backup found to restore."
    return "$EXIT_RESTORE"
  fi

  _print_section_header "RESTORING BACKUP"
  printf '  Source: %s\n' "$backup_path"
  if [[ ! -f "$backup_path/manifest" ]]; then
    _restore_legacy_backup "$backup_path"
    return $?
  fi
  [[ -f "$backup_path/apt-config.tar" && -f "$backup_path/archive.sha256" ]] || {
    error "Backup snapshot is incomplete."
    return "$EXIT_RESTORE"
  }
  if ! (cd "$backup_path" && sha256sum -c archive.sha256 >/dev/null); then
    error "Backup checksum validation failed."
    return "$EXIT_RESTORE"
  fi

  local format="" sources_list_state="" sources_dir_state="" conf_dir_state key value
  while IFS='=' read -r key value; do
    case "$key" in
    format) format="$value" ;;
    created_at) ;;
    sources_list) sources_list_state="$value" ;;
    sources_list.d) sources_dir_state="$value" ;;
    apt.conf.d) conf_dir_state="$value" ;;
    *)
      error "Unknown manifest key: $key"
      return "$EXIT_RESTORE"
      ;;
    esac
  done <"$backup_path/manifest"

  [[ "$format" == "1" ]] || {
    error "Unsupported backup manifest version."
    return "$EXIT_RESTORE"
  }
  [[ "$sources_list_state" == present || "$sources_list_state" == absent ]] || return "$EXIT_RESTORE"
  [[ "$sources_dir_state" == present || "$sources_dir_state" == absent ]] || return "$EXIT_RESTORE"
  [[ "$conf_dir_state" == present || "$conf_dir_state" == absent ]] || return "$EXIT_RESTORE"

  local tar_entries tar_entry
  tar_entries="$(tar -tf "$backup_path/apt-config.tar")" || {
    error "Could not inspect backup archive."
    return "$EXIT_RESTORE"
  }
  if [[ -n "$tar_entries" ]]; then
    while IFS= read -r tar_entry; do
      case "$tar_entry" in
      etc | etc/ | etc/apt | etc/apt/ | etc/apt/sources.list | etc/apt/sources.list.d | etc/apt/sources.list.d/* | etc/apt/apt.conf.d | etc/apt/apt.conf.d/*) ;;
      *)
        error "Unsafe path in snapshot archive: $tar_entry"
        return "$EXIT_RESTORE"
        ;;
      esac
      [[ "$tar_entry" != *"/../"* && "$tar_entry" != ../* && "$tar_entry" != */.. ]] || return "$EXIT_RESTORE"
    done <<<"$tar_entries"
  fi

  mkdir -p "$APT_ETC_DIR" || return "$EXIT_RESTORE"
  local stage_dir extracted_root previous_root archive_root
  stage_dir="$(mktemp -d "$APT_ETC_DIR/.power-apt-boost-restore.XXXXXX")" || return "$EXIT_RESTORE"
  extracted_root="$stage_dir/extracted"
  previous_root="$stage_dir/previous"
  mkdir -p "$extracted_root" "$previous_root" || {
    rm -rf "$stage_dir"
    return "$EXIT_RESTORE"
  }
  if ! tar -xpf "$backup_path/apt-config.tar" -C "$extracted_root"; then
    rm -rf "$stage_dir"
    error "Could not extract the snapshot archive."
    return "$EXIT_RESTORE"
  fi
  archive_root="$extracted_root/etc/apt"

  [[ "$sources_list_state" != present || -e "$archive_root/sources.list" || -L "$archive_root/sources.list" ]] || {
    rm -rf "$stage_dir"
    return "$EXIT_RESTORE"
  }
  [[ "$sources_dir_state" != present || -e "$archive_root/sources.list.d" || -L "$archive_root/sources.list.d" ]] || {
    rm -rf "$stage_dir"
    return "$EXIT_RESTORE"
  }
  [[ "$conf_dir_state" != present || -e "$archive_root/apt.conf.d" || -L "$archive_root/apt.conf.d" ]] || {
    rm -rf "$stage_dir"
    return "$EXIT_RESTORE"
  }

  local -a target_names=(sources.list sources.list.d apt.conf.d)
  local -a moved_targets=()
  local dest
  for key in "${target_names[@]}"; do
    dest="$(_apt_target_path "$key")"
    if [[ -e "$dest" || -L "$dest" ]]; then
      if ! mv -- "$dest" "$previous_root/$key"; then
        local stage_restore_failed=false
        for value in "${moved_targets[@]}"; do
          if ! mv -- "$previous_root/$value" "$(_apt_target_path "$value")"; then stage_restore_failed=true; fi
        done
        [[ "$stage_restore_failed" == false ]] && rm -rf "$stage_dir"
        error "Could not stage the current APT configuration."
        [[ "$stage_restore_failed" == true ]] && error "Recovery data remains in $stage_dir"
        return "$EXIT_RESTORE"
      fi
      moved_targets+=("$key")
    fi
  done

  local install_failed=false
  for key in "${target_names[@]}"; do
    case "$key" in
    sources.list) value="$sources_list_state" ;;
    sources.list.d) value="$sources_dir_state" ;;
    apt.conf.d) value="$conf_dir_state" ;;
    esac
    if [[ "$value" == present ]]; then
      if ! mv -- "$archive_root/$key" "$(_apt_target_path "$key")"; then
        install_failed=true
        break
      fi
    fi
  done

  if [[ "$install_failed" == true ]]; then
    local rollback_failed=false
    for key in "${target_names[@]}"; do
      dest="$(_apt_target_path "$key")"
      if [[ -e "$dest" || -L "$dest" ]]; then rm -rf -- "$dest" || rollback_failed=true; fi
    done
    for key in "${moved_targets[@]}"; do
      dest="$(_apt_target_path "$key")"
      mv -- "$previous_root/$key" "$dest" || rollback_failed=true
    done
    error "Snapshot installation failed."
    if [[ "$rollback_failed" == true ]]; then
      error "Rollback also failed. Preserve recovery data at: $stage_dir"
      return "$EXIT_RESTORE"
    fi
    rm -rf "$stage_dir"
    return "$EXIT_RESTORE"
  fi

  rm -rf "$stage_dir" || warn "Restore succeeded; temporary recovery data remains at $stage_dir"
  info "APT configuration restored from validated snapshot."
}

_acquire_mutation_lock() {
  command -v flock >/dev/null 2>&1 || die "flock is required for safe APT mutations." "$EXIT_GENERAL"
  mkdir -p "$(dirname "$APT_LOCK_FILE")" || die "Cannot create APT lock directory." "$EXIT_GENERAL"
  local old_umask
  old_umask="$(umask)"
  umask 077
  exec 9>"$APT_LOCK_FILE" || die "Cannot open APT mutation lock." "$EXIT_GENERAL"
  umask "$old_umask"
  flock -n 9 || die "Another Power APT Boost operation is already modifying APT." "$EXIT_GENERAL"
  chmod 0600 "$APT_LOCK_FILE" 2>/dev/null || true
}

# ─── Apply Changes ───────────────────────────────────────────────────────────

_apply_changes() {
  _print_section_header "APPLYING CHANGES"
  printf '  Mirror: %s\n' "$SELECTED_MIRROR"
  printf '  Probe time: %ss\n\n' "$SELECTED_TIME"

  if [[ "$DRY_RUN" == true ]]; then
    cat <<DRYRUN
  ${COLOR_YELLOW}${COLOR_BOLD}DRY RUN MODE${COLOR_RESET} — no APT configuration changes applied

  Files that would be written:
    ${APT_DEB822_FILE}
    ${APT_CONF_FILE}

  Selected mirror:
    ${SELECTED_MIRROR}
DRYRUN
    return 0
  fi

  _print_step 1 3 "Creating and validating backup"
  local backup_dir
  if ! backup_dir="$(_create_backup)"; then
    die "Could not create a validated backup. No APT changes were applied." "$EXIT_BACKUP"
  fi

  _print_step 2 3 "Writing APT configuration atomically"
  if ! _write_apt_sources "$SELECTED_MIRROR" || ! _write_apt_config; then
    warn "APT configuration write failed. Restoring the validated snapshot."
    if ! _restore_backup "$backup_dir"; then
      die "Configuration write failed and rollback failed. Recovery snapshot: $backup_dir" "$EXIT_RESTORE"
    fi
    die "Configuration write failed. The original APT configuration was restored." "$EXIT_GENERAL"
  fi

  if [[ "$SKIP_UPDATE" == true ]]; then
    msg_color "$COLOR_YELLOW" "  Skipped apt-get update. Existing package lists and archive cache were left untouched."
    return 0
  fi

  _print_step 3 3 "Running apt-get update"
  if apt-get update; then
    info "APT update completed successfully"
  else
    warn "apt-get update failed. Restoring previous APT configuration."
    if ! _restore_backup "$backup_dir"; then
      die "apt-get update failed and rollback failed. Recovery snapshot: $backup_dir" "$EXIT_RESTORE"
    fi
    die "apt-get update failed. Previous APT configuration restored; run apt-get update after resolving connectivity." "$EXIT_NETWORK"
  fi
}

# ─── Output ──────────────────────────────────────────────────────────────────# ─── Output ───────────────────────────────────────────────────────────────────

_json_quote() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//
}

_collect_status() {
  REPORT_OS_ID="unknown"
  REPORT_OS_PRETTY="unknown"
  REPORT_VERSION_ID="unknown"
  REPORT_CODENAME="unknown"
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$OS_RELEASE_FILE"
    REPORT_OS_ID="${ID:-unknown}"
    REPORT_OS_PRETTY="${PRETTY_NAME:-${ID:-unknown}}"
    REPORT_VERSION_ID="${VERSION_ID:-unknown}"
    REPORT_CODENAME="${VERSION_CODENAME:-unknown}"
  fi
  REPORT_SOURCES_LIST="absent"
  REPORT_DEB822="absent"
  REPORT_MANAGED_CONFIG="absent"
  [[ ! -e "$APT_SOURCES_FILE" ]] || REPORT_SOURCES_LIST="present"
  [[ ! -e "$APT_DEB822_FILE" ]] || REPORT_DEB822="present"
  [[ ! -e "$APT_CONF_FILE" ]] || REPORT_MANAGED_CONFIG="present"

  REPORT_CURRENT_MIRROR=""
  if [[ -r "$APT_DEB822_FILE" ]]; then
    REPORT_CURRENT_MIRROR="$(awk -F': ' '$1 == "URIs" {print $2; exit}' "$APT_DEB822_FILE" 2>/dev/null || true)"
    REPORT_CURRENT_MIRROR="$(printf '%s' "$REPORT_CURRENT_MIRROR" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g')"
  fi
  REPORT_BACKUP_ACCESSIBLE=false
  REPORT_BACKUP_COUNT=0
  REPORT_LATEST_BACKUP=""
  if [[ -d "$BACKUP_BASE" && -r "$BACKUP_BASE" ]]; then
    REPORT_BACKUP_ACCESSIBLE=true
    REPORT_BACKUP_COUNT="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]')"
    REPORT_LATEST_BACKUP="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
}

_print_status_report() {
  _collect_status
  printf '\n%s\n' "$APP_NAME — System Status"
  printf '%-24s %s\n' "Operating system:" "$REPORT_OS_PRETTY"
  printf '%-24s %s\n' "Ubuntu codename:" "$REPORT_CODENAME"
  printf '%-24s %s\n' "Legacy sources.list:" "$REPORT_SOURCES_LIST"
  printf '%-24s %s\n' "Deb822 ubuntu.sources:" "$REPORT_DEB822"
  printf '%-24s %s\n' "Managed APT config:" "$REPORT_MANAGED_CONFIG"
  printf '%-24s %s\n' "Current mirror:" "${REPORT_CURRENT_MIRROR:-not detected}"
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    printf '%-24s %s\n' "Available backups:" "$REPORT_BACKUP_COUNT"
    printf '%-24s %s\n' "Latest backup:" "${REPORT_LATEST_BACKUP:-none}"
  else
    printf '%-24s %s\n' "Backup directory:" "not accessible (root may be required)"
  fi
  printf '\n'
}

_doctor_add_check() {
  REPORT_CHECK_NAMES+=("$1")
  REPORT_CHECK_STATUSES+=("$2")
  REPORT_CHECK_DETAILS+=("$3")
  case "$2" in
    error) REPORT_STATUS="error" ;;
    warning)
      [[ "$REPORT_STATUS" == "error" ]] || REPORT_STATUS="warning"
      ;;
  esac
}

_doctor_collect() {
  _collect_status
  REPORT_CHECK_NAMES=()
  REPORT_CHECK_STATUSES=()
  REPORT_CHECK_DETAILS=()
  REPORT_STATUS="ok"
  if [[ "$REPORT_OS_ID" == "ubuntu" ]]; then
    _doctor_add_check "operating_system" "ok" "$REPORT_OS_PRETTY"
  else
    _doctor_add_check "operating_system" "error" "Ubuntu is required; detected $REPORT_OS_PRETTY"
  fi
  local cmd
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat find sort head cut chown mv rm sed; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _doctor_add_check "command:$cmd" "ok" "available"
    else
      _doctor_add_check "command:$cmd" "error" "missing required command"
    fi
  done
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    _doctor_add_check "http_client" "ok" "curl or wget is available"
  else
    _doctor_add_check "http_client" "error" "curl or wget is required"
  fi
  if [[ -f "$KEYRING_PATH" ]]; then
    _doctor_add_check "ubuntu_archive_keyring" "ok" "keyring exists"
  else
    _doctor_add_check "ubuntu_archive_keyring" "warning" "keyring not found at $KEYRING_PATH"
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    _doctor_add_check "privileges" "ok" "running as root"
  else
    _doctor_add_check "privileges" "warning" "root is required for apply and restore operations"
  fi
  if [[ -r "$APT_ETC_DIR" ]]; then
    _doctor_add_check "apt_configuration" "ok" "APT configuration directory is readable"
  else
    _doctor_add_check "apt_configuration" "warning" "APT configuration directory is not readable"
  fi
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    _doctor_add_check "backup_directory" "ok" "$REPORT_BACKUP_COUNT backup snapshot(s) visible"
  else
    _doctor_add_check "backup_directory" "warning" "backup directory is not currently accessible or has not been created"
  fi
}

_report_checks_json() {
  local i
  printf '['
  for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
    if ((i > 0)); then printf ','; fi
    printf '{"name":%s,"status":%s,"detail":%s}' "$(_json_quote "${REPORT_CHECK_NAMES[$i]}")" "$(_json_quote "${REPORT_CHECK_STATUSES[$i]}")" "$(_json_quote "${REPORT_CHECK_DETAILS[$i]}")"
  done
  printf ']'
}

_print_json() {
  _collect_status
  local checks_json
  checks_json="$(_report_checks_json)"
  printf '{\\n'
  printf '  "schema_version": 1,\\n'
  printf '  "version": %s,\\n' "$(_json_quote "$APP_VERSION")"
  printf '  "command": %s,\\n' "$(_json_quote "$REPORT_COMMAND")"
  printf '  "status": %s,\\n' "$(_json_quote "$REPORT_STATUS")"
  printf '  "timestamp": %s,\\n' "$(_json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "system": {"id": %s, "pretty_name": %s, "version_id": %s, "codename": %s},\\n' "$(_json_quote "$REPORT_OS_ID")" "$(_json_quote "$REPORT_OS_PRETTY")" "$(_json_quote "$REPORT_VERSION_ID")" "$(_json_quote "$REPORT_CODENAME")"
  printf '  "apt": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "current_mirror": %s},\\n' "$(_json_quote "$REPORT_SOURCES_LIST")" "$(_json_quote "$REPORT_DEB822")" "$(_json_quote "$REPORT_MANAGED_CONFIG")" "$(_json_quote "$REPORT_CURRENT_MIRROR")"
  printf '  "backups": {"accessible": %s, "count": %s, "latest": %s},\\n' "$REPORT_BACKUP_ACCESSIBLE" "$REPORT_BACKUP_COUNT" "$(_json_quote "$REPORT_LATEST_BACKUP")"
  printf '  "operation": {"mirror": %s, "response_time_seconds": %s, "dry_run": %s, "skip_update": %s},\\n' "$(_json_quote "$SELECTED_MIRROR")" "$(_json_quote "$SELECTED_TIME")" "$DRY_RUN" "$SKIP_UPDATE"
  printf '  "paths": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "backup_root": %s},\\n' "$(_json_quote "$APT_SOURCES_FILE")" "$(_json_quote "$APT_DEB822_FILE")" "$(_json_quote "$APT_CONF_FILE")" "$(_json_quote "$BACKUP_BASE")"
  printf '  "checks": %s\\n' "$checks_json"
  printf '}\\n'
}

_status_report() {
  _collect_status
  REPORT_COMMAND="status"
  REPORT_STATUS="ok"
  [[ "$REPORT_OS_ID" == "ubuntu" ]] || REPORT_STATUS="warning"
  if [[ "$JSON_OUTPUT" == true ]]; then _print_json; else _print_status_report; fi
}

_doctor_report() {
  _doctor_collect
  REPORT_COMMAND="doctor"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _print_json
  else
    printf '\n%s\n' "$APP_NAME — Diagnostics"
    local i
    for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
      printf '  %-8s %-28s %s\n' "${REPORT_CHECK_STATUSES[$i]}" "${REPORT_CHECK_NAMES[$i]}" "${REPORT_CHECK_DETAILS[$i]}"
    done
    printf '\nOverall status: %s\n\n' "$REPORT_STATUS"
  fi
}

_print_summary() {
  if [[ "$DRY_RUN" == true ]]; then
    cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_YELLOW}${COLOR_BOLD}DRY RUN COMPLETED${COLOR_RESET}

  Fastest mirror:  ${COLOR_BOLD}${SELECTED_MIRROR}${COLOR_RESET}
  Response time:   ${COLOR_BOLD}${SELECTED_TIME}s${COLOR_RESET}

  ${COLOR_DIM}No system changes were made.${COLOR_RESET}
${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
    return
  fi

  cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_GREEN}${COLOR_BOLD}SUCCESS — APT mirror optimized${COLOR_RESET}

  ${COLOR_BOLD}Mirror:${COLOR_RESET}  ${SELECTED_MIRROR}
  ${COLOR_BOLD}Speed:${COLOR_RESET}   ${SELECTED_TIME}s

  ${COLOR_DIM}Config files:${COLOR_RESET}
    ${APT_DEB822_FILE}
    ${APT_CONF_FILE}

  ${COLOR_DIM}To undo:${COLOR_RESET}
    ${COLOR_CYAN}sudo bash ${_SCRIPT_NAME} --restore${COLOR_RESET}

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
}

_print_banner() {
  if [[ "$QUIET" == true || "$JSON_OUTPUT" == true ]]; then return; fi
  cat <<'EOF'

██████   ██████  ██     ██ ███████ ██████       █████  ██████  ████████     ██████   ██████   ██████  ███████ ████████ 
██   ██ ██    ██ ██     ██ ██      ██   ██     ██   ██ ██   ██    ██        ██   ██ ██    ██ ██    ██ ██         ██    
██████  ██    ██ ██  █  ██ █████   ██████      ███████ ██████     ██        ██████  ██    ██ ██    ██ ███████    ██    
██      ██    ██ ██ ███ ██ ██      ██   ██     ██   ██ ██         ██        ██   ██ ██    ██ ██    ██      ██    ██    
██       ██████   ███ ███  ███████ ██   ██     ██   ██ ██         ██        ██████   ██████   ██████  ███████    ██    
                                                                                                                       
                                                                                                                       
EOF
  echo "" >&2
  printf '%b\n' "  ${COLOR_DIM}Fast Ubuntu APT mirror selector & network optimizer${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}v${APP_VERSION} · ${APP_LICENSE} · ${APP_AUTHOR}${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}${APP_GITHUB}${COLOR_RESET}" >&2
  echo "" >&2
}

_print_help() {
  cat <<EOF
${COLOR_BOLD}${COLOR_CYAN}Power APT Boost${COLOR_RESET} v${APP_VERSION}
Fast Ubuntu APT mirror selector and network optimizer

${COLOR_BOLD}${COLOR_BLUE}USAGE${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}                 # Open the interactive menu on a TTY
  sudo bash ${_SCRIPT_NAME} [OPTIONS]
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

${COLOR_BOLD}${COLOR_BLUE}OPTIONS${COLOR_RESET}
  ${COLOR_GREEN}-h, --help${COLOR_RESET}              Show this help message
  ${COLOR_GREEN}-v, --version${COLOR_RESET}           Show version information
  ${COLOR_GREEN}-m, --mirror URL${COLOR_RESET}        Use a specific Ubuntu mirror
  ${COLOR_GREEN}-r, --restore${COLOR_RESET}           Restore APT config from backup
  ${COLOR_GREEN}    --restore-path PATH${COLOR_RESET}   Restore from a specific backup
  ${COLOR_GREEN}    --dry-run${COLOR_RESET}            Test mirrors without changing config
  ${COLOR_GREEN}    --skip-update${COLOR_RESET}        Write config but skip apt-get update (preserve caches)
  ${COLOR_GREEN}    --list${COLOR_RESET}               List available mirrors and test them
  ${COLOR_GREEN}    --menu${COLOR_RESET}               Open the interactive terminal menu
  ${COLOR_GREEN}    --status${COLOR_RESET}             Show current system and APT status
  ${COLOR_GREEN}    --doctor${COLOR_RESET}             Run local dependency and configuration checks
  ${COLOR_GREEN}-y, --yes${COLOR_RESET}              Confirm changes in non-interactive mode
  ${COLOR_GREEN}    --json${COLOR_RESET}               Output reports using the stable JSON schema
  ${COLOR_GREEN}    --verbose${COLOR_RESET}             Show detailed output
  ${COLOR_GREEN}    --quiet${COLOR_RESET}               Suppress non-essential output
  ${COLOR_GREEN}    --no-spinner${COLOR_RESET}          Disable spinner (for CI/CD)
  ${COLOR_GREEN}    --timeout SECS${COLOR_RESET}        Probe timeout (default: 20)
  ${COLOR_GREEN}    --country CODE${COLOR_RESET}        Filter mirrors by country code
  ${COLOR_GREEN}    --ipv6${COLOR_RESET}                Use IPv6 for mirror testing
  ${COLOR_GREEN}    --log-file PATH${COLOR_RESET}       Write log to file

${COLOR_BOLD}${COLOR_BLUE}EXAMPLES${COLOR_RESET}
  ${COLOR_DIM}# Open the interactive menu${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}

  ${COLOR_DIM}# Apply automatically from a pipe or CI job${COLOR_RESET}
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

  ${COLOR_DIM}# Read-only status and diagnostics${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --status
  sudo bash ${_SCRIPT_NAME} --doctor

  ${COLOR_DIM}# Test without changing system config${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run

  ${COLOR_DIM}# Use a specific mirror${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Restore from latest backup${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore

  ${COLOR_DIM}# Machine-readable output for CI/CD pipelines${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --json --quiet

  ${COLOR_DIM}# List and test all available mirrors${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list

  ${COLOR_DIM}# Filter mirrors by country${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --country us

${COLOR_BOLD}${COLOR_BLUE}WHAT IT DOES${COLOR_RESET}
  1. Detects your Ubuntu version
  2. Tests multiple mirrors in parallel for speed
  3. Selects the fastest working mirror
  4. Backs up current APT configuration
  5. Writes optimized APT sources (deb822 format)
  6. Configures network optimizations (retries, timeouts)
  7. Preserves existing package lists and downloaded packages when --skip-update is selected
  8. Runs apt-get update unless --skip-update is selected

${COLOR_BOLD}${COLOR_BLUE}BACKUPS${COLOR_RESET}
  Location:  ${BACKUP_BASE}/
  Restore:   sudo bash ${_SCRIPT_NAME} --restore
  Or:        sudo bash ${_SCRIPT_NAME} --restore-path /var/backups/${APP_SLUG}/<timestamp>

${COLOR_BOLD}${COLOR_BLUE}EXIT CODES${COLOR_RESET}
  ${COLOR_GREEN}0${COLOR_RESET}  Success         ${COLOR_GREEN}4${COLOR_RESET}  Not running as root
  1  General error      5  Not Ubuntu
  2  Usage error        6  No working mirror found
  3  Network error      7  Backup failed
  4  Root required      8  Restore/rollback failed

${COLOR_BOLD}${COLOR_BLUE}AUTHOR${COLOR_RESET}
  ${APP_AUTHOR} · ${APP_GITHUB}
EOF
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        _print_help
        exit "$EXIT_OK"
        ;;
      -v | --version)
        printf '%s v%s\n' "$APP_NAME" "$APP_VERSION"
        exit "$EXIT_OK"
        ;;
      -m | --mirror)
        [[ -n "${2:-}" ]] || die "Option $1 requires a URL argument." "$EXIT_USAGE"
        FORCE_MIRROR="${2%/}"
        ACTION_REQUESTED=true
        shift 2
        ;;
      -r | --restore)
        RESTORE=true
        shift
        ;;
      --restore-path)
        [[ -n "${2:-}" ]] || die "Option $1 requires a backup path." "$EXIT_USAGE"
        RESTORE_PATH="$2"
        RESTORE=true
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        ACTION_REQUESTED=true
        shift
        ;;
      --skip-update)
        SKIP_UPDATE=true
        ACTION_REQUESTED=true
        shift
        ;;
      --list)
        LIST_REQUESTED=true
        shift
        ;;
      --menu)
        MENU_REQUESTED=true
        shift
        ;;
      --status)
        STATUS_REQUESTED=true
        shift
        ;;
      --doctor)
        DOCTOR_REQUESTED=true
        shift
        ;;
      -y | --yes)
        YES=true
        shift
        ;;
      --json)
        JSON_OUTPUT=true
        QUIET=true
        NO_SPINNER=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --quiet)
        QUIET=true
        shift
        ;;
      --no-spinner)
        NO_SPINNER=true
        shift
        ;;
      --timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires a positive integer." "$EXIT_USAGE"
        (($2 >= 1 && $2 <= 300)) || die "Option $1 must be between 1 and 300 seconds." "$EXIT_USAGE"
        TIMEOUT_TOTAL="$2"
        shift 2
        ;;
      --country)
        [[ "${2:-}" =~ ^[A-Za-z]{2}$ ]] || die "Option $1 requires a two-letter country code." "$EXIT_USAGE"
        COUNTRY_FILTER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
        shift 2
        ;;
      --ipv6)
        USE_IPV6=true
        shift
        ;;
      --log-file)
        [[ -n "${2:-}" ]] || die "Option $1 requires a file path." "$EXIT_USAGE"
        LOG_FILE="$2"
        LOG_ENABLED=true
        shift 2
        ;;
      -*)
        error "Unknown option: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
      *)
        error "Unexpected argument: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
    esac
  done

  local mode_count=0
  if [[ "$MENU_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$STATUS_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$DOCTOR_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$LIST_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$RESTORE" == true ]]; then ((mode_count += 1)); fi
  ((mode_count <= 1)) || die "Choose only one command mode: menu, status, doctor, list or restore." "$EXIT_USAGE"

  if [[ "$MENU_REQUESTED" == true ]]; then
    [[ "$YES" != true && "$JSON_OUTPUT" != true && "$ACTION_REQUESTED" != true ]] || die "--menu cannot be combined with apply, --yes or --json options." "$EXIT_USAGE"
  fi
  if [[ "$STATUS_REQUESTED" == true || "$DOCTOR_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--status and --doctor are read-only commands." "$EXIT_USAGE"
  fi
  if [[ "$LIST_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--list cannot be combined with apply options." "$EXIT_USAGE"
  fi
  if [[ "$RESTORE" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--restore cannot be combined with dry-run, skip-update or mirror selection." "$EXIT_USAGE"
  fi
}

_is_interactive() {
  [[ -t 0 && -t 1 ]]
}

_confirm_action() {
  local prompt="$1"
  local answer=""
  if [[ "$YES" == true ]]; then return 0; fi
  if ! _is_interactive; then
    error "Non-interactive changes require --yes. Use --dry-run to preview without applying."
    return "$EXIT_USAGE"
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer || answer=""
  case "${answer,,}" in
    y | yes) return 0 ;;
    *) info "Cancelled. No system changes were made."; return 10 ;;
  esac
}

_print_apply_preview() {
  _print_section_header "CHANGE PREVIEW"
  printf 'Selected mirror: %s\n' "$SELECTED_MIRROR"
  printf 'APT source file: %s\n' "$APT_DEB822_FILE"
  printf 'APT network config: %s\n' "$APT_CONF_FILE"
  printf 'Backup root: %s\n' "$BACKUP_BASE"
  if [[ -f "$APT_SOURCES_FILE" ]]; then
    printf 'Legacy sources.list: may be removed if it contains only Ubuntu archive entries (%s)\n' "$APT_SOURCES_FILE"
  fi
  if [[ "$SKIP_UPDATE" == true ]]; then
    printf 'APT update: skipped; existing package lists and archive cache are preserved\n'
  else
    printf 'APT update: apt-get update will run after configuration changes\n'
  fi
}

_confirm_apply() {
  [[ "$DRY_RUN" == true ]] && return 0
  _print_apply_preview
  _confirm_action "Apply this APT mirror configuration?"
}

_confirm_restore() {
  local backup_path="$1"
  _print_section_header "RESTORE PREVIEW"
  printf 'Snapshot: %s\n' "$backup_path"
  printf 'Managed targets restored exactly: %s, %s, %s\n' "$APT_SOURCES_FILE" "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'APT update: apt-get update will run after restoration\n'
  _confirm_action "Restore this snapshot?"
}

_resolve_backup_path() {
  local backup_path="$1"
  if [[ -z "$backup_path" && -d "$BACKUP_BASE" ]]; then
    backup_path="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    local legacy_root="${_SYSTEM_ROOT}/root"
    if [[ -d "$legacy_root" ]]; then
      backup_path="$(find "$legacy_root" -maxdepth 1 -name 'apt-backup-*' -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
    fi
  fi
  [[ -n "$backup_path" && -d "$backup_path" ]] || return "$EXIT_RESTORE"
  printf '%s\n' "$backup_path"
}

_menu_choose() {
  local title="$1"
  local prompt="$2"
  shift 2
  local -a tags=() labels=() whiptail_args=()
  while (($# >= 2)); do
    tags+=("$1")
    labels+=("$2")
    whiptail_args+=("$1" "$2")
    shift 2
  done

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --menu "$prompt" 22 78 12 "${whiptail_args[@]}" 3>&1 1>&2 2>&3
    return $?
  fi

  printf '\n%s\n%s\n' "$title" "$prompt" >&2
  local i
  for ((i = 0; i < ${#tags[@]}; i++)); do
    printf '  %d) %s\n' "$((i + 1))" "${labels[$i]}" >&2
  done
  printf 'Select an option: ' >&2
  local answer=""
  IFS= read -r answer || return 1
  if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#tags[@]})); then
    printf '%s\n' "${tags[$((answer - 1))]}"
    return 0
  fi
  for ((i = 0; i < ${#tags[@]}; i++)); do
    if [[ "$answer" == "${tags[$i]}" ]]; then
      printf '%s\n' "${tags[$i]}"
      return 0
    fi
  done
  return 1
}

_menu_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local answer=""
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default_value" 3>&1 1>&2 2>&3
    return $?
  fi
  printf '%s [%s]: ' "$prompt" "$default_value" >&2
  IFS= read -r answer || return 1
  printf '%s\n' "${answer:-$default_value}"
}

_menu_message() {
  local title="$1"
  local message="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --msgbox "$message" 16 78
  else
    printf '\n%s\n%s\n' "$title" "$message" >&2
    printf 'Press Enter to continue: ' >&2
    local ignored=""
    IFS= read -r ignored || true
  fi
}

_run_list_flow() {
  _check_probe_tool
  detect_ubuntu
  if [[ "$JSON_OUTPUT" == true ]]; then
    list_mirrors >&2
    REPORT_COMMAND="list"
    REPORT_STATUS="complete"
    _collect_status
    REPORT_CHECK_NAMES=("mirror_catalog")
    REPORT_CHECK_STATUSES=("complete")
    REPORT_CHECK_DETAILS=("Mirror reachability checks completed; see stderr for detailed results")
    _print_json
  else
    list_mirrors
  fi
}

_run_benchmark_only() {
  _check_probe_tool
  detect_ubuntu
  SELECTED_MIRROR=""
  SELECTED_TIME=""
  _select_mirror
  printf '\nSelected mirror: %s\nProbe time: %ss\n\n' "$SELECTED_MIRROR" "$SELECTED_TIME"
}

_run_apply_flow() {
  if [[ "$DRY_RUN" != true && "$YES" != true ]] && ! _is_interactive; then
    error "Applying APT changes from a non-interactive session requires --yes. Use --dry-run to preview."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi

  _print_banner
  _check_commands
  _check_probe_tool
  detect_ubuntu
  if [[ "$DRY_RUN" != true ]]; then _acquire_mutation_lock; fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    _print_section_header "TESTING SPECIFIED MIRROR"
    msg "  Mirror: ${COLOR_BOLD}${FORCE_MIRROR}${COLOR_RESET}"
    local result_file rtime rstatus
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.force.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$FORCE_MIRROR" "$result_file" "$CODENAME"
    rtime="$(awk '{print $1}' "$result_file")"
    rstatus="$(awk '{print $2}' "$result_file")"
    rm -f "$result_file" 2>/dev/null || true
    if [[ "$rstatus" == "pass" ]]; then
      SELECTED_MIRROR="$FORCE_MIRROR"
      SELECTED_TIME="$rtime"
    else
      error "Mirror is not reachable: $FORCE_MIRROR"
      return "$EXIT_NO_MIRROR"
    fi
  else
    _select_mirror
  fi

  if [[ "$DRY_RUN" != true ]]; then
    local confirm_status=0
    _confirm_apply || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi
  fi

  REPORT_COMMAND="apply"
  REPORT_STATUS="success"
  [[ "$DRY_RUN" == true ]] && REPORT_STATUS="dry_run"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _apply_changes >&2
    _print_json
  else
    _apply_changes
    _print_summary
  fi
}

_run_restore_flow() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Restoring APT configuration from a non-interactive session requires --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  _check_commands

  local selected_backup confirm_status=0
  if ! selected_backup="$(_resolve_backup_path "$RESTORE_PATH")"; then
    error "No backup snapshot was found."
    return "$EXIT_RESTORE"
  fi
  _confirm_restore "$selected_backup" || confirm_status=$?
  if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi

  _acquire_mutation_lock
  REPORT_COMMAND="restore"
  REPORT_STATUS="success"
  SELECTED_MIRROR="restored"
  SELECTED_TIME=""
  if [[ "$JSON_OUTPUT" == true ]]; then
    _restore_backup "$selected_backup" >&2 || return "$EXIT_RESTORE"
    apt-get update >&2 || return "$EXIT_NETWORK"
    _print_json
  else
    _restore_backup "$selected_backup" || return "$EXIT_RESTORE"
    apt-get update || return "$EXIT_NETWORK"
    info "APT sources restored and updated successfully."
  fi
}

_menu_overview() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    _status_report
  else
    _print_status_report
    _menu_message "Overview" "System status refreshed."
  fi
}

_menu_apt() {
  local choice rc
  while true; do
    choice="$(_menu_choose "APT Management" "Choose an action" \\
      "apply_best" "Find and apply the fastest mirror" \\
      "apply_custom" "Test and apply a custom mirror" \\
      "list" "List and test available mirrors" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      apply_best)
        FORCE_MIRROR=""
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      apply_custom)
        FORCE_MIRROR="$(_menu_input "Custom mirror" "Enter an Ubuntu mirror base URL" "")" || continue
        [[ "$FORCE_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || {
          _menu_message "Invalid mirror URL" "Enter an http:// or https:// URL without spaces."
          continue
        }
        FORCE_MIRROR="${FORCE_MIRROR%/}"
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      list)
        _run_list_flow
        _menu_message "APT mirrors" "Mirror testing completed."
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_benchmark() {
  _run_benchmark_only
  _menu_message "Benchmark" "Benchmark completed. No system configuration was changed."
}

_menu_backups() {
  if [[ "$(id -u)" -ne 0 ]]; then
    _menu_message "Backup and Restore" "Run the menu as root to inspect protected system backups."
    return 0
  fi
  local listing
  listing="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn || true)"
  if [[ -z "$listing" ]]; then
    _menu_message "Backup and Restore" "No Power APT Boost backup snapshots were found."
    return 0
  fi
  local -a args=()
  local line path
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    args+=("$path" "${path##*/}")
  done <<<"$listing"
  local selected rc
  selected="$(_menu_choose "Backup and Restore" "Select a snapshot to restore" "${args[@]}" "back" "Back")" || return 0
  [[ "$selected" == back ]] && return 0
  RESTORE_PATH="$selected"
  rc=0
  _run_restore_flow || rc=$?
  [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Restore result" "Restore finished with exit code $rc."
}

_menu_diagnostics() {
  local choice
  choice="$(_menu_choose "Diagnostics" "Choose a report" \\
    "status" "System status" \\
    "doctor" "Run local health checks" \\
    "back" "Back to main menu")" || return 0
  case "$choice" in
    status)
      _status_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Status report completed."
      ;;
    doctor)
      _doctor_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Health checks completed."
      ;;
    back) return 0 ;;
  esac
}

_country_code_supported() {
  local requested="$1" entry country mirror_url
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r country _ mirror_url <<<"$entry"
    [[ "$country" != "$requested" ]] || return 0
  done
  return 1
}

_menu_settings() {
  local choice value
  while true; do
    choice="$(_menu_choose "Settings" "Settings apply to this session only" \\
      "timeout" "Probe timeout: ${TIMEOUT_TOTAL}s" \\
      "country" "Country filter: ${COUNTRY_FILTER:-all}" \\
      "ipv6" "IP family: $([[ "$USE_IPV6" == true ]] && echo IPv6 || echo IPv4)" \\
      "spinner" "Spinner: $([[ "$NO_SPINNER" == true ]] && echo disabled || echo enabled)" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      timeout)
        value="$(_menu_input "Probe timeout" "Enter timeout in seconds (1-300)" "$TIMEOUT_TOTAL")" || continue
        if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 300)); then
          TIMEOUT_TOTAL="$value"
        else
          _menu_message "Invalid timeout" "Enter a whole number from 1 to 300."
        fi
        ;;
      country)
        value="$(_menu_input "Country filter" "Enter a supported two-letter country code, or leave empty for all" "$COUNTRY_FILTER")" || continue
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$value" ]]; then
          COUNTRY_FILTER=""
        elif [[ "$value" =~ ^[a-z]{2}$ ]] && _country_code_supported "$value"; then
          COUNTRY_FILTER="$value"
        else
          _menu_message "Unsupported country" "Choose a country code present in the built-in mirror catalog."
        fi
        ;;
      ipv6)
        [[ "$USE_IPV6" == true ]] && USE_IPV6=false || USE_IPV6=true
        ;;
      spinner)
        [[ "$NO_SPINNER" == true ]] && NO_SPINNER=false || NO_SPINNER=true
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_main() {
  if ! _is_interactive; then
    error "The interactive menu requires a TTY. Use --help for non-interactive commands."
    return "$EXIT_USAGE"
  fi
  while true; do
    local choice
    choice="$(_menu_choose "$APP_NAME v$APP_VERSION" "Main menu" \\
      "overview" "Overview" \\
      "apt" "APT management" \\
      "benchmark" "Mirror benchmark" \\
      "backups" "Backup and Restore" \\
      "diagnostics" "Diagnostics" \\
      "settings" "Settings" \\
      "exit" "Exit")" || return 0
    case "$choice" in
      overview) _menu_overview ;;
      apt) _menu_apt ;;
      benchmark) _menu_benchmark ;;
      backups) _menu_backups ;;
      diagnostics) _menu_diagnostics ;;
      settings) _menu_settings ;;
      exit) return 0 ;;
    esac
  done
}

main() {
  _setup_colors
  _parse_args "$@"

  if [[ "$LOG_ENABLED" == true ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : >"$LOG_FILE"
    _log_to_file "Session started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  if [[ "$STATUS_REQUESTED" == true ]]; then
    _status_report
    exit "$EXIT_OK"
  fi

  if [[ "$DOCTOR_REQUESTED" == true ]]; then
    _doctor_report
    [[ "$REPORT_STATUS" != "error" ]] || exit "$EXIT_GENERAL"
    exit "$EXIT_OK"
  fi

  if [[ "$LIST_REQUESTED" == true ]]; then
    local list_status=0
    _run_list_flow || list_status=$?
    exit "$list_status"
  fi

  if [[ "$RESTORE" == true ]]; then
    local restore_status=0
    _run_restore_flow || restore_status=$?
    [[ "$restore_status" -eq "$EXIT_CANCELLED" ]] && restore_status="$EXIT_OK"
    exit "$restore_status"
  fi

  if [[ "$MENU_REQUESTED" == true ]]; then
    local menu_status=0
    _menu_main || menu_status=$?
    exit "$menu_status"
  fi

  if [[ "$ACTION_REQUESTED" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
    if _is_interactive; then
      _menu_main
      exit $?
    fi
    error "No command was selected. A non-interactive apply requires --yes; use --status, --doctor or --dry-run for read-only checks."
    exit "$EXIT_USAGE"
  fi

  local apply_status=0
  _run_apply_flow || apply_status=$?
  [[ "$apply_status" -eq "$EXIT_CANCELLED" ]] && apply_status="$EXIT_OK"
  exit "$apply_status"
}
if [[ "${POWER_APT_BOOST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
\t'/\\t}"
  value="${value//
}

_collect_status() {
  REPORT_OS_ID="unknown"
  REPORT_OS_PRETTY="unknown"
  REPORT_VERSION_ID="unknown"
  REPORT_CODENAME="unknown"
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$OS_RELEASE_FILE"
    REPORT_OS_ID="${ID:-unknown}"
    REPORT_OS_PRETTY="${PRETTY_NAME:-${ID:-unknown}}"
    REPORT_VERSION_ID="${VERSION_ID:-unknown}"
    REPORT_CODENAME="${VERSION_CODENAME:-unknown}"
  fi
  REPORT_SOURCES_LIST="absent"
  REPORT_DEB822="absent"
  REPORT_MANAGED_CONFIG="absent"
  [[ ! -e "$APT_SOURCES_FILE" ]] || REPORT_SOURCES_LIST="present"
  [[ ! -e "$APT_DEB822_FILE" ]] || REPORT_DEB822="present"
  [[ ! -e "$APT_CONF_FILE" ]] || REPORT_MANAGED_CONFIG="present"

  REPORT_CURRENT_MIRROR=""
  if [[ -r "$APT_DEB822_FILE" ]]; then
    REPORT_CURRENT_MIRROR="$(awk -F': ' '$1 == "URIs" {print $2; exit}' "$APT_DEB822_FILE" 2>/dev/null || true)"
    REPORT_CURRENT_MIRROR="$(printf '%s' "$REPORT_CURRENT_MIRROR" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g')"
  fi
  REPORT_BACKUP_ACCESSIBLE=false
  REPORT_BACKUP_COUNT=0
  REPORT_LATEST_BACKUP=""
  if [[ -d "$BACKUP_BASE" && -r "$BACKUP_BASE" ]]; then
    REPORT_BACKUP_ACCESSIBLE=true
    REPORT_BACKUP_COUNT="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]')"
    REPORT_LATEST_BACKUP="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
}

_print_status_report() {
  _collect_status
  printf '\n%s\n' "$APP_NAME — System Status"
  printf '%-24s %s\n' "Operating system:" "$REPORT_OS_PRETTY"
  printf '%-24s %s\n' "Ubuntu codename:" "$REPORT_CODENAME"
  printf '%-24s %s\n' "Legacy sources.list:" "$REPORT_SOURCES_LIST"
  printf '%-24s %s\n' "Deb822 ubuntu.sources:" "$REPORT_DEB822"
  printf '%-24s %s\n' "Managed APT config:" "$REPORT_MANAGED_CONFIG"
  printf '%-24s %s\n' "Current mirror:" "${REPORT_CURRENT_MIRROR:-not detected}"
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    printf '%-24s %s\n' "Available backups:" "$REPORT_BACKUP_COUNT"
    printf '%-24s %s\n' "Latest backup:" "${REPORT_LATEST_BACKUP:-none}"
  else
    printf '%-24s %s\n' "Backup directory:" "not accessible (root may be required)"
  fi
  printf '\n'
}

_doctor_add_check() {
  REPORT_CHECK_NAMES+=("$1")
  REPORT_CHECK_STATUSES+=("$2")
  REPORT_CHECK_DETAILS+=("$3")
  case "$2" in
    error) REPORT_STATUS="error" ;;
    warning)
      [[ "$REPORT_STATUS" == "error" ]] || REPORT_STATUS="warning"
      ;;
  esac
}

_doctor_collect() {
  _collect_status
  REPORT_CHECK_NAMES=()
  REPORT_CHECK_STATUSES=()
  REPORT_CHECK_DETAILS=()
  REPORT_STATUS="ok"
  if [[ "$REPORT_OS_ID" == "ubuntu" ]]; then
    _doctor_add_check "operating_system" "ok" "$REPORT_OS_PRETTY"
  else
    _doctor_add_check "operating_system" "error" "Ubuntu is required; detected $REPORT_OS_PRETTY"
  fi
  local cmd
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat find sort head cut chown mv rm sed; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _doctor_add_check "command:$cmd" "ok" "available"
    else
      _doctor_add_check "command:$cmd" "error" "missing required command"
    fi
  done
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    _doctor_add_check "http_client" "ok" "curl or wget is available"
  else
    _doctor_add_check "http_client" "error" "curl or wget is required"
  fi
  if [[ -f "$KEYRING_PATH" ]]; then
    _doctor_add_check "ubuntu_archive_keyring" "ok" "keyring exists"
  else
    _doctor_add_check "ubuntu_archive_keyring" "warning" "keyring not found at $KEYRING_PATH"
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    _doctor_add_check "privileges" "ok" "running as root"
  else
    _doctor_add_check "privileges" "warning" "root is required for apply and restore operations"
  fi
  if [[ -r "$APT_ETC_DIR" ]]; then
    _doctor_add_check "apt_configuration" "ok" "APT configuration directory is readable"
  else
    _doctor_add_check "apt_configuration" "warning" "APT configuration directory is not readable"
  fi
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    _doctor_add_check "backup_directory" "ok" "$REPORT_BACKUP_COUNT backup snapshot(s) visible"
  else
    _doctor_add_check "backup_directory" "warning" "backup directory is not currently accessible or has not been created"
  fi
}

_report_checks_json() {
  local i
  printf '['
  for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
    if ((i > 0)); then printf ','; fi
    printf '{"name":%s,"status":%s,"detail":%s}' "$(_json_quote "${REPORT_CHECK_NAMES[$i]}")" "$(_json_quote "${REPORT_CHECK_STATUSES[$i]}")" "$(_json_quote "${REPORT_CHECK_DETAILS[$i]}")"
  done
  printf ']'
}

_print_json() {
  _collect_status
  local checks_json
  checks_json="$(_report_checks_json)"
  printf '{\\n'
  printf '  "schema_version": 1,\\n'
  printf '  "version": %s,\\n' "$(_json_quote "$APP_VERSION")"
  printf '  "command": %s,\\n' "$(_json_quote "$REPORT_COMMAND")"
  printf '  "status": %s,\\n' "$(_json_quote "$REPORT_STATUS")"
  printf '  "timestamp": %s,\\n' "$(_json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "system": {"id": %s, "pretty_name": %s, "version_id": %s, "codename": %s},\\n' "$(_json_quote "$REPORT_OS_ID")" "$(_json_quote "$REPORT_OS_PRETTY")" "$(_json_quote "$REPORT_VERSION_ID")" "$(_json_quote "$REPORT_CODENAME")"
  printf '  "apt": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "current_mirror": %s},\\n' "$(_json_quote "$REPORT_SOURCES_LIST")" "$(_json_quote "$REPORT_DEB822")" "$(_json_quote "$REPORT_MANAGED_CONFIG")" "$(_json_quote "$REPORT_CURRENT_MIRROR")"
  printf '  "backups": {"accessible": %s, "count": %s, "latest": %s},\\n' "$REPORT_BACKUP_ACCESSIBLE" "$REPORT_BACKUP_COUNT" "$(_json_quote "$REPORT_LATEST_BACKUP")"
  printf '  "operation": {"mirror": %s, "response_time_seconds": %s, "dry_run": %s, "skip_update": %s},\\n' "$(_json_quote "$SELECTED_MIRROR")" "$(_json_quote "$SELECTED_TIME")" "$DRY_RUN" "$SKIP_UPDATE"
  printf '  "paths": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "backup_root": %s},\\n' "$(_json_quote "$APT_SOURCES_FILE")" "$(_json_quote "$APT_DEB822_FILE")" "$(_json_quote "$APT_CONF_FILE")" "$(_json_quote "$BACKUP_BASE")"
  printf '  "checks": %s\\n' "$checks_json"
  printf '}\\n'
}

_status_report() {
  _collect_status
  REPORT_COMMAND="status"
  REPORT_STATUS="ok"
  [[ "$REPORT_OS_ID" == "ubuntu" ]] || REPORT_STATUS="warning"
  if [[ "$JSON_OUTPUT" == true ]]; then _print_json; else _print_status_report; fi
}

_doctor_report() {
  _doctor_collect
  REPORT_COMMAND="doctor"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _print_json
  else
    printf '\n%s\n' "$APP_NAME — Diagnostics"
    local i
    for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
      printf '  %-8s %-28s %s\n' "${REPORT_CHECK_STATUSES[$i]}" "${REPORT_CHECK_NAMES[$i]}" "${REPORT_CHECK_DETAILS[$i]}"
    done
    printf '\nOverall status: %s\n\n' "$REPORT_STATUS"
  fi
}

_print_summary() {
  if [[ "$DRY_RUN" == true ]]; then
    cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_YELLOW}${COLOR_BOLD}DRY RUN COMPLETED${COLOR_RESET}

  Fastest mirror:  ${COLOR_BOLD}${SELECTED_MIRROR}${COLOR_RESET}
  Response time:   ${COLOR_BOLD}${SELECTED_TIME}s${COLOR_RESET}

  ${COLOR_DIM}No system changes were made.${COLOR_RESET}
${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
    return
  fi

  cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_GREEN}${COLOR_BOLD}SUCCESS — APT mirror optimized${COLOR_RESET}

  ${COLOR_BOLD}Mirror:${COLOR_RESET}  ${SELECTED_MIRROR}
  ${COLOR_BOLD}Speed:${COLOR_RESET}   ${SELECTED_TIME}s

  ${COLOR_DIM}Config files:${COLOR_RESET}
    ${APT_DEB822_FILE}
    ${APT_CONF_FILE}

  ${COLOR_DIM}To undo:${COLOR_RESET}
    ${COLOR_CYAN}sudo bash ${_SCRIPT_NAME} --restore${COLOR_RESET}

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
}

_print_banner() {
  if [[ "$QUIET" == true || "$JSON_OUTPUT" == true ]]; then return; fi
  cat <<'EOF'

██████   ██████  ██     ██ ███████ ██████       █████  ██████  ████████     ██████   ██████   ██████  ███████ ████████ 
██   ██ ██    ██ ██     ██ ██      ██   ██     ██   ██ ██   ██    ██        ██   ██ ██    ██ ██    ██ ██         ██    
██████  ██    ██ ██  █  ██ █████   ██████      ███████ ██████     ██        ██████  ██    ██ ██    ██ ███████    ██    
██      ██    ██ ██ ███ ██ ██      ██   ██     ██   ██ ██         ██        ██   ██ ██    ██ ██    ██      ██    ██    
██       ██████   ███ ███  ███████ ██   ██     ██   ██ ██         ██        ██████   ██████   ██████  ███████    ██    
                                                                                                                       
                                                                                                                       
EOF
  echo "" >&2
  printf '%b\n' "  ${COLOR_DIM}Fast Ubuntu APT mirror selector & network optimizer${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}v${APP_VERSION} · ${APP_LICENSE} · ${APP_AUTHOR}${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}${APP_GITHUB}${COLOR_RESET}" >&2
  echo "" >&2
}

_print_help() {
  cat <<EOF
${COLOR_BOLD}${COLOR_CYAN}Power APT Boost${COLOR_RESET} v${APP_VERSION}
Fast Ubuntu APT mirror selector and network optimizer

${COLOR_BOLD}${COLOR_BLUE}USAGE${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}                 # Open the interactive menu on a TTY
  sudo bash ${_SCRIPT_NAME} [OPTIONS]
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

${COLOR_BOLD}${COLOR_BLUE}OPTIONS${COLOR_RESET}
  ${COLOR_GREEN}-h, --help${COLOR_RESET}              Show this help message
  ${COLOR_GREEN}-v, --version${COLOR_RESET}           Show version information
  ${COLOR_GREEN}-m, --mirror URL${COLOR_RESET}        Use a specific Ubuntu mirror
  ${COLOR_GREEN}-r, --restore${COLOR_RESET}           Restore APT config from backup
  ${COLOR_GREEN}    --restore-path PATH${COLOR_RESET}   Restore from a specific backup
  ${COLOR_GREEN}    --dry-run${COLOR_RESET}            Test mirrors without changing config
  ${COLOR_GREEN}    --skip-update${COLOR_RESET}        Write config but skip apt-get update (preserve caches)
  ${COLOR_GREEN}    --list${COLOR_RESET}               List available mirrors and test them
  ${COLOR_GREEN}    --menu${COLOR_RESET}               Open the interactive terminal menu
  ${COLOR_GREEN}    --status${COLOR_RESET}             Show current system and APT status
  ${COLOR_GREEN}    --doctor${COLOR_RESET}             Run local dependency and configuration checks
  ${COLOR_GREEN}-y, --yes${COLOR_RESET}              Confirm changes in non-interactive mode
  ${COLOR_GREEN}    --json${COLOR_RESET}               Output reports using the stable JSON schema
  ${COLOR_GREEN}    --verbose${COLOR_RESET}             Show detailed output
  ${COLOR_GREEN}    --quiet${COLOR_RESET}               Suppress non-essential output
  ${COLOR_GREEN}    --no-spinner${COLOR_RESET}          Disable spinner (for CI/CD)
  ${COLOR_GREEN}    --timeout SECS${COLOR_RESET}        Probe timeout (default: 20)
  ${COLOR_GREEN}    --country CODE${COLOR_RESET}        Filter mirrors by country code
  ${COLOR_GREEN}    --ipv6${COLOR_RESET}                Use IPv6 for mirror testing
  ${COLOR_GREEN}    --log-file PATH${COLOR_RESET}       Write log to file

${COLOR_BOLD}${COLOR_BLUE}EXAMPLES${COLOR_RESET}
  ${COLOR_DIM}# Open the interactive menu${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}

  ${COLOR_DIM}# Apply automatically from a pipe or CI job${COLOR_RESET}
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

  ${COLOR_DIM}# Read-only status and diagnostics${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --status
  sudo bash ${_SCRIPT_NAME} --doctor

  ${COLOR_DIM}# Test without changing system config${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run

  ${COLOR_DIM}# Use a specific mirror${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Restore from latest backup${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore

  ${COLOR_DIM}# Machine-readable output for CI/CD pipelines${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --json --quiet

  ${COLOR_DIM}# List and test all available mirrors${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list

  ${COLOR_DIM}# Filter mirrors by country${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --country us

${COLOR_BOLD}${COLOR_BLUE}WHAT IT DOES${COLOR_RESET}
  1. Detects your Ubuntu version
  2. Tests multiple mirrors in parallel for speed
  3. Selects the fastest working mirror
  4. Backs up current APT configuration
  5. Writes optimized APT sources (deb822 format)
  6. Configures network optimizations (retries, timeouts)
  7. Preserves existing package lists and downloaded packages when --skip-update is selected
  8. Runs apt-get update unless --skip-update is selected

${COLOR_BOLD}${COLOR_BLUE}BACKUPS${COLOR_RESET}
  Location:  ${BACKUP_BASE}/
  Restore:   sudo bash ${_SCRIPT_NAME} --restore
  Or:        sudo bash ${_SCRIPT_NAME} --restore-path /var/backups/${APP_SLUG}/<timestamp>

${COLOR_BOLD}${COLOR_BLUE}EXIT CODES${COLOR_RESET}
  ${COLOR_GREEN}0${COLOR_RESET}  Success         ${COLOR_GREEN}4${COLOR_RESET}  Not running as root
  1  General error      5  Not Ubuntu
  2  Usage error        6  No working mirror found
  3  Network error      7  Backup failed
  4  Root required      8  Restore/rollback failed

${COLOR_BOLD}${COLOR_BLUE}AUTHOR${COLOR_RESET}
  ${APP_AUTHOR} · ${APP_GITHUB}
EOF
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        _print_help
        exit "$EXIT_OK"
        ;;
      -v | --version)
        printf '%s v%s\n' "$APP_NAME" "$APP_VERSION"
        exit "$EXIT_OK"
        ;;
      -m | --mirror)
        [[ -n "${2:-}" ]] || die "Option $1 requires a URL argument." "$EXIT_USAGE"
        FORCE_MIRROR="${2%/}"
        ACTION_REQUESTED=true
        shift 2
        ;;
      -r | --restore)
        RESTORE=true
        shift
        ;;
      --restore-path)
        [[ -n "${2:-}" ]] || die "Option $1 requires a backup path." "$EXIT_USAGE"
        RESTORE_PATH="$2"
        RESTORE=true
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        ACTION_REQUESTED=true
        shift
        ;;
      --skip-update)
        SKIP_UPDATE=true
        ACTION_REQUESTED=true
        shift
        ;;
      --list)
        LIST_REQUESTED=true
        shift
        ;;
      --menu)
        MENU_REQUESTED=true
        shift
        ;;
      --status)
        STATUS_REQUESTED=true
        shift
        ;;
      --doctor)
        DOCTOR_REQUESTED=true
        shift
        ;;
      -y | --yes)
        YES=true
        shift
        ;;
      --json)
        JSON_OUTPUT=true
        QUIET=true
        NO_SPINNER=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --quiet)
        QUIET=true
        shift
        ;;
      --no-spinner)
        NO_SPINNER=true
        shift
        ;;
      --timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires a positive integer." "$EXIT_USAGE"
        (($2 >= 1 && $2 <= 300)) || die "Option $1 must be between 1 and 300 seconds." "$EXIT_USAGE"
        TIMEOUT_TOTAL="$2"
        shift 2
        ;;
      --country)
        [[ "${2:-}" =~ ^[A-Za-z]{2}$ ]] || die "Option $1 requires a two-letter country code." "$EXIT_USAGE"
        COUNTRY_FILTER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
        shift 2
        ;;
      --ipv6)
        USE_IPV6=true
        shift
        ;;
      --log-file)
        [[ -n "${2:-}" ]] || die "Option $1 requires a file path." "$EXIT_USAGE"
        LOG_FILE="$2"
        LOG_ENABLED=true
        shift 2
        ;;
      -*)
        error "Unknown option: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
      *)
        error "Unexpected argument: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
    esac
  done

  local mode_count=0
  if [[ "$MENU_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$STATUS_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$DOCTOR_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$LIST_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$RESTORE" == true ]]; then ((mode_count += 1)); fi
  ((mode_count <= 1)) || die "Choose only one command mode: menu, status, doctor, list or restore." "$EXIT_USAGE"

  if [[ "$MENU_REQUESTED" == true ]]; then
    [[ "$YES" != true && "$JSON_OUTPUT" != true && "$ACTION_REQUESTED" != true ]] || die "--menu cannot be combined with apply, --yes or --json options." "$EXIT_USAGE"
  fi
  if [[ "$STATUS_REQUESTED" == true || "$DOCTOR_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--status and --doctor are read-only commands." "$EXIT_USAGE"
  fi
  if [[ "$LIST_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--list cannot be combined with apply options." "$EXIT_USAGE"
  fi
  if [[ "$RESTORE" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--restore cannot be combined with dry-run, skip-update or mirror selection." "$EXIT_USAGE"
  fi
}

_is_interactive() {
  [[ -t 0 && -t 1 ]]
}

_confirm_action() {
  local prompt="$1"
  local answer=""
  if [[ "$YES" == true ]]; then return 0; fi
  if ! _is_interactive; then
    error "Non-interactive changes require --yes. Use --dry-run to preview without applying."
    return "$EXIT_USAGE"
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer || answer=""
  case "${answer,,}" in
    y | yes) return 0 ;;
    *) info "Cancelled. No system changes were made."; return 10 ;;
  esac
}

_print_apply_preview() {
  _print_section_header "CHANGE PREVIEW"
  printf 'Selected mirror: %s\n' "$SELECTED_MIRROR"
  printf 'APT source file: %s\n' "$APT_DEB822_FILE"
  printf 'APT network config: %s\n' "$APT_CONF_FILE"
  printf 'Backup root: %s\n' "$BACKUP_BASE"
  if [[ -f "$APT_SOURCES_FILE" ]]; then
    printf 'Legacy sources.list: may be removed if it contains only Ubuntu archive entries (%s)\n' "$APT_SOURCES_FILE"
  fi
  if [[ "$SKIP_UPDATE" == true ]]; then
    printf 'APT update: skipped; existing package lists and archive cache are preserved\n'
  else
    printf 'APT update: apt-get update will run after configuration changes\n'
  fi
}

_confirm_apply() {
  [[ "$DRY_RUN" == true ]] && return 0
  _print_apply_preview
  _confirm_action "Apply this APT mirror configuration?"
}

_confirm_restore() {
  local backup_path="$1"
  _print_section_header "RESTORE PREVIEW"
  printf 'Snapshot: %s\n' "$backup_path"
  printf 'Managed targets restored exactly: %s, %s, %s\n' "$APT_SOURCES_FILE" "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'APT update: apt-get update will run after restoration\n'
  _confirm_action "Restore this snapshot?"
}

_resolve_backup_path() {
  local backup_path="$1"
  if [[ -z "$backup_path" && -d "$BACKUP_BASE" ]]; then
    backup_path="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    local legacy_root="${_SYSTEM_ROOT}/root"
    if [[ -d "$legacy_root" ]]; then
      backup_path="$(find "$legacy_root" -maxdepth 1 -name 'apt-backup-*' -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
    fi
  fi
  [[ -n "$backup_path" && -d "$backup_path" ]] || return "$EXIT_RESTORE"
  printf '%s\n' "$backup_path"
}

_menu_choose() {
  local title="$1"
  local prompt="$2"
  shift 2
  local -a tags=() labels=() whiptail_args=()
  while (($# >= 2)); do
    tags+=("$1")
    labels+=("$2")
    whiptail_args+=("$1" "$2")
    shift 2
  done

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --menu "$prompt" 22 78 12 "${whiptail_args[@]}" 3>&1 1>&2 2>&3
    return $?
  fi

  printf '\n%s\n%s\n' "$title" "$prompt" >&2
  local i
  for ((i = 0; i < ${#tags[@]}; i++)); do
    printf '  %d) %s\n' "$((i + 1))" "${labels[$i]}" >&2
  done
  printf 'Select an option: ' >&2
  local answer=""
  IFS= read -r answer || return 1
  if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#tags[@]})); then
    printf '%s\n' "${tags[$((answer - 1))]}"
    return 0
  fi
  for ((i = 0; i < ${#tags[@]}; i++)); do
    if [[ "$answer" == "${tags[$i]}" ]]; then
      printf '%s\n' "${tags[$i]}"
      return 0
    fi
  done
  return 1
}

_menu_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local answer=""
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default_value" 3>&1 1>&2 2>&3
    return $?
  fi
  printf '%s [%s]: ' "$prompt" "$default_value" >&2
  IFS= read -r answer || return 1
  printf '%s\n' "${answer:-$default_value}"
}

_menu_message() {
  local title="$1"
  local message="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --msgbox "$message" 16 78
  else
    printf '\n%s\n%s\n' "$title" "$message" >&2
    printf 'Press Enter to continue: ' >&2
    local ignored=""
    IFS= read -r ignored || true
  fi
}

_run_list_flow() {
  _check_probe_tool
  detect_ubuntu
  if [[ "$JSON_OUTPUT" == true ]]; then
    list_mirrors >&2
    REPORT_COMMAND="list"
    REPORT_STATUS="complete"
    _collect_status
    REPORT_CHECK_NAMES=("mirror_catalog")
    REPORT_CHECK_STATUSES=("complete")
    REPORT_CHECK_DETAILS=("Mirror reachability checks completed; see stderr for detailed results")
    _print_json
  else
    list_mirrors
  fi
}

_run_benchmark_only() {
  _check_probe_tool
  detect_ubuntu
  SELECTED_MIRROR=""
  SELECTED_TIME=""
  _select_mirror
  printf '\nSelected mirror: %s\nProbe time: %ss\n\n' "$SELECTED_MIRROR" "$SELECTED_TIME"
}

_run_apply_flow() {
  if [[ "$DRY_RUN" != true && "$YES" != true ]] && ! _is_interactive; then
    error "Applying APT changes from a non-interactive session requires --yes. Use --dry-run to preview."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi

  _print_banner
  _check_commands
  _check_probe_tool
  detect_ubuntu
  if [[ "$DRY_RUN" != true ]]; then _acquire_mutation_lock; fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    _print_section_header "TESTING SPECIFIED MIRROR"
    msg "  Mirror: ${COLOR_BOLD}${FORCE_MIRROR}${COLOR_RESET}"
    local result_file rtime rstatus
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.force.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$FORCE_MIRROR" "$result_file" "$CODENAME"
    rtime="$(awk '{print $1}' "$result_file")"
    rstatus="$(awk '{print $2}' "$result_file")"
    rm -f "$result_file" 2>/dev/null || true
    if [[ "$rstatus" == "pass" ]]; then
      SELECTED_MIRROR="$FORCE_MIRROR"
      SELECTED_TIME="$rtime"
    else
      error "Mirror is not reachable: $FORCE_MIRROR"
      return "$EXIT_NO_MIRROR"
    fi
  else
    _select_mirror
  fi

  if [[ "$DRY_RUN" != true ]]; then
    local confirm_status=0
    _confirm_apply || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi
  fi

  REPORT_COMMAND="apply"
  REPORT_STATUS="success"
  [[ "$DRY_RUN" == true ]] && REPORT_STATUS="dry_run"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _apply_changes >&2
    _print_json
  else
    _apply_changes
    _print_summary
  fi
}

_run_restore_flow() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Restoring APT configuration from a non-interactive session requires --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  _check_commands

  local selected_backup confirm_status=0
  if ! selected_backup="$(_resolve_backup_path "$RESTORE_PATH")"; then
    error "No backup snapshot was found."
    return "$EXIT_RESTORE"
  fi
  _confirm_restore "$selected_backup" || confirm_status=$?
  if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi

  _acquire_mutation_lock
  REPORT_COMMAND="restore"
  REPORT_STATUS="success"
  SELECTED_MIRROR="restored"
  SELECTED_TIME=""
  if [[ "$JSON_OUTPUT" == true ]]; then
    _restore_backup "$selected_backup" >&2 || return "$EXIT_RESTORE"
    apt-get update >&2 || return "$EXIT_NETWORK"
    _print_json
  else
    _restore_backup "$selected_backup" || return "$EXIT_RESTORE"
    apt-get update || return "$EXIT_NETWORK"
    info "APT sources restored and updated successfully."
  fi
}

_menu_overview() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    _status_report
  else
    _print_status_report
    _menu_message "Overview" "System status refreshed."
  fi
}

_menu_apt() {
  local choice rc
  while true; do
    choice="$(_menu_choose "APT Management" "Choose an action" \\
      "apply_best" "Find and apply the fastest mirror" \\
      "apply_custom" "Test and apply a custom mirror" \\
      "list" "List and test available mirrors" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      apply_best)
        FORCE_MIRROR=""
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      apply_custom)
        FORCE_MIRROR="$(_menu_input "Custom mirror" "Enter an Ubuntu mirror base URL" "")" || continue
        [[ "$FORCE_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || {
          _menu_message "Invalid mirror URL" "Enter an http:// or https:// URL without spaces."
          continue
        }
        FORCE_MIRROR="${FORCE_MIRROR%/}"
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      list)
        _run_list_flow
        _menu_message "APT mirrors" "Mirror testing completed."
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_benchmark() {
  _run_benchmark_only
  _menu_message "Benchmark" "Benchmark completed. No system configuration was changed."
}

_menu_backups() {
  if [[ "$(id -u)" -ne 0 ]]; then
    _menu_message "Backup and Restore" "Run the menu as root to inspect protected system backups."
    return 0
  fi
  local listing
  listing="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn || true)"
  if [[ -z "$listing" ]]; then
    _menu_message "Backup and Restore" "No Power APT Boost backup snapshots were found."
    return 0
  fi
  local -a args=()
  local line path
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    args+=("$path" "${path##*/}")
  done <<<"$listing"
  local selected rc
  selected="$(_menu_choose "Backup and Restore" "Select a snapshot to restore" "${args[@]}" "back" "Back")" || return 0
  [[ "$selected" == back ]] && return 0
  RESTORE_PATH="$selected"
  rc=0
  _run_restore_flow || rc=$?
  [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Restore result" "Restore finished with exit code $rc."
}

_menu_diagnostics() {
  local choice
  choice="$(_menu_choose "Diagnostics" "Choose a report" \\
    "status" "System status" \\
    "doctor" "Run local health checks" \\
    "back" "Back to main menu")" || return 0
  case "$choice" in
    status)
      _status_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Status report completed."
      ;;
    doctor)
      _doctor_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Health checks completed."
      ;;
    back) return 0 ;;
  esac
}

_country_code_supported() {
  local requested="$1" entry country mirror_url
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r country _ mirror_url <<<"$entry"
    [[ "$country" != "$requested" ]] || return 0
  done
  return 1
}

_menu_settings() {
  local choice value
  while true; do
    choice="$(_menu_choose "Settings" "Settings apply to this session only" \\
      "timeout" "Probe timeout: ${TIMEOUT_TOTAL}s" \\
      "country" "Country filter: ${COUNTRY_FILTER:-all}" \\
      "ipv6" "IP family: $([[ "$USE_IPV6" == true ]] && echo IPv6 || echo IPv4)" \\
      "spinner" "Spinner: $([[ "$NO_SPINNER" == true ]] && echo disabled || echo enabled)" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      timeout)
        value="$(_menu_input "Probe timeout" "Enter timeout in seconds (1-300)" "$TIMEOUT_TOTAL")" || continue
        if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 300)); then
          TIMEOUT_TOTAL="$value"
        else
          _menu_message "Invalid timeout" "Enter a whole number from 1 to 300."
        fi
        ;;
      country)
        value="$(_menu_input "Country filter" "Enter a supported two-letter country code, or leave empty for all" "$COUNTRY_FILTER")" || continue
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$value" ]]; then
          COUNTRY_FILTER=""
        elif [[ "$value" =~ ^[a-z]{2}$ ]] && _country_code_supported "$value"; then
          COUNTRY_FILTER="$value"
        else
          _menu_message "Unsupported country" "Choose a country code present in the built-in mirror catalog."
        fi
        ;;
      ipv6)
        [[ "$USE_IPV6" == true ]] && USE_IPV6=false || USE_IPV6=true
        ;;
      spinner)
        [[ "$NO_SPINNER" == true ]] && NO_SPINNER=false || NO_SPINNER=true
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_main() {
  if ! _is_interactive; then
    error "The interactive menu requires a TTY. Use --help for non-interactive commands."
    return "$EXIT_USAGE"
  fi
  while true; do
    local choice
    choice="$(_menu_choose "$APP_NAME v$APP_VERSION" "Main menu" \\
      "overview" "Overview" \\
      "apt" "APT management" \\
      "benchmark" "Mirror benchmark" \\
      "backups" "Backup and Restore" \\
      "diagnostics" "Diagnostics" \\
      "settings" "Settings" \\
      "exit" "Exit")" || return 0
    case "$choice" in
      overview) _menu_overview ;;
      apt) _menu_apt ;;
      benchmark) _menu_benchmark ;;
      backups) _menu_backups ;;
      diagnostics) _menu_diagnostics ;;
      settings) _menu_settings ;;
      exit) return 0 ;;
    esac
  done
}

main() {
  _setup_colors
  _parse_args "$@"

  if [[ "$LOG_ENABLED" == true ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : >"$LOG_FILE"
    _log_to_file "Session started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  if [[ "$STATUS_REQUESTED" == true ]]; then
    _status_report
    exit "$EXIT_OK"
  fi

  if [[ "$DOCTOR_REQUESTED" == true ]]; then
    _doctor_report
    [[ "$REPORT_STATUS" != "error" ]] || exit "$EXIT_GENERAL"
    exit "$EXIT_OK"
  fi

  if [[ "$LIST_REQUESTED" == true ]]; then
    local list_status=0
    _run_list_flow || list_status=$?
    exit "$list_status"
  fi

  if [[ "$RESTORE" == true ]]; then
    local restore_status=0
    _run_restore_flow || restore_status=$?
    [[ "$restore_status" -eq "$EXIT_CANCELLED" ]] && restore_status="$EXIT_OK"
    exit "$restore_status"
  fi

  if [[ "$MENU_REQUESTED" == true ]]; then
    local menu_status=0
    _menu_main || menu_status=$?
    exit "$menu_status"
  fi

  if [[ "$ACTION_REQUESTED" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
    if _is_interactive; then
      _menu_main
      exit $?
    fi
    error "No command was selected. A non-interactive apply requires --yes; use --status, --doctor or --dry-run for read-only checks."
    exit "$EXIT_USAGE"
  fi

  local apply_status=0
  _run_apply_flow || apply_status=$?
  [[ "$apply_status" -eq "$EXIT_CANCELLED" ]] && apply_status="$EXIT_OK"
  exit "$apply_status"
}
if [[ "${POWER_APT_BOOST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
\b'/\\b}"
  value="${value//
}

_collect_status() {
  REPORT_OS_ID="unknown"
  REPORT_OS_PRETTY="unknown"
  REPORT_VERSION_ID="unknown"
  REPORT_CODENAME="unknown"
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$OS_RELEASE_FILE"
    REPORT_OS_ID="${ID:-unknown}"
    REPORT_OS_PRETTY="${PRETTY_NAME:-${ID:-unknown}}"
    REPORT_VERSION_ID="${VERSION_ID:-unknown}"
    REPORT_CODENAME="${VERSION_CODENAME:-unknown}"
  fi
  REPORT_SOURCES_LIST="absent"
  REPORT_DEB822="absent"
  REPORT_MANAGED_CONFIG="absent"
  [[ ! -e "$APT_SOURCES_FILE" ]] || REPORT_SOURCES_LIST="present"
  [[ ! -e "$APT_DEB822_FILE" ]] || REPORT_DEB822="present"
  [[ ! -e "$APT_CONF_FILE" ]] || REPORT_MANAGED_CONFIG="present"

  REPORT_CURRENT_MIRROR=""
  if [[ -r "$APT_DEB822_FILE" ]]; then
    REPORT_CURRENT_MIRROR="$(awk -F': ' '$1 == "URIs" {print $2; exit}' "$APT_DEB822_FILE" 2>/dev/null || true)"
    REPORT_CURRENT_MIRROR="$(printf '%s' "$REPORT_CURRENT_MIRROR" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g')"
  fi
  REPORT_BACKUP_ACCESSIBLE=false
  REPORT_BACKUP_COUNT=0
  REPORT_LATEST_BACKUP=""
  if [[ -d "$BACKUP_BASE" && -r "$BACKUP_BASE" ]]; then
    REPORT_BACKUP_ACCESSIBLE=true
    REPORT_BACKUP_COUNT="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]')"
    REPORT_LATEST_BACKUP="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
}

_print_status_report() {
  _collect_status
  printf '\n%s\n' "$APP_NAME — System Status"
  printf '%-24s %s\n' "Operating system:" "$REPORT_OS_PRETTY"
  printf '%-24s %s\n' "Ubuntu codename:" "$REPORT_CODENAME"
  printf '%-24s %s\n' "Legacy sources.list:" "$REPORT_SOURCES_LIST"
  printf '%-24s %s\n' "Deb822 ubuntu.sources:" "$REPORT_DEB822"
  printf '%-24s %s\n' "Managed APT config:" "$REPORT_MANAGED_CONFIG"
  printf '%-24s %s\n' "Current mirror:" "${REPORT_CURRENT_MIRROR:-not detected}"
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    printf '%-24s %s\n' "Available backups:" "$REPORT_BACKUP_COUNT"
    printf '%-24s %s\n' "Latest backup:" "${REPORT_LATEST_BACKUP:-none}"
  else
    printf '%-24s %s\n' "Backup directory:" "not accessible (root may be required)"
  fi
  printf '\n'
}

_doctor_add_check() {
  REPORT_CHECK_NAMES+=("$1")
  REPORT_CHECK_STATUSES+=("$2")
  REPORT_CHECK_DETAILS+=("$3")
  case "$2" in
    error) REPORT_STATUS="error" ;;
    warning)
      [[ "$REPORT_STATUS" == "error" ]] || REPORT_STATUS="warning"
      ;;
  esac
}

_doctor_collect() {
  _collect_status
  REPORT_CHECK_NAMES=()
  REPORT_CHECK_STATUSES=()
  REPORT_CHECK_DETAILS=()
  REPORT_STATUS="ok"
  if [[ "$REPORT_OS_ID" == "ubuntu" ]]; then
    _doctor_add_check "operating_system" "ok" "$REPORT_OS_PRETTY"
  else
    _doctor_add_check "operating_system" "error" "Ubuntu is required; detected $REPORT_OS_PRETTY"
  fi
  local cmd
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat find sort head cut chown mv rm sed; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _doctor_add_check "command:$cmd" "ok" "available"
    else
      _doctor_add_check "command:$cmd" "error" "missing required command"
    fi
  done
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    _doctor_add_check "http_client" "ok" "curl or wget is available"
  else
    _doctor_add_check "http_client" "error" "curl or wget is required"
  fi
  if [[ -f "$KEYRING_PATH" ]]; then
    _doctor_add_check "ubuntu_archive_keyring" "ok" "keyring exists"
  else
    _doctor_add_check "ubuntu_archive_keyring" "warning" "keyring not found at $KEYRING_PATH"
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    _doctor_add_check "privileges" "ok" "running as root"
  else
    _doctor_add_check "privileges" "warning" "root is required for apply and restore operations"
  fi
  if [[ -r "$APT_ETC_DIR" ]]; then
    _doctor_add_check "apt_configuration" "ok" "APT configuration directory is readable"
  else
    _doctor_add_check "apt_configuration" "warning" "APT configuration directory is not readable"
  fi
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    _doctor_add_check "backup_directory" "ok" "$REPORT_BACKUP_COUNT backup snapshot(s) visible"
  else
    _doctor_add_check "backup_directory" "warning" "backup directory is not currently accessible or has not been created"
  fi
}

_report_checks_json() {
  local i
  printf '['
  for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
    if ((i > 0)); then printf ','; fi
    printf '{"name":%s,"status":%s,"detail":%s}' "$(_json_quote "${REPORT_CHECK_NAMES[$i]}")" "$(_json_quote "${REPORT_CHECK_STATUSES[$i]}")" "$(_json_quote "${REPORT_CHECK_DETAILS[$i]}")"
  done
  printf ']'
}

_print_json() {
  _collect_status
  local checks_json
  checks_json="$(_report_checks_json)"
  printf '{\\n'
  printf '  "schema_version": 1,\\n'
  printf '  "version": %s,\\n' "$(_json_quote "$APP_VERSION")"
  printf '  "command": %s,\\n' "$(_json_quote "$REPORT_COMMAND")"
  printf '  "status": %s,\\n' "$(_json_quote "$REPORT_STATUS")"
  printf '  "timestamp": %s,\\n' "$(_json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "system": {"id": %s, "pretty_name": %s, "version_id": %s, "codename": %s},\\n' "$(_json_quote "$REPORT_OS_ID")" "$(_json_quote "$REPORT_OS_PRETTY")" "$(_json_quote "$REPORT_VERSION_ID")" "$(_json_quote "$REPORT_CODENAME")"
  printf '  "apt": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "current_mirror": %s},\\n' "$(_json_quote "$REPORT_SOURCES_LIST")" "$(_json_quote "$REPORT_DEB822")" "$(_json_quote "$REPORT_MANAGED_CONFIG")" "$(_json_quote "$REPORT_CURRENT_MIRROR")"
  printf '  "backups": {"accessible": %s, "count": %s, "latest": %s},\\n' "$REPORT_BACKUP_ACCESSIBLE" "$REPORT_BACKUP_COUNT" "$(_json_quote "$REPORT_LATEST_BACKUP")"
  printf '  "operation": {"mirror": %s, "response_time_seconds": %s, "dry_run": %s, "skip_update": %s},\\n' "$(_json_quote "$SELECTED_MIRROR")" "$(_json_quote "$SELECTED_TIME")" "$DRY_RUN" "$SKIP_UPDATE"
  printf '  "paths": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "backup_root": %s},\\n' "$(_json_quote "$APT_SOURCES_FILE")" "$(_json_quote "$APT_DEB822_FILE")" "$(_json_quote "$APT_CONF_FILE")" "$(_json_quote "$BACKUP_BASE")"
  printf '  "checks": %s\\n' "$checks_json"
  printf '}\\n'
}

_status_report() {
  _collect_status
  REPORT_COMMAND="status"
  REPORT_STATUS="ok"
  [[ "$REPORT_OS_ID" == "ubuntu" ]] || REPORT_STATUS="warning"
  if [[ "$JSON_OUTPUT" == true ]]; then _print_json; else _print_status_report; fi
}

_doctor_report() {
  _doctor_collect
  REPORT_COMMAND="doctor"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _print_json
  else
    printf '\n%s\n' "$APP_NAME — Diagnostics"
    local i
    for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
      printf '  %-8s %-28s %s\n' "${REPORT_CHECK_STATUSES[$i]}" "${REPORT_CHECK_NAMES[$i]}" "${REPORT_CHECK_DETAILS[$i]}"
    done
    printf '\nOverall status: %s\n\n' "$REPORT_STATUS"
  fi
}

_print_summary() {
  if [[ "$DRY_RUN" == true ]]; then
    cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_YELLOW}${COLOR_BOLD}DRY RUN COMPLETED${COLOR_RESET}

  Fastest mirror:  ${COLOR_BOLD}${SELECTED_MIRROR}${COLOR_RESET}
  Response time:   ${COLOR_BOLD}${SELECTED_TIME}s${COLOR_RESET}

  ${COLOR_DIM}No system changes were made.${COLOR_RESET}
${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
    return
  fi

  cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_GREEN}${COLOR_BOLD}SUCCESS — APT mirror optimized${COLOR_RESET}

  ${COLOR_BOLD}Mirror:${COLOR_RESET}  ${SELECTED_MIRROR}
  ${COLOR_BOLD}Speed:${COLOR_RESET}   ${SELECTED_TIME}s

  ${COLOR_DIM}Config files:${COLOR_RESET}
    ${APT_DEB822_FILE}
    ${APT_CONF_FILE}

  ${COLOR_DIM}To undo:${COLOR_RESET}
    ${COLOR_CYAN}sudo bash ${_SCRIPT_NAME} --restore${COLOR_RESET}

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
}

_print_banner() {
  if [[ "$QUIET" == true || "$JSON_OUTPUT" == true ]]; then return; fi
  cat <<'EOF'

██████   ██████  ██     ██ ███████ ██████       █████  ██████  ████████     ██████   ██████   ██████  ███████ ████████ 
██   ██ ██    ██ ██     ██ ██      ██   ██     ██   ██ ██   ██    ██        ██   ██ ██    ██ ██    ██ ██         ██    
██████  ██    ██ ██  █  ██ █████   ██████      ███████ ██████     ██        ██████  ██    ██ ██    ██ ███████    ██    
██      ██    ██ ██ ███ ██ ██      ██   ██     ██   ██ ██         ██        ██   ██ ██    ██ ██    ██      ██    ██    
██       ██████   ███ ███  ███████ ██   ██     ██   ██ ██         ██        ██████   ██████   ██████  ███████    ██    
                                                                                                                       
                                                                                                                       
EOF
  echo "" >&2
  printf '%b\n' "  ${COLOR_DIM}Fast Ubuntu APT mirror selector & network optimizer${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}v${APP_VERSION} · ${APP_LICENSE} · ${APP_AUTHOR}${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}${APP_GITHUB}${COLOR_RESET}" >&2
  echo "" >&2
}

_print_help() {
  cat <<EOF
${COLOR_BOLD}${COLOR_CYAN}Power APT Boost${COLOR_RESET} v${APP_VERSION}
Fast Ubuntu APT mirror selector and network optimizer

${COLOR_BOLD}${COLOR_BLUE}USAGE${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}                 # Open the interactive menu on a TTY
  sudo bash ${_SCRIPT_NAME} [OPTIONS]
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

${COLOR_BOLD}${COLOR_BLUE}OPTIONS${COLOR_RESET}
  ${COLOR_GREEN}-h, --help${COLOR_RESET}              Show this help message
  ${COLOR_GREEN}-v, --version${COLOR_RESET}           Show version information
  ${COLOR_GREEN}-m, --mirror URL${COLOR_RESET}        Use a specific Ubuntu mirror
  ${COLOR_GREEN}-r, --restore${COLOR_RESET}           Restore APT config from backup
  ${COLOR_GREEN}    --restore-path PATH${COLOR_RESET}   Restore from a specific backup
  ${COLOR_GREEN}    --dry-run${COLOR_RESET}            Test mirrors without changing config
  ${COLOR_GREEN}    --skip-update${COLOR_RESET}        Write config but skip apt-get update (preserve caches)
  ${COLOR_GREEN}    --list${COLOR_RESET}               List available mirrors and test them
  ${COLOR_GREEN}    --menu${COLOR_RESET}               Open the interactive terminal menu
  ${COLOR_GREEN}    --status${COLOR_RESET}             Show current system and APT status
  ${COLOR_GREEN}    --doctor${COLOR_RESET}             Run local dependency and configuration checks
  ${COLOR_GREEN}-y, --yes${COLOR_RESET}              Confirm changes in non-interactive mode
  ${COLOR_GREEN}    --json${COLOR_RESET}               Output reports using the stable JSON schema
  ${COLOR_GREEN}    --verbose${COLOR_RESET}             Show detailed output
  ${COLOR_GREEN}    --quiet${COLOR_RESET}               Suppress non-essential output
  ${COLOR_GREEN}    --no-spinner${COLOR_RESET}          Disable spinner (for CI/CD)
  ${COLOR_GREEN}    --timeout SECS${COLOR_RESET}        Probe timeout (default: 20)
  ${COLOR_GREEN}    --country CODE${COLOR_RESET}        Filter mirrors by country code
  ${COLOR_GREEN}    --ipv6${COLOR_RESET}                Use IPv6 for mirror testing
  ${COLOR_GREEN}    --log-file PATH${COLOR_RESET}       Write log to file

${COLOR_BOLD}${COLOR_BLUE}EXAMPLES${COLOR_RESET}
  ${COLOR_DIM}# Open the interactive menu${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}

  ${COLOR_DIM}# Apply automatically from a pipe or CI job${COLOR_RESET}
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

  ${COLOR_DIM}# Read-only status and diagnostics${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --status
  sudo bash ${_SCRIPT_NAME} --doctor

  ${COLOR_DIM}# Test without changing system config${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run

  ${COLOR_DIM}# Use a specific mirror${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Restore from latest backup${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore

  ${COLOR_DIM}# Machine-readable output for CI/CD pipelines${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --json --quiet

  ${COLOR_DIM}# List and test all available mirrors${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list

  ${COLOR_DIM}# Filter mirrors by country${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --country us

${COLOR_BOLD}${COLOR_BLUE}WHAT IT DOES${COLOR_RESET}
  1. Detects your Ubuntu version
  2. Tests multiple mirrors in parallel for speed
  3. Selects the fastest working mirror
  4. Backs up current APT configuration
  5. Writes optimized APT sources (deb822 format)
  6. Configures network optimizations (retries, timeouts)
  7. Preserves existing package lists and downloaded packages when --skip-update is selected
  8. Runs apt-get update unless --skip-update is selected

${COLOR_BOLD}${COLOR_BLUE}BACKUPS${COLOR_RESET}
  Location:  ${BACKUP_BASE}/
  Restore:   sudo bash ${_SCRIPT_NAME} --restore
  Or:        sudo bash ${_SCRIPT_NAME} --restore-path /var/backups/${APP_SLUG}/<timestamp>

${COLOR_BOLD}${COLOR_BLUE}EXIT CODES${COLOR_RESET}
  ${COLOR_GREEN}0${COLOR_RESET}  Success         ${COLOR_GREEN}4${COLOR_RESET}  Not running as root
  1  General error      5  Not Ubuntu
  2  Usage error        6  No working mirror found
  3  Network error      7  Backup failed
  4  Root required      8  Restore/rollback failed

${COLOR_BOLD}${COLOR_BLUE}AUTHOR${COLOR_RESET}
  ${APP_AUTHOR} · ${APP_GITHUB}
EOF
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        _print_help
        exit "$EXIT_OK"
        ;;
      -v | --version)
        printf '%s v%s\n' "$APP_NAME" "$APP_VERSION"
        exit "$EXIT_OK"
        ;;
      -m | --mirror)
        [[ -n "${2:-}" ]] || die "Option $1 requires a URL argument." "$EXIT_USAGE"
        FORCE_MIRROR="${2%/}"
        ACTION_REQUESTED=true
        shift 2
        ;;
      -r | --restore)
        RESTORE=true
        shift
        ;;
      --restore-path)
        [[ -n "${2:-}" ]] || die "Option $1 requires a backup path." "$EXIT_USAGE"
        RESTORE_PATH="$2"
        RESTORE=true
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        ACTION_REQUESTED=true
        shift
        ;;
      --skip-update)
        SKIP_UPDATE=true
        ACTION_REQUESTED=true
        shift
        ;;
      --list)
        LIST_REQUESTED=true
        shift
        ;;
      --menu)
        MENU_REQUESTED=true
        shift
        ;;
      --status)
        STATUS_REQUESTED=true
        shift
        ;;
      --doctor)
        DOCTOR_REQUESTED=true
        shift
        ;;
      -y | --yes)
        YES=true
        shift
        ;;
      --json)
        JSON_OUTPUT=true
        QUIET=true
        NO_SPINNER=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --quiet)
        QUIET=true
        shift
        ;;
      --no-spinner)
        NO_SPINNER=true
        shift
        ;;
      --timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires a positive integer." "$EXIT_USAGE"
        (($2 >= 1 && $2 <= 300)) || die "Option $1 must be between 1 and 300 seconds." "$EXIT_USAGE"
        TIMEOUT_TOTAL="$2"
        shift 2
        ;;
      --country)
        [[ "${2:-}" =~ ^[A-Za-z]{2}$ ]] || die "Option $1 requires a two-letter country code." "$EXIT_USAGE"
        COUNTRY_FILTER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
        shift 2
        ;;
      --ipv6)
        USE_IPV6=true
        shift
        ;;
      --log-file)
        [[ -n "${2:-}" ]] || die "Option $1 requires a file path." "$EXIT_USAGE"
        LOG_FILE="$2"
        LOG_ENABLED=true
        shift 2
        ;;
      -*)
        error "Unknown option: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
      *)
        error "Unexpected argument: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
    esac
  done

  local mode_count=0
  if [[ "$MENU_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$STATUS_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$DOCTOR_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$LIST_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$RESTORE" == true ]]; then ((mode_count += 1)); fi
  ((mode_count <= 1)) || die "Choose only one command mode: menu, status, doctor, list or restore." "$EXIT_USAGE"

  if [[ "$MENU_REQUESTED" == true ]]; then
    [[ "$YES" != true && "$JSON_OUTPUT" != true && "$ACTION_REQUESTED" != true ]] || die "--menu cannot be combined with apply, --yes or --json options." "$EXIT_USAGE"
  fi
  if [[ "$STATUS_REQUESTED" == true || "$DOCTOR_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--status and --doctor are read-only commands." "$EXIT_USAGE"
  fi
  if [[ "$LIST_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--list cannot be combined with apply options." "$EXIT_USAGE"
  fi
  if [[ "$RESTORE" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--restore cannot be combined with dry-run, skip-update or mirror selection." "$EXIT_USAGE"
  fi
}

_is_interactive() {
  [[ -t 0 && -t 1 ]]
}

_confirm_action() {
  local prompt="$1"
  local answer=""
  if [[ "$YES" == true ]]; then return 0; fi
  if ! _is_interactive; then
    error "Non-interactive changes require --yes. Use --dry-run to preview without applying."
    return "$EXIT_USAGE"
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer || answer=""
  case "${answer,,}" in
    y | yes) return 0 ;;
    *) info "Cancelled. No system changes were made."; return 10 ;;
  esac
}

_print_apply_preview() {
  _print_section_header "CHANGE PREVIEW"
  printf 'Selected mirror: %s\n' "$SELECTED_MIRROR"
  printf 'APT source file: %s\n' "$APT_DEB822_FILE"
  printf 'APT network config: %s\n' "$APT_CONF_FILE"
  printf 'Backup root: %s\n' "$BACKUP_BASE"
  if [[ -f "$APT_SOURCES_FILE" ]]; then
    printf 'Legacy sources.list: may be removed if it contains only Ubuntu archive entries (%s)\n' "$APT_SOURCES_FILE"
  fi
  if [[ "$SKIP_UPDATE" == true ]]; then
    printf 'APT update: skipped; existing package lists and archive cache are preserved\n'
  else
    printf 'APT update: apt-get update will run after configuration changes\n'
  fi
}

_confirm_apply() {
  [[ "$DRY_RUN" == true ]] && return 0
  _print_apply_preview
  _confirm_action "Apply this APT mirror configuration?"
}

_confirm_restore() {
  local backup_path="$1"
  _print_section_header "RESTORE PREVIEW"
  printf 'Snapshot: %s\n' "$backup_path"
  printf 'Managed targets restored exactly: %s, %s, %s\n' "$APT_SOURCES_FILE" "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'APT update: apt-get update will run after restoration\n'
  _confirm_action "Restore this snapshot?"
}

_resolve_backup_path() {
  local backup_path="$1"
  if [[ -z "$backup_path" && -d "$BACKUP_BASE" ]]; then
    backup_path="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    local legacy_root="${_SYSTEM_ROOT}/root"
    if [[ -d "$legacy_root" ]]; then
      backup_path="$(find "$legacy_root" -maxdepth 1 -name 'apt-backup-*' -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
    fi
  fi
  [[ -n "$backup_path" && -d "$backup_path" ]] || return "$EXIT_RESTORE"
  printf '%s\n' "$backup_path"
}

_menu_choose() {
  local title="$1"
  local prompt="$2"
  shift 2
  local -a tags=() labels=() whiptail_args=()
  while (($# >= 2)); do
    tags+=("$1")
    labels+=("$2")
    whiptail_args+=("$1" "$2")
    shift 2
  done

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --menu "$prompt" 22 78 12 "${whiptail_args[@]}" 3>&1 1>&2 2>&3
    return $?
  fi

  printf '\n%s\n%s\n' "$title" "$prompt" >&2
  local i
  for ((i = 0; i < ${#tags[@]}; i++)); do
    printf '  %d) %s\n' "$((i + 1))" "${labels[$i]}" >&2
  done
  printf 'Select an option: ' >&2
  local answer=""
  IFS= read -r answer || return 1
  if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#tags[@]})); then
    printf '%s\n' "${tags[$((answer - 1))]}"
    return 0
  fi
  for ((i = 0; i < ${#tags[@]}; i++)); do
    if [[ "$answer" == "${tags[$i]}" ]]; then
      printf '%s\n' "${tags[$i]}"
      return 0
    fi
  done
  return 1
}

_menu_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local answer=""
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default_value" 3>&1 1>&2 2>&3
    return $?
  fi
  printf '%s [%s]: ' "$prompt" "$default_value" >&2
  IFS= read -r answer || return 1
  printf '%s\n' "${answer:-$default_value}"
}

_menu_message() {
  local title="$1"
  local message="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --msgbox "$message" 16 78
  else
    printf '\n%s\n%s\n' "$title" "$message" >&2
    printf 'Press Enter to continue: ' >&2
    local ignored=""
    IFS= read -r ignored || true
  fi
}

_run_list_flow() {
  _check_probe_tool
  detect_ubuntu
  if [[ "$JSON_OUTPUT" == true ]]; then
    list_mirrors >&2
    REPORT_COMMAND="list"
    REPORT_STATUS="complete"
    _collect_status
    REPORT_CHECK_NAMES=("mirror_catalog")
    REPORT_CHECK_STATUSES=("complete")
    REPORT_CHECK_DETAILS=("Mirror reachability checks completed; see stderr for detailed results")
    _print_json
  else
    list_mirrors
  fi
}

_run_benchmark_only() {
  _check_probe_tool
  detect_ubuntu
  SELECTED_MIRROR=""
  SELECTED_TIME=""
  _select_mirror
  printf '\nSelected mirror: %s\nProbe time: %ss\n\n' "$SELECTED_MIRROR" "$SELECTED_TIME"
}

_run_apply_flow() {
  if [[ "$DRY_RUN" != true && "$YES" != true ]] && ! _is_interactive; then
    error "Applying APT changes from a non-interactive session requires --yes. Use --dry-run to preview."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi

  _print_banner
  _check_commands
  _check_probe_tool
  detect_ubuntu
  if [[ "$DRY_RUN" != true ]]; then _acquire_mutation_lock; fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    _print_section_header "TESTING SPECIFIED MIRROR"
    msg "  Mirror: ${COLOR_BOLD}${FORCE_MIRROR}${COLOR_RESET}"
    local result_file rtime rstatus
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.force.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$FORCE_MIRROR" "$result_file" "$CODENAME"
    rtime="$(awk '{print $1}' "$result_file")"
    rstatus="$(awk '{print $2}' "$result_file")"
    rm -f "$result_file" 2>/dev/null || true
    if [[ "$rstatus" == "pass" ]]; then
      SELECTED_MIRROR="$FORCE_MIRROR"
      SELECTED_TIME="$rtime"
    else
      error "Mirror is not reachable: $FORCE_MIRROR"
      return "$EXIT_NO_MIRROR"
    fi
  else
    _select_mirror
  fi

  if [[ "$DRY_RUN" != true ]]; then
    local confirm_status=0
    _confirm_apply || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi
  fi

  REPORT_COMMAND="apply"
  REPORT_STATUS="success"
  [[ "$DRY_RUN" == true ]] && REPORT_STATUS="dry_run"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _apply_changes >&2
    _print_json
  else
    _apply_changes
    _print_summary
  fi
}

_run_restore_flow() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Restoring APT configuration from a non-interactive session requires --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  _check_commands

  local selected_backup confirm_status=0
  if ! selected_backup="$(_resolve_backup_path "$RESTORE_PATH")"; then
    error "No backup snapshot was found."
    return "$EXIT_RESTORE"
  fi
  _confirm_restore "$selected_backup" || confirm_status=$?
  if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi

  _acquire_mutation_lock
  REPORT_COMMAND="restore"
  REPORT_STATUS="success"
  SELECTED_MIRROR="restored"
  SELECTED_TIME=""
  if [[ "$JSON_OUTPUT" == true ]]; then
    _restore_backup "$selected_backup" >&2 || return "$EXIT_RESTORE"
    apt-get update >&2 || return "$EXIT_NETWORK"
    _print_json
  else
    _restore_backup "$selected_backup" || return "$EXIT_RESTORE"
    apt-get update || return "$EXIT_NETWORK"
    info "APT sources restored and updated successfully."
  fi
}

_menu_overview() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    _status_report
  else
    _print_status_report
    _menu_message "Overview" "System status refreshed."
  fi
}

_menu_apt() {
  local choice rc
  while true; do
    choice="$(_menu_choose "APT Management" "Choose an action" \\
      "apply_best" "Find and apply the fastest mirror" \\
      "apply_custom" "Test and apply a custom mirror" \\
      "list" "List and test available mirrors" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      apply_best)
        FORCE_MIRROR=""
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      apply_custom)
        FORCE_MIRROR="$(_menu_input "Custom mirror" "Enter an Ubuntu mirror base URL" "")" || continue
        [[ "$FORCE_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || {
          _menu_message "Invalid mirror URL" "Enter an http:// or https:// URL without spaces."
          continue
        }
        FORCE_MIRROR="${FORCE_MIRROR%/}"
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      list)
        _run_list_flow
        _menu_message "APT mirrors" "Mirror testing completed."
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_benchmark() {
  _run_benchmark_only
  _menu_message "Benchmark" "Benchmark completed. No system configuration was changed."
}

_menu_backups() {
  if [[ "$(id -u)" -ne 0 ]]; then
    _menu_message "Backup and Restore" "Run the menu as root to inspect protected system backups."
    return 0
  fi
  local listing
  listing="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn || true)"
  if [[ -z "$listing" ]]; then
    _menu_message "Backup and Restore" "No Power APT Boost backup snapshots were found."
    return 0
  fi
  local -a args=()
  local line path
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    args+=("$path" "${path##*/}")
  done <<<"$listing"
  local selected rc
  selected="$(_menu_choose "Backup and Restore" "Select a snapshot to restore" "${args[@]}" "back" "Back")" || return 0
  [[ "$selected" == back ]] && return 0
  RESTORE_PATH="$selected"
  rc=0
  _run_restore_flow || rc=$?
  [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Restore result" "Restore finished with exit code $rc."
}

_menu_diagnostics() {
  local choice
  choice="$(_menu_choose "Diagnostics" "Choose a report" \\
    "status" "System status" \\
    "doctor" "Run local health checks" \\
    "back" "Back to main menu")" || return 0
  case "$choice" in
    status)
      _status_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Status report completed."
      ;;
    doctor)
      _doctor_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Health checks completed."
      ;;
    back) return 0 ;;
  esac
}

_country_code_supported() {
  local requested="$1" entry country mirror_url
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r country _ mirror_url <<<"$entry"
    [[ "$country" != "$requested" ]] || return 0
  done
  return 1
}

_menu_settings() {
  local choice value
  while true; do
    choice="$(_menu_choose "Settings" "Settings apply to this session only" \\
      "timeout" "Probe timeout: ${TIMEOUT_TOTAL}s" \\
      "country" "Country filter: ${COUNTRY_FILTER:-all}" \\
      "ipv6" "IP family: $([[ "$USE_IPV6" == true ]] && echo IPv6 || echo IPv4)" \\
      "spinner" "Spinner: $([[ "$NO_SPINNER" == true ]] && echo disabled || echo enabled)" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      timeout)
        value="$(_menu_input "Probe timeout" "Enter timeout in seconds (1-300)" "$TIMEOUT_TOTAL")" || continue
        if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 300)); then
          TIMEOUT_TOTAL="$value"
        else
          _menu_message "Invalid timeout" "Enter a whole number from 1 to 300."
        fi
        ;;
      country)
        value="$(_menu_input "Country filter" "Enter a supported two-letter country code, or leave empty for all" "$COUNTRY_FILTER")" || continue
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$value" ]]; then
          COUNTRY_FILTER=""
        elif [[ "$value" =~ ^[a-z]{2}$ ]] && _country_code_supported "$value"; then
          COUNTRY_FILTER="$value"
        else
          _menu_message "Unsupported country" "Choose a country code present in the built-in mirror catalog."
        fi
        ;;
      ipv6)
        [[ "$USE_IPV6" == true ]] && USE_IPV6=false || USE_IPV6=true
        ;;
      spinner)
        [[ "$NO_SPINNER" == true ]] && NO_SPINNER=false || NO_SPINNER=true
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_main() {
  if ! _is_interactive; then
    error "The interactive menu requires a TTY. Use --help for non-interactive commands."
    return "$EXIT_USAGE"
  fi
  while true; do
    local choice
    choice="$(_menu_choose "$APP_NAME v$APP_VERSION" "Main menu" \\
      "overview" "Overview" \\
      "apt" "APT management" \\
      "benchmark" "Mirror benchmark" \\
      "backups" "Backup and Restore" \\
      "diagnostics" "Diagnostics" \\
      "settings" "Settings" \\
      "exit" "Exit")" || return 0
    case "$choice" in
      overview) _menu_overview ;;
      apt) _menu_apt ;;
      benchmark) _menu_benchmark ;;
      backups) _menu_backups ;;
      diagnostics) _menu_diagnostics ;;
      settings) _menu_settings ;;
      exit) return 0 ;;
    esac
  done
}

main() {
  _setup_colors
  _parse_args "$@"

  if [[ "$LOG_ENABLED" == true ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : >"$LOG_FILE"
    _log_to_file "Session started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  if [[ "$STATUS_REQUESTED" == true ]]; then
    _status_report
    exit "$EXIT_OK"
  fi

  if [[ "$DOCTOR_REQUESTED" == true ]]; then
    _doctor_report
    [[ "$REPORT_STATUS" != "error" ]] || exit "$EXIT_GENERAL"
    exit "$EXIT_OK"
  fi

  if [[ "$LIST_REQUESTED" == true ]]; then
    local list_status=0
    _run_list_flow || list_status=$?
    exit "$list_status"
  fi

  if [[ "$RESTORE" == true ]]; then
    local restore_status=0
    _run_restore_flow || restore_status=$?
    [[ "$restore_status" -eq "$EXIT_CANCELLED" ]] && restore_status="$EXIT_OK"
    exit "$restore_status"
  fi

  if [[ "$MENU_REQUESTED" == true ]]; then
    local menu_status=0
    _menu_main || menu_status=$?
    exit "$menu_status"
  fi

  if [[ "$ACTION_REQUESTED" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
    if _is_interactive; then
      _menu_main
      exit $?
    fi
    error "No command was selected. A non-interactive apply requires --yes; use --status, --doctor or --dry-run for read-only checks."
    exit "$EXIT_USAGE"
  fi

  local apply_status=0
  _run_apply_flow || apply_status=$?
  [[ "$apply_status" -eq "$EXIT_CANCELLED" ]] && apply_status="$EXIT_OK"
  exit "$apply_status"
}
if [[ "${POWER_APT_BOOST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
\f'/\\f}"
  printf '"%s"' "$value"
}

_collect_status() {
  REPORT_OS_ID="unknown"
  REPORT_OS_PRETTY="unknown"
  REPORT_VERSION_ID="unknown"
  REPORT_CODENAME="unknown"
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$OS_RELEASE_FILE"
    REPORT_OS_ID="${ID:-unknown}"
    REPORT_OS_PRETTY="${PRETTY_NAME:-${ID:-unknown}}"
    REPORT_VERSION_ID="${VERSION_ID:-unknown}"
    REPORT_CODENAME="${VERSION_CODENAME:-unknown}"
  fi
  REPORT_SOURCES_LIST="absent"
  REPORT_DEB822="absent"
  REPORT_MANAGED_CONFIG="absent"
  [[ ! -e "$APT_SOURCES_FILE" ]] || REPORT_SOURCES_LIST="present"
  [[ ! -e "$APT_DEB822_FILE" ]] || REPORT_DEB822="present"
  [[ ! -e "$APT_CONF_FILE" ]] || REPORT_MANAGED_CONFIG="present"

  REPORT_CURRENT_MIRROR=""
  if [[ -r "$APT_DEB822_FILE" ]]; then
    REPORT_CURRENT_MIRROR="$(awk -F': ' '$1 == "URIs" {print $2; exit}' "$APT_DEB822_FILE" 2>/dev/null || true)"
    REPORT_CURRENT_MIRROR="$(printf '%s' "$REPORT_CURRENT_MIRROR" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g')"
  fi
  REPORT_BACKUP_ACCESSIBLE=false
  REPORT_BACKUP_COUNT=0
  REPORT_LATEST_BACKUP=""
  if [[ -d "$BACKUP_BASE" && -r "$BACKUP_BASE" ]]; then
    REPORT_BACKUP_ACCESSIBLE=true
    REPORT_BACKUP_COUNT="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]')"
    REPORT_LATEST_BACKUP="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
}

_print_status_report() {
  _collect_status
  printf '\n%s\n' "$APP_NAME — System Status"
  printf '%-24s %s\n' "Operating system:" "$REPORT_OS_PRETTY"
  printf '%-24s %s\n' "Ubuntu codename:" "$REPORT_CODENAME"
  printf '%-24s %s\n' "Legacy sources.list:" "$REPORT_SOURCES_LIST"
  printf '%-24s %s\n' "Deb822 ubuntu.sources:" "$REPORT_DEB822"
  printf '%-24s %s\n' "Managed APT config:" "$REPORT_MANAGED_CONFIG"
  printf '%-24s %s\n' "Current mirror:" "${REPORT_CURRENT_MIRROR:-not detected}"
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    printf '%-24s %s\n' "Available backups:" "$REPORT_BACKUP_COUNT"
    printf '%-24s %s\n' "Latest backup:" "${REPORT_LATEST_BACKUP:-none}"
  else
    printf '%-24s %s\n' "Backup directory:" "not accessible (root may be required)"
  fi
  printf '\n'
}

_doctor_add_check() {
  REPORT_CHECK_NAMES+=("$1")
  REPORT_CHECK_STATUSES+=("$2")
  REPORT_CHECK_DETAILS+=("$3")
  case "$2" in
    error) REPORT_STATUS="error" ;;
    warning)
      [[ "$REPORT_STATUS" == "error" ]] || REPORT_STATUS="warning"
      ;;
  esac
}

_doctor_collect() {
  _collect_status
  REPORT_CHECK_NAMES=()
  REPORT_CHECK_STATUSES=()
  REPORT_CHECK_DETAILS=()
  REPORT_STATUS="ok"
  if [[ "$REPORT_OS_ID" == "ubuntu" ]]; then
    _doctor_add_check "operating_system" "ok" "$REPORT_OS_PRETTY"
  else
    _doctor_add_check "operating_system" "error" "Ubuntu is required; detected $REPORT_OS_PRETTY"
  fi
  local cmd
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat find sort head cut chown mv rm sed; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _doctor_add_check "command:$cmd" "ok" "available"
    else
      _doctor_add_check "command:$cmd" "error" "missing required command"
    fi
  done
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    _doctor_add_check "http_client" "ok" "curl or wget is available"
  else
    _doctor_add_check "http_client" "error" "curl or wget is required"
  fi
  if [[ -f "$KEYRING_PATH" ]]; then
    _doctor_add_check "ubuntu_archive_keyring" "ok" "keyring exists"
  else
    _doctor_add_check "ubuntu_archive_keyring" "warning" "keyring not found at $KEYRING_PATH"
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    _doctor_add_check "privileges" "ok" "running as root"
  else
    _doctor_add_check "privileges" "warning" "root is required for apply and restore operations"
  fi
  if [[ -r "$APT_ETC_DIR" ]]; then
    _doctor_add_check "apt_configuration" "ok" "APT configuration directory is readable"
  else
    _doctor_add_check "apt_configuration" "warning" "APT configuration directory is not readable"
  fi
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    _doctor_add_check "backup_directory" "ok" "$REPORT_BACKUP_COUNT backup snapshot(s) visible"
  else
    _doctor_add_check "backup_directory" "warning" "backup directory is not currently accessible or has not been created"
  fi
}

_report_checks_json() {
  local i
  printf '['
  for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
    if ((i > 0)); then printf ','; fi
    printf '{"name":%s,"status":%s,"detail":%s}' "$(_json_quote "${REPORT_CHECK_NAMES[$i]}")" "$(_json_quote "${REPORT_CHECK_STATUSES[$i]}")" "$(_json_quote "${REPORT_CHECK_DETAILS[$i]}")"
  done
  printf ']'
}

_print_json() {
  _collect_status
  local checks_json
  checks_json="$(_report_checks_json)"
  printf '{\\n'
  printf '  "schema_version": 1,\\n'
  printf '  "version": %s,\\n' "$(_json_quote "$APP_VERSION")"
  printf '  "command": %s,\\n' "$(_json_quote "$REPORT_COMMAND")"
  printf '  "status": %s,\\n' "$(_json_quote "$REPORT_STATUS")"
  printf '  "timestamp": %s,\\n' "$(_json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "system": {"id": %s, "pretty_name": %s, "version_id": %s, "codename": %s},\\n' "$(_json_quote "$REPORT_OS_ID")" "$(_json_quote "$REPORT_OS_PRETTY")" "$(_json_quote "$REPORT_VERSION_ID")" "$(_json_quote "$REPORT_CODENAME")"
  printf '  "apt": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "current_mirror": %s},\\n' "$(_json_quote "$REPORT_SOURCES_LIST")" "$(_json_quote "$REPORT_DEB822")" "$(_json_quote "$REPORT_MANAGED_CONFIG")" "$(_json_quote "$REPORT_CURRENT_MIRROR")"
  printf '  "backups": {"accessible": %s, "count": %s, "latest": %s},\\n' "$REPORT_BACKUP_ACCESSIBLE" "$REPORT_BACKUP_COUNT" "$(_json_quote "$REPORT_LATEST_BACKUP")"
  printf '  "operation": {"mirror": %s, "response_time_seconds": %s, "dry_run": %s, "skip_update": %s},\\n' "$(_json_quote "$SELECTED_MIRROR")" "$(_json_quote "$SELECTED_TIME")" "$DRY_RUN" "$SKIP_UPDATE"
  printf '  "paths": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "backup_root": %s},\\n' "$(_json_quote "$APT_SOURCES_FILE")" "$(_json_quote "$APT_DEB822_FILE")" "$(_json_quote "$APT_CONF_FILE")" "$(_json_quote "$BACKUP_BASE")"
  printf '  "checks": %s\\n' "$checks_json"
  printf '}\\n'
}

_status_report() {
  _collect_status
  REPORT_COMMAND="status"
  REPORT_STATUS="ok"
  [[ "$REPORT_OS_ID" == "ubuntu" ]] || REPORT_STATUS="warning"
  if [[ "$JSON_OUTPUT" == true ]]; then _print_json; else _print_status_report; fi
}

_doctor_report() {
  _doctor_collect
  REPORT_COMMAND="doctor"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _print_json
  else
    printf '\n%s\n' "$APP_NAME — Diagnostics"
    local i
    for ((i = 0; i < ${#REPORT_CHECK_NAMES[@]}; i++)); do
      printf '  %-8s %-28s %s\n' "${REPORT_CHECK_STATUSES[$i]}" "${REPORT_CHECK_NAMES[$i]}" "${REPORT_CHECK_DETAILS[$i]}"
    done
    printf '\nOverall status: %s\n\n' "$REPORT_STATUS"
  fi
}

_print_summary() {
  if [[ "$DRY_RUN" == true ]]; then
    cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_YELLOW}${COLOR_BOLD}DRY RUN COMPLETED${COLOR_RESET}

  Fastest mirror:  ${COLOR_BOLD}${SELECTED_MIRROR}${COLOR_RESET}
  Response time:   ${COLOR_BOLD}${SELECTED_TIME}s${COLOR_RESET}

  ${COLOR_DIM}No system changes were made.${COLOR_RESET}
${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
    return
  fi

  cat <<EOF

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}
  ${COLOR_GREEN}${COLOR_BOLD}SUCCESS — APT mirror optimized${COLOR_RESET}

  ${COLOR_BOLD}Mirror:${COLOR_RESET}  ${SELECTED_MIRROR}
  ${COLOR_BOLD}Speed:${COLOR_RESET}   ${SELECTED_TIME}s

  ${COLOR_DIM}Config files:${COLOR_RESET}
    ${APT_DEB822_FILE}
    ${APT_CONF_FILE}

  ${COLOR_DIM}To undo:${COLOR_RESET}
    ${COLOR_CYAN}sudo bash ${_SCRIPT_NAME} --restore${COLOR_RESET}

${COLOR_BOLD}════════════════════════════════════════════════════════════${COLOR_RESET}

EOF
}

_print_banner() {
  if [[ "$QUIET" == true || "$JSON_OUTPUT" == true ]]; then return; fi
  cat <<'EOF'

██████   ██████  ██     ██ ███████ ██████       █████  ██████  ████████     ██████   ██████   ██████  ███████ ████████ 
██   ██ ██    ██ ██     ██ ██      ██   ██     ██   ██ ██   ██    ██        ██   ██ ██    ██ ██    ██ ██         ██    
██████  ██    ██ ██  █  ██ █████   ██████      ███████ ██████     ██        ██████  ██    ██ ██    ██ ███████    ██    
██      ██    ██ ██ ███ ██ ██      ██   ██     ██   ██ ██         ██        ██   ██ ██    ██ ██    ██      ██    ██    
██       ██████   ███ ███  ███████ ██   ██     ██   ██ ██         ██        ██████   ██████   ██████  ███████    ██    
                                                                                                                       
                                                                                                                       
EOF
  echo "" >&2
  printf '%b\n' "  ${COLOR_DIM}Fast Ubuntu APT mirror selector & network optimizer${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}v${APP_VERSION} · ${APP_LICENSE} · ${APP_AUTHOR}${COLOR_RESET}" >&2
  printf '%b\n' "  ${COLOR_DIM}${APP_GITHUB}${COLOR_RESET}" >&2
  echo "" >&2
}

_print_help() {
  cat <<EOF
${COLOR_BOLD}${COLOR_CYAN}Power APT Boost${COLOR_RESET} v${APP_VERSION}
Fast Ubuntu APT mirror selector and network optimizer

${COLOR_BOLD}${COLOR_BLUE}USAGE${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}                 # Open the interactive menu on a TTY
  sudo bash ${_SCRIPT_NAME} [OPTIONS]
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

${COLOR_BOLD}${COLOR_BLUE}OPTIONS${COLOR_RESET}
  ${COLOR_GREEN}-h, --help${COLOR_RESET}              Show this help message
  ${COLOR_GREEN}-v, --version${COLOR_RESET}           Show version information
  ${COLOR_GREEN}-m, --mirror URL${COLOR_RESET}        Use a specific Ubuntu mirror
  ${COLOR_GREEN}-r, --restore${COLOR_RESET}           Restore APT config from backup
  ${COLOR_GREEN}    --restore-path PATH${COLOR_RESET}   Restore from a specific backup
  ${COLOR_GREEN}    --dry-run${COLOR_RESET}            Test mirrors without changing config
  ${COLOR_GREEN}    --skip-update${COLOR_RESET}        Write config but skip apt-get update (preserve caches)
  ${COLOR_GREEN}    --list${COLOR_RESET}               List available mirrors and test them
  ${COLOR_GREEN}    --menu${COLOR_RESET}               Open the interactive terminal menu
  ${COLOR_GREEN}    --status${COLOR_RESET}             Show current system and APT status
  ${COLOR_GREEN}    --doctor${COLOR_RESET}             Run local dependency and configuration checks
  ${COLOR_GREEN}-y, --yes${COLOR_RESET}              Confirm changes in non-interactive mode
  ${COLOR_GREEN}    --json${COLOR_RESET}               Output reports using the stable JSON schema
  ${COLOR_GREEN}    --verbose${COLOR_RESET}             Show detailed output
  ${COLOR_GREEN}    --quiet${COLOR_RESET}               Suppress non-essential output
  ${COLOR_GREEN}    --no-spinner${COLOR_RESET}          Disable spinner (for CI/CD)
  ${COLOR_GREEN}    --timeout SECS${COLOR_RESET}        Probe timeout (default: 20)
  ${COLOR_GREEN}    --country CODE${COLOR_RESET}        Filter mirrors by country code
  ${COLOR_GREEN}    --ipv6${COLOR_RESET}                Use IPv6 for mirror testing
  ${COLOR_GREEN}    --log-file PATH${COLOR_RESET}       Write log to file

${COLOR_BOLD}${COLOR_BLUE}EXAMPLES${COLOR_RESET}
  ${COLOR_DIM}# Open the interactive menu${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME}

  ${COLOR_DIM}# Apply automatically from a pipe or CI job${COLOR_RESET}
  curl -fsSL ${APP_GITHUB}/raw/main/power-apt-boost.sh | sudo bash -s -- --yes

  ${COLOR_DIM}# Read-only status and diagnostics${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --status
  sudo bash ${_SCRIPT_NAME} --doctor

  ${COLOR_DIM}# Test without changing system config${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run

  ${COLOR_DIM}# Use a specific mirror${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Restore from latest backup${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore

  ${COLOR_DIM}# Machine-readable output for CI/CD pipelines${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --json --quiet

  ${COLOR_DIM}# List and test all available mirrors${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list

  ${COLOR_DIM}# Filter mirrors by country${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --country us

${COLOR_BOLD}${COLOR_BLUE}WHAT IT DOES${COLOR_RESET}
  1. Detects your Ubuntu version
  2. Tests multiple mirrors in parallel for speed
  3. Selects the fastest working mirror
  4. Backs up current APT configuration
  5. Writes optimized APT sources (deb822 format)
  6. Configures network optimizations (retries, timeouts)
  7. Preserves existing package lists and downloaded packages when --skip-update is selected
  8. Runs apt-get update unless --skip-update is selected

${COLOR_BOLD}${COLOR_BLUE}BACKUPS${COLOR_RESET}
  Location:  ${BACKUP_BASE}/
  Restore:   sudo bash ${_SCRIPT_NAME} --restore
  Or:        sudo bash ${_SCRIPT_NAME} --restore-path /var/backups/${APP_SLUG}/<timestamp>

${COLOR_BOLD}${COLOR_BLUE}EXIT CODES${COLOR_RESET}
  ${COLOR_GREEN}0${COLOR_RESET}  Success         ${COLOR_GREEN}4${COLOR_RESET}  Not running as root
  1  General error      5  Not Ubuntu
  2  Usage error        6  No working mirror found
  3  Network error      7  Backup failed
  4  Root required      8  Restore/rollback failed

${COLOR_BOLD}${COLOR_BLUE}AUTHOR${COLOR_RESET}
  ${APP_AUTHOR} · ${APP_GITHUB}
EOF
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        _print_help
        exit "$EXIT_OK"
        ;;
      -v | --version)
        printf '%s v%s\n' "$APP_NAME" "$APP_VERSION"
        exit "$EXIT_OK"
        ;;
      -m | --mirror)
        [[ -n "${2:-}" ]] || die "Option $1 requires a URL argument." "$EXIT_USAGE"
        FORCE_MIRROR="${2%/}"
        ACTION_REQUESTED=true
        shift 2
        ;;
      -r | --restore)
        RESTORE=true
        shift
        ;;
      --restore-path)
        [[ -n "${2:-}" ]] || die "Option $1 requires a backup path." "$EXIT_USAGE"
        RESTORE_PATH="$2"
        RESTORE=true
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        ACTION_REQUESTED=true
        shift
        ;;
      --skip-update)
        SKIP_UPDATE=true
        ACTION_REQUESTED=true
        shift
        ;;
      --list)
        LIST_REQUESTED=true
        shift
        ;;
      --menu)
        MENU_REQUESTED=true
        shift
        ;;
      --status)
        STATUS_REQUESTED=true
        shift
        ;;
      --doctor)
        DOCTOR_REQUESTED=true
        shift
        ;;
      -y | --yes)
        YES=true
        shift
        ;;
      --json)
        JSON_OUTPUT=true
        QUIET=true
        NO_SPINNER=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --quiet)
        QUIET=true
        shift
        ;;
      --no-spinner)
        NO_SPINNER=true
        shift
        ;;
      --timeout)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires a positive integer." "$EXIT_USAGE"
        (($2 >= 1 && $2 <= 300)) || die "Option $1 must be between 1 and 300 seconds." "$EXIT_USAGE"
        TIMEOUT_TOTAL="$2"
        shift 2
        ;;
      --country)
        [[ "${2:-}" =~ ^[A-Za-z]{2}$ ]] || die "Option $1 requires a two-letter country code." "$EXIT_USAGE"
        COUNTRY_FILTER="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
        shift 2
        ;;
      --ipv6)
        USE_IPV6=true
        shift
        ;;
      --log-file)
        [[ -n "${2:-}" ]] || die "Option $1 requires a file path." "$EXIT_USAGE"
        LOG_FILE="$2"
        LOG_ENABLED=true
        shift 2
        ;;
      -*)
        error "Unknown option: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
      *)
        error "Unexpected argument: $1. Run --help for usage."
        exit "$EXIT_USAGE"
        ;;
    esac
  done

  local mode_count=0
  if [[ "$MENU_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$STATUS_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$DOCTOR_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$LIST_REQUESTED" == true ]]; then ((mode_count += 1)); fi
  if [[ "$RESTORE" == true ]]; then ((mode_count += 1)); fi
  ((mode_count <= 1)) || die "Choose only one command mode: menu, status, doctor, list or restore." "$EXIT_USAGE"

  if [[ "$MENU_REQUESTED" == true ]]; then
    [[ "$YES" != true && "$JSON_OUTPUT" != true && "$ACTION_REQUESTED" != true ]] || die "--menu cannot be combined with apply, --yes or --json options." "$EXIT_USAGE"
  fi
  if [[ "$STATUS_REQUESTED" == true || "$DOCTOR_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--status and --doctor are read-only commands." "$EXIT_USAGE"
  fi
  if [[ "$LIST_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--list cannot be combined with apply options." "$EXIT_USAGE"
  fi
  if [[ "$RESTORE" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" ]] || die "--restore cannot be combined with dry-run, skip-update or mirror selection." "$EXIT_USAGE"
  fi
}

_is_interactive() {
  [[ -t 0 && -t 1 ]]
}

_confirm_action() {
  local prompt="$1"
  local answer=""
  if [[ "$YES" == true ]]; then return 0; fi
  if ! _is_interactive; then
    error "Non-interactive changes require --yes. Use --dry-run to preview without applying."
    return "$EXIT_USAGE"
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer || answer=""
  case "${answer,,}" in
    y | yes) return 0 ;;
    *) info "Cancelled. No system changes were made."; return 10 ;;
  esac
}

_print_apply_preview() {
  _print_section_header "CHANGE PREVIEW"
  printf 'Selected mirror: %s\n' "$SELECTED_MIRROR"
  printf 'APT source file: %s\n' "$APT_DEB822_FILE"
  printf 'APT network config: %s\n' "$APT_CONF_FILE"
  printf 'Backup root: %s\n' "$BACKUP_BASE"
  if [[ -f "$APT_SOURCES_FILE" ]]; then
    printf 'Legacy sources.list: may be removed if it contains only Ubuntu archive entries (%s)\n' "$APT_SOURCES_FILE"
  fi
  if [[ "$SKIP_UPDATE" == true ]]; then
    printf 'APT update: skipped; existing package lists and archive cache are preserved\n'
  else
    printf 'APT update: apt-get update will run after configuration changes\n'
  fi
}

_confirm_apply() {
  [[ "$DRY_RUN" == true ]] && return 0
  _print_apply_preview
  _confirm_action "Apply this APT mirror configuration?"
}

_confirm_restore() {
  local backup_path="$1"
  _print_section_header "RESTORE PREVIEW"
  printf 'Snapshot: %s\n' "$backup_path"
  printf 'Managed targets restored exactly: %s, %s, %s\n' "$APT_SOURCES_FILE" "$APT_SOURCES_DIR" "$APT_CONF_DIR"
  printf 'APT update: apt-get update will run after restoration\n'
  _confirm_action "Restore this snapshot?"
}

_resolve_backup_path() {
  local backup_path="$1"
  if [[ -z "$backup_path" && -d "$BACKUP_BASE" ]]; then
    backup_path="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
  fi
  if [[ -z "$backup_path" || ! -d "$backup_path" ]]; then
    local legacy_root="${_SYSTEM_ROOT}/root"
    if [[ -d "$legacy_root" ]]; then
      backup_path="$(find "$legacy_root" -maxdepth 1 -name 'apt-backup-*' -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)"
    fi
  fi
  [[ -n "$backup_path" && -d "$backup_path" ]] || return "$EXIT_RESTORE"
  printf '%s\n' "$backup_path"
}

_menu_choose() {
  local title="$1"
  local prompt="$2"
  shift 2
  local -a tags=() labels=() whiptail_args=()
  while (($# >= 2)); do
    tags+=("$1")
    labels+=("$2")
    whiptail_args+=("$1" "$2")
    shift 2
  done

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --menu "$prompt" 22 78 12 "${whiptail_args[@]}" 3>&1 1>&2 2>&3
    return $?
  fi

  printf '\n%s\n%s\n' "$title" "$prompt" >&2
  local i
  for ((i = 0; i < ${#tags[@]}; i++)); do
    printf '  %d) %s\n' "$((i + 1))" "${labels[$i]}" >&2
  done
  printf 'Select an option: ' >&2
  local answer=""
  IFS= read -r answer || return 1
  if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#tags[@]})); then
    printf '%s\n' "${tags[$((answer - 1))]}"
    return 0
  fi
  for ((i = 0; i < ${#tags[@]}; i++)); do
    if [[ "$answer" == "${tags[$i]}" ]]; then
      printf '%s\n' "${tags[$i]}"
      return 0
    fi
  done
  return 1
}

_menu_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local answer=""
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --inputbox "$prompt" 10 78 "$default_value" 3>&1 1>&2 2>&3
    return $?
  fi
  printf '%s [%s]: ' "$prompt" "$default_value" >&2
  IFS= read -r answer || return 1
  printf '%s\n' "${answer:-$default_value}"
}

_menu_message() {
  local title="$1"
  local message="$2"
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "$title" --msgbox "$message" 16 78
  else
    printf '\n%s\n%s\n' "$title" "$message" >&2
    printf 'Press Enter to continue: ' >&2
    local ignored=""
    IFS= read -r ignored || true
  fi
}

_run_list_flow() {
  _check_probe_tool
  detect_ubuntu
  if [[ "$JSON_OUTPUT" == true ]]; then
    list_mirrors >&2
    REPORT_COMMAND="list"
    REPORT_STATUS="complete"
    _collect_status
    REPORT_CHECK_NAMES=("mirror_catalog")
    REPORT_CHECK_STATUSES=("complete")
    REPORT_CHECK_DETAILS=("Mirror reachability checks completed; see stderr for detailed results")
    _print_json
  else
    list_mirrors
  fi
}

_run_benchmark_only() {
  _check_probe_tool
  detect_ubuntu
  SELECTED_MIRROR=""
  SELECTED_TIME=""
  _select_mirror
  printf '\nSelected mirror: %s\nProbe time: %ss\n\n' "$SELECTED_MIRROR" "$SELECTED_TIME"
}

_run_apply_flow() {
  if [[ "$DRY_RUN" != true && "$YES" != true ]] && ! _is_interactive; then
    error "Applying APT changes from a non-interactive session requires --yes. Use --dry-run to preview."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi

  _print_banner
  _check_commands
  _check_probe_tool
  detect_ubuntu
  if [[ "$DRY_RUN" != true ]]; then _acquire_mutation_lock; fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    _print_section_header "TESTING SPECIFIED MIRROR"
    msg "  Mirror: ${COLOR_BOLD}${FORCE_MIRROR}${COLOR_RESET}"
    local result_file rtime rstatus
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.force.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$FORCE_MIRROR" "$result_file" "$CODENAME"
    rtime="$(awk '{print $1}' "$result_file")"
    rstatus="$(awk '{print $2}' "$result_file")"
    rm -f "$result_file" 2>/dev/null || true
    if [[ "$rstatus" == "pass" ]]; then
      SELECTED_MIRROR="$FORCE_MIRROR"
      SELECTED_TIME="$rtime"
    else
      error "Mirror is not reachable: $FORCE_MIRROR"
      return "$EXIT_NO_MIRROR"
    fi
  else
    _select_mirror
  fi

  if [[ "$DRY_RUN" != true ]]; then
    local confirm_status=0
    _confirm_apply || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi
  fi

  REPORT_COMMAND="apply"
  REPORT_STATUS="success"
  [[ "$DRY_RUN" == true ]] && REPORT_STATUS="dry_run"
  if [[ "$JSON_OUTPUT" == true ]]; then
    _apply_changes >&2
    _print_json
  else
    _apply_changes
    _print_summary
  fi
}

_run_restore_flow() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Restoring APT configuration from a non-interactive session requires --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "This operation must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  _check_commands

  local selected_backup confirm_status=0
  if ! selected_backup="$(_resolve_backup_path "$RESTORE_PATH")"; then
    error "No backup snapshot was found."
    return "$EXIT_RESTORE"
  fi
  _confirm_restore "$selected_backup" || confirm_status=$?
  if [[ "$confirm_status" -ne 0 ]]; then return "$confirm_status"; fi

  _acquire_mutation_lock
  REPORT_COMMAND="restore"
  REPORT_STATUS="success"
  SELECTED_MIRROR="restored"
  SELECTED_TIME=""
  if [[ "$JSON_OUTPUT" == true ]]; then
    _restore_backup "$selected_backup" >&2 || return "$EXIT_RESTORE"
    apt-get update >&2 || return "$EXIT_NETWORK"
    _print_json
  else
    _restore_backup "$selected_backup" || return "$EXIT_RESTORE"
    apt-get update || return "$EXIT_NETWORK"
    info "APT sources restored and updated successfully."
  fi
}

_menu_overview() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    _status_report
  else
    _print_status_report
    _menu_message "Overview" "System status refreshed."
  fi
}

_menu_apt() {
  local choice rc
  while true; do
    choice="$(_menu_choose "APT Management" "Choose an action" \\
      "apply_best" "Find and apply the fastest mirror" \\
      "apply_custom" "Test and apply a custom mirror" \\
      "list" "List and test available mirrors" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      apply_best)
        FORCE_MIRROR=""
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      apply_custom)
        FORCE_MIRROR="$(_menu_input "Custom mirror" "Enter an Ubuntu mirror base URL" "")" || continue
        [[ "$FORCE_MIRROR" =~ ^https?://[^[:space:]]+$ ]] || {
          _menu_message "Invalid mirror URL" "Enter an http:// or https:// URL without spaces."
          continue
        }
        FORCE_MIRROR="${FORCE_MIRROR%/}"
        DRY_RUN=false
        rc=0
        _run_apply_flow || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Operation result" "Operation finished with exit code $rc."
        ;;
      list)
        _run_list_flow
        _menu_message "APT mirrors" "Mirror testing completed."
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_benchmark() {
  _run_benchmark_only
  _menu_message "Benchmark" "Benchmark completed. No system configuration was changed."
}

_menu_backups() {
  if [[ "$(id -u)" -ne 0 ]]; then
    _menu_message "Backup and Restore" "Run the menu as root to inspect protected system backups."
    return 0
  fi
  local listing
  listing="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn || true)"
  if [[ -z "$listing" ]]; then
    _menu_message "Backup and Restore" "No Power APT Boost backup snapshots were found."
    return 0
  fi
  local -a args=()
  local line path
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    args+=("$path" "${path##*/}")
  done <<<"$listing"
  local selected rc
  selected="$(_menu_choose "Backup and Restore" "Select a snapshot to restore" "${args[@]}" "back" "Back")" || return 0
  [[ "$selected" == back ]] && return 0
  RESTORE_PATH="$selected"
  rc=0
  _run_restore_flow || rc=$?
  [[ "$rc" -eq 0 || "$rc" -eq 10 ]] || _menu_message "Restore result" "Restore finished with exit code $rc."
}

_menu_diagnostics() {
  local choice
  choice="$(_menu_choose "Diagnostics" "Choose a report" \\
    "status" "System status" \\
    "doctor" "Run local health checks" \\
    "back" "Back to main menu")" || return 0
  case "$choice" in
    status)
      _status_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Status report completed."
      ;;
    doctor)
      _doctor_report
      [[ "$JSON_OUTPUT" == true ]] || _menu_message "Diagnostics" "Health checks completed."
      ;;
    back) return 0 ;;
  esac
}

_country_code_supported() {
  local requested="$1" entry country mirror_url
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r country _ mirror_url <<<"$entry"
    [[ "$country" != "$requested" ]] || return 0
  done
  return 1
}

_menu_settings() {
  local choice value
  while true; do
    choice="$(_menu_choose "Settings" "Settings apply to this session only" \\
      "timeout" "Probe timeout: ${TIMEOUT_TOTAL}s" \\
      "country" "Country filter: ${COUNTRY_FILTER:-all}" \\
      "ipv6" "IP family: $([[ "$USE_IPV6" == true ]] && echo IPv6 || echo IPv4)" \\
      "spinner" "Spinner: $([[ "$NO_SPINNER" == true ]] && echo disabled || echo enabled)" \\
      "back" "Back to main menu")" || return 0
    case "$choice" in
      timeout)
        value="$(_menu_input "Probe timeout" "Enter timeout in seconds (1-300)" "$TIMEOUT_TOTAL")" || continue
        if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 300)); then
          TIMEOUT_TOTAL="$value"
        else
          _menu_message "Invalid timeout" "Enter a whole number from 1 to 300."
        fi
        ;;
      country)
        value="$(_menu_input "Country filter" "Enter a supported two-letter country code, or leave empty for all" "$COUNTRY_FILTER")" || continue
        value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$value" ]]; then
          COUNTRY_FILTER=""
        elif [[ "$value" =~ ^[a-z]{2}$ ]] && _country_code_supported "$value"; then
          COUNTRY_FILTER="$value"
        else
          _menu_message "Unsupported country" "Choose a country code present in the built-in mirror catalog."
        fi
        ;;
      ipv6)
        [[ "$USE_IPV6" == true ]] && USE_IPV6=false || USE_IPV6=true
        ;;
      spinner)
        [[ "$NO_SPINNER" == true ]] && NO_SPINNER=false || NO_SPINNER=true
        ;;
      back) return 0 ;;
    esac
  done
}

_menu_main() {
  if ! _is_interactive; then
    error "The interactive menu requires a TTY. Use --help for non-interactive commands."
    return "$EXIT_USAGE"
  fi
  while true; do
    local choice
    choice="$(_menu_choose "$APP_NAME v$APP_VERSION" "Main menu" \\
      "overview" "Overview" \\
      "apt" "APT management" \\
      "benchmark" "Mirror benchmark" \\
      "backups" "Backup and Restore" \\
      "diagnostics" "Diagnostics" \\
      "settings" "Settings" \\
      "exit" "Exit")" || return 0
    case "$choice" in
      overview) _menu_overview ;;
      apt) _menu_apt ;;
      benchmark) _menu_benchmark ;;
      backups) _menu_backups ;;
      diagnostics) _menu_diagnostics ;;
      settings) _menu_settings ;;
      exit) return 0 ;;
    esac
  done
}

main() {
  _setup_colors
  _parse_args "$@"

  if [[ "$LOG_ENABLED" == true ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : >"$LOG_FILE"
    _log_to_file "Session started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  if [[ "$STATUS_REQUESTED" == true ]]; then
    _status_report
    exit "$EXIT_OK"
  fi

  if [[ "$DOCTOR_REQUESTED" == true ]]; then
    _doctor_report
    [[ "$REPORT_STATUS" != "error" ]] || exit "$EXIT_GENERAL"
    exit "$EXIT_OK"
  fi

  if [[ "$LIST_REQUESTED" == true ]]; then
    local list_status=0
    _run_list_flow || list_status=$?
    exit "$list_status"
  fi

  if [[ "$RESTORE" == true ]]; then
    local restore_status=0
    _run_restore_flow || restore_status=$?
    [[ "$restore_status" -eq "$EXIT_CANCELLED" ]] && restore_status="$EXIT_OK"
    exit "$restore_status"
  fi

  if [[ "$MENU_REQUESTED" == true ]]; then
    local menu_status=0
    _menu_main || menu_status=$?
    exit "$menu_status"
  fi

  if [[ "$ACTION_REQUESTED" != true && "$YES" != true && "$DRY_RUN" != true ]]; then
    if _is_interactive; then
      _menu_main
      exit $?
    fi
    error "No command was selected. A non-interactive apply requires --yes; use --status, --doctor or --dry-run for read-only checks."
    exit "$EXIT_USAGE"
  fi

  local apply_status=0
  _run_apply_flow || apply_status=$?
  [[ "$apply_status" -eq "$EXIT_CANCELLED" ]] && apply_status="$EXIT_OK"
  exit "$apply_status"
}
if [[ "${POWER_APT_BOOST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
