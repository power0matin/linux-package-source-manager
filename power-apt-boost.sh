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
readonly MIRROR_INDEX_URL="http://mirrors.ubuntu.com/mirrors.txt"
readonly MIRROR_CATALOG_SCHEMA=1
readonly CATALOG_CACHE_TTL=86400
readonly CATALOG_MAX_RELEASE_AGE=604800
readonly CATALOG_CACHE_FILE="${_SYSTEM_ROOT}/var/cache/${APP_SLUG}/ubuntu-index-v1.tsv"
readonly USER_MIRRORS_FILE="${_SYSTEM_ROOT}/etc/${APP_SLUG}/custom-mirrors-v1.tsv"
readonly MAX_WORKERS_LIMIT=8
readonly DEFAULT_BENCH_WORKERS=8

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
BENCH_WORKERS="$DEFAULT_BENCH_WORKERS"
PROBE_RETRIES=1
APT_RETRIES=3
APT_PROXY=""
CLEAR_APT_PROXY=false
RESTORE_SCOPE="all"
PRUNE_BACKUPS_KEEP=""
NETWORK_DIAGNOSTICS=false
OFFICIAL_ONLY=false
REFRESH_CATALOG=false
NO_CATALOG_NETWORK=false
MIRROR_MANAGEMENT_REQUESTED=false
MIRROR_MANAGEMENT_ACTION=""
MIRROR_MANAGEMENT_VALUE=""
CATALOG_SOURCE="built-in"
CATALOG_CACHE_STATE="missing"
CATALOG_LAST_REFRESH=""
CATALOG_INVALID_ENTRIES=0
_CATALOG_IDS=()
_CATALOG_COUNTRIES=()
_CATALOG_REGIONS=()
_CATALOG_URLS=()
_CATALOG_SOURCES=()
_CATALOG_OFFICIAL=()
_CATALOG_ENABLED=()
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
REPORT_SOURCE_COUNT=0
REPORT_UBUNTU_SOURCE_COUNT=0
REPORT_THIRD_PARTY_SOURCE_COUNT=0
REPORT_DUPLICATE_SOURCE_COUNT=0
APT_SOURCE_TOTAL=0
APT_SOURCE_UBUNTU=0
APT_SOURCE_THIRD_PARTY=0
APT_SOURCE_DUPLICATES=0
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
  for cmd in apt-get awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat gpgv; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%b\n' "\n  ${COLOR_RED}${COLOR_BOLD}ERROR:${COLOR_RESET} ${COLOR_RED}Missing required commands:${COLOR_RESET}\n" >&2
    printf '  %s\n' "${missing[*]}" >&2
    printf '%b\n' "  ${COLOR_DIM}Fix:${COLOR_RESET} These utilities are required for APT backup and signed Ubuntu mirror verification." >&2
    printf '%b\n' "  Try: ${COLOR_CYAN}apt-get install -y coreutils gawk grep gnupg${COLOR_RESET}" >&2
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
  "ir-archive|ir|Iran|https://ir.archive.ubuntu.com/ubuntu|builtin|true|true"
  "ir-arvancloud|ir|Iran|https://mirror.arvancloud.ir/ubuntu|builtin|false|true"
  "ir-iranserver|ir|Iran|https://mirror.iranserver.com/ubuntu|builtin|false|true"
  "ir-hostiran|ir|Iran|https://ubuntu.hostiran.ir/ubuntu|builtin|false|true"
  "ir-hostbaran|ir|Iran|https://mirror.hostbaran.com/ubuntu|builtin|false|true"
  "ir-aminidc|ir|Iran|https://mirror.aminidc.com/ubuntu|builtin|false|true"
  "ir-ito|ir|Iran|https://archive.ito.gov.ir/ubuntu|builtin|false|true"
  "ir-petiak|ir|Iran|https://archive.ubuntu.petiak.ir/ubuntu|builtin|false|true"
  "ir-mobinhost|ir|Iran|https://mirror.mobinhost.com/ubuntu|builtin|false|true"
  "ir-linuxmirrors|ir|Iran|https://linuxmirrors.ir/ubuntu|builtin|false|true"
  "ir-kubarcloud|ir|Iran|https://mirror.kubarcloud.com/ubuntu|builtin|false|true"
  "global-archive|global|Global|https://archive.ubuntu.com/ubuntu|builtin|true|true"
  "global-ports|global|Global|https://ports.ubuntu.com/ubuntu-ports|builtin|true|true"
  "global-kernel|global|Global|https://mirrors.kernel.org/ubuntu|builtin|false|true"
  "us-archive|us|United States|https://us.archive.ubuntu.com/ubuntu|builtin|true|true"
  "us-princeton|us|United States|https://mirror.math.princeton.edu/pub/ubuntu|builtin|false|true"
  "us-uchicago|us|United States|https://mirror.cs.uchicago.edu/ubuntu|builtin|false|true"
  "ca-waterloo|ca|Canada|https://mirror.csclub.uwaterloo.ca/ubuntu|builtin|false|true"
  "us-rit|us|United States|https://mirror.rit.edu/ubuntu|builtin|false|true"
  "us-arizona|us|United States|https://mirror.arizona.edu/ubuntu|builtin|false|true"
  "gb-archive|gb|United Kingdom|https://gb.archive.ubuntu.com/ubuntu|builtin|true|true"
  "de-archive|de|Germany|https://de.archive.ubuntu.com/ubuntu|builtin|true|true"
  "fr-archive|fr|France|https://fr.archive.ubuntu.com/ubuntu|builtin|true|true"
  "it-archive|it|Italy|https://it.archive.ubuntu.com/ubuntu|builtin|true|true"
  "nl-archive|nl|Netherlands|https://nl.archive.ubuntu.com/ubuntu|builtin|true|true"
  "au-archive|au|Australia|https://au.archive.ubuntu.com/ubuntu|builtin|true|true"
  "jp-archive|jp|Japan|https://jp.archive.ubuntu.com/ubuntu|builtin|true|true"
  "kr-archive|kr|South Korea|https://kr.archive.ubuntu.com/ubuntu|builtin|true|true"
  "in-archive|in|India|https://in.archive.ubuntu.com/ubuntu|builtin|true|true"
  "br-archive|br|Brazil|https://br.archive.ubuntu.com/ubuntu|builtin|true|true"
)

_validate_mirror_url() {
  local url="${1%/}" authority path
  [[ "$url" != *'|'* && "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 1
  [[ "$url" != *'@'* && "$url" != *'?'* && "$url" != *'#'* ]] || return 1
  [[ "$url" =~ ^https?://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] || return 1
  authority="${url#*://}"
  authority="${authority%%/*}"
  [[ -n "$authority" && "$authority" != .* && "$authority" != *..* ]] || return 1
  path="/${url#*://}"
  path="/${path#*/}"
  [[ "$path" == */ubuntu || "$path" == */ubuntu-ports ]] || return 1
  [[ "$path" != *"/../"* && "$path" != *"/./"* ]] || return 1
  printf '%s\n' "$url"
}

_catalog_entry_valid() {
  local id="$1" country="$2" region="$3" url="$4" source="$5" official="$6" enabled="$7"
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return 1
  [[ "$country" =~ ^(global|auto|[a-z]{2})$ ]] || return 1
  [[ -n "$region" && "$region" != *'|'* && "$region" != *$'\n'* ]] || return 1
  _validate_mirror_url "$url" >/dev/null || return 1
  case "$source" in
  builtin | ubuntu-index | user) ;;
  *) return 1 ;;
  esac
  [[ "$official" == true || "$official" == false ]] || return 1
  [[ "$enabled" == true || "$enabled" == false ]] || return 1
  [[ "$source" != user || "$official" == false ]] || return 1
}

_catalog_add_entry() {
  local id="$1" country="$2" region="$3" url="$4" source="$5" official="$6" enabled="$7"
  local normalized existing
  if ! normalized="$(_validate_mirror_url "$url")" ||
    ! _catalog_entry_valid "$id" "$country" "$region" "$normalized" "$source" "$official" "$enabled"; then
    ((CATALOG_INVALID_ENTRIES += 1)) || true
    return 1
  fi
  for existing in "${_CATALOG_URLS[@]}"; do
    [[ "$existing" != "$normalized" ]] || return 0
  done
  _CATALOG_IDS+=("$id")
  _CATALOG_COUNTRIES+=("$country")
  _CATALOG_REGIONS+=("$region")
  _CATALOG_URLS+=("$normalized")
  _CATALOG_SOURCES+=("$source")
  _CATALOG_OFFICIAL+=("$official")
  _CATALOG_ENABLED+=("$enabled")
}

_catalog_read_file() {
  local file="$1" expected_source="$2"
  [[ -f "$file" && -r "$file" ]] || return 0
  local line id country region url source official enabled extra
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    IFS='|' read -r id country region url source official enabled extra <<<"$line"
    if [[ -n "${extra:-}" || "$source" != "$expected_source" ]]; then
      ((CATALOG_INVALID_ENTRIES += 1)) || true
      continue
    fi
    _catalog_add_entry "$id" "$country" "$region" "$url" "$source" "$official" "$enabled" || true
  done <"$file"
}

_validate_https_redirect_headers() {
  local headers_file="$1" target
  while IFS= read -r target; do
    [[ "$target" == https://* ]] || return 1
  done < <(awk 'tolower($1) == "location:" {print $2}' "$headers_file")
}

_download_catalog_file() {
  local destination="$1" headers_file
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout "$PROBE_TIMEOUT_CONNECT" --max-time "$TIMEOUT_TOTAL" \
      --proto '=http,https' --proto-redir '=https' -o "$destination" "$MIRROR_INDEX_URL"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    headers_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.index-headers.XXXXXX")" || return 1
    if wget --server-response --timeout="$TIMEOUT_TOTAL" --tries=1 --max-redirect=5 \
      -O "$destination" "$MIRROR_INDEX_URL" >/dev/null 2>"$headers_file"; then
      if _validate_https_redirect_headers "$headers_file"; then
        rm -f "$headers_file"
        return 0
      fi
    fi
    rm -f "$headers_file" "$destination"
    return 1
  fi
  return 1
}

_refresh_catalog_cache() {
  local download_file cache_tmp accepted=0 url host hash id row
  local -a discovered=()
  local -A seen_urls=()
  download_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.index.XXXXXX")" || return 1
  if ! _download_catalog_file "$download_file"; then
    rm -f "$download_file"
    return 1
  fi

  while IFS= read -r url || [[ -n "$url" ]]; do
    url="$(printf '%s' "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$url" && "$url" != \#* ]] || continue
    if ! url="$(_validate_mirror_url "$url")"; then
      ((CATALOG_INVALID_ENTRIES += 1)) || true
      continue
    fi
    [[ -z "${seen_urls[$url]+x}" ]] || continue
    seen_urls["$url"]=1
    host="${url#*://}"
    host="${host%%/*}"
    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
    hash="$(printf '%s' "$url" | sha256sum | cut -c1-10)"
    id="ubuntu-index-${host:0:32}-${hash}"
    discovered+=("$id|auto|Ubuntu-selected|$url|ubuntu-index|false|true")
    ((accepted += 1))
  done <"$download_file"
  rm -f "$download_file"
  ((accepted > 0)) || return 1

  for row in "${discovered[@]}"; do
    IFS='|' read -r id country region url source official enabled <<<"$row"
    _catalog_add_entry "$id" "$country" "$region" "$url" "$source" "$official" "$enabled" || true
  done

  if ! mkdir -p "$(dirname "$CATALOG_CACHE_FILE")"; then
    CATALOG_CACHE_STATE="discovered-uncached"
    CATALOG_LAST_REFRESH="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    return 0
  fi
  chmod 0700 "$(dirname "$CATALOG_CACHE_FILE")" 2>/dev/null || true
  cache_tmp="$(mktemp "${CATALOG_CACHE_FILE}.tmp.XXXXXX")" || {
    CATALOG_CACHE_STATE="discovered-uncached"
    return 0
  }
  {
    printf '# power-apt-boost-catalog-v%s\n' "$MIRROR_CATALOG_SCHEMA"
    printf '# fetched_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\n' "${discovered[@]}"
  } >"$cache_tmp" || {
    rm -f "$cache_tmp"
    CATALOG_CACHE_STATE="discovered-uncached"
    return 0
  }
  chmod 0600 "$cache_tmp" || {
    rm -f "$cache_tmp"
    CATALOG_CACHE_STATE="discovered-uncached"
    return 0
  }
  mv -f -- "$cache_tmp" "$CATALOG_CACHE_FILE" || {
    rm -f "$cache_tmp"
    CATALOG_CACHE_STATE="discovered-uncached"
    return 0
  }
  CATALOG_CACHE_STATE="refreshed"
  CATALOG_LAST_REFRESH="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ "$CATALOG_SOURCE" == "built-in" ]]; then
    CATALOG_SOURCE="built-in+ubuntu-index"
  elif [[ "$CATALOG_SOURCE" == "built-in+user" ]]; then
    CATALOG_SOURCE="built-in+user+ubuntu-index"
  fi
  return 0
}

_load_mirror_catalog() {
  _CATALOG_IDS=()
  _CATALOG_COUNTRIES=()
  _CATALOG_REGIONS=()
  _CATALOG_URLS=()
  _CATALOG_SOURCES=()
  _CATALOG_OFFICIAL=()
  _CATALOG_ENABLED=()
  CATALOG_INVALID_ENTRIES=0
  CATALOG_SOURCE="built-in"
  CATALOG_CACHE_STATE="missing"
  CATALOG_LAST_REFRESH=""

  local entry id country region url source official enabled
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r id country region url source official enabled <<<"$entry"
    _catalog_add_entry "$id" "$country" "$region" "$url" "$source" "$official" "$enabled" || true
  done

  if [[ -f "$USER_MIRRORS_FILE" ]]; then
    local before_user_count="${#_CATALOG_IDS[@]}"
    _catalog_read_file "$USER_MIRRORS_FILE" "user"
    if (("${#_CATALOG_IDS[@]}" > before_user_count)); then
      CATALOG_SOURCE="built-in+user"
    fi
  fi

  local cache_age=999999999 now cache_mtime cache_timestamp="" cache_valid=false
  if [[ -f "$CATALOG_CACHE_FILE" && ! -L "$CATALOG_CACHE_FILE" ]] &&
    grep -Fqx "# power-apt-boost-catalog-v$MIRROR_CATALOG_SCHEMA" "$CATALOG_CACHE_FILE"; then
    cache_valid=true
    cache_mtime="$(stat -c '%Y' "$CATALOG_CACHE_FILE" 2>/dev/null || printf '0')"
    now="$(date +%s)"
    cache_age=$((now - cache_mtime))
    ((cache_age >= 0)) || cache_age=999999999
    cache_timestamp="$(sed -n 's/^# fetched_at=//p' "$CATALOG_CACHE_FILE" | head -1)"
  elif [[ -e "$CATALOG_CACHE_FILE" || -L "$CATALOG_CACHE_FILE" ]]; then
    CATALOG_CACHE_STATE="invalid-cache"
    warn "Ignoring an invalid mirror catalog cache; schema or file type is not supported."
  fi

  if [[ "$NO_CATALOG_NETWORK" == true ]]; then
    if [[ "$cache_valid" == true ]]; then
      CATALOG_CACHE_STATE="local-cache"
      CATALOG_LAST_REFRESH="$cache_timestamp"
    else
      [[ "$CATALOG_CACHE_STATE" == "invalid-cache" ]] || CATALOG_CACHE_STATE="network-disabled"
    fi
  elif [[ "$REFRESH_CATALOG" == true || "$cache_valid" != true || "$cache_age" -gt "$CATALOG_CACHE_TTL" ]]; then
    if [[ -z "$COUNTRY_FILTER" ]] && _refresh_catalog_cache; then
      :
    elif [[ "$cache_valid" == true ]]; then
      CATALOG_CACHE_STATE="stale-fallback"
      CATALOG_LAST_REFRESH="$cache_timestamp"
      warn "Ubuntu mirror discovery failed; using the last known-good catalog cache."
    else
      [[ "$CATALOG_CACHE_STATE" == "invalid-cache" ]] || CATALOG_CACHE_STATE="unavailable"
      warn "Ubuntu mirror discovery is unavailable; using the built-in and user mirror catalog."
    fi
  elif [[ "$cache_valid" == true ]]; then
    CATALOG_CACHE_STATE="fresh-cache"
    CATALOG_LAST_REFRESH="$cache_timestamp"
  fi

  REFRESH_CATALOG=false

  if [[ "$cache_valid" == true ]]; then
    local before_dynamic_count="${#_CATALOG_IDS[@]}"
    _catalog_read_file "$CATALOG_CACHE_FILE" "ubuntu-index"
    if (("${#_CATALOG_IDS[@]}" > before_dynamic_count)); then
      [[ "$CATALOG_SOURCE" == built-in ]] && CATALOG_SOURCE="built-in+ubuntu-index"
      [[ "$CATALOG_SOURCE" == built-in+user ]] && CATALOG_SOURCE="built-in+user+ubuntu-index"
    fi
  elif [[ "$CATALOG_CACHE_STATE" == discovered-uncached ]]; then
    CATALOG_SOURCE="built-in+ubuntu-index"
  fi
  CATALOG_SOURCE="schema-v${MIRROR_CATALOG_SCHEMA}:${CATALOG_SOURCE}"
}

_get_mirrors() {
  local -a mirrors=()
  local i found_country=false existing country_lower
  country_lower="$(printf '%s' "$COUNTRY_FILTER" | tr '[:upper:]' '[:lower:]')"

  for i in "${!_CATALOG_URLS[@]}"; do
    [[ "${_CATALOG_ENABLED[$i]}" == true ]] || continue
    if _uses_ports_archive; then
      [[ "${_CATALOG_URLS[$i]}" == */ubuntu-ports ]] || continue
    else
      [[ "${_CATALOG_URLS[$i]}" != */ubuntu-ports ]] || continue
    fi
    if [[ "$OFFICIAL_ONLY" == true && "${_CATALOG_OFFICIAL[$i]}" != true ]]; then continue; fi
    if [[ -n "$country_lower" && "${_CATALOG_COUNTRIES[$i]}" != "$country_lower" ]]; then continue; fi
    mirrors+=("${_CATALOG_URLS[$i]}")
    [[ "${_CATALOG_COUNTRIES[$i]}" != "$country_lower" ]] || found_country=true
  done

  if [[ -n "$country_lower" && "$found_country" != true ]]; then
    die "No enabled mirrors are available for country code: $COUNTRY_FILTER" "$EXIT_USAGE"
  fi

  if [[ -n "$FORCE_MIRROR" ]]; then
    local forced_url
    forced_url="$(_validate_mirror_url "$FORCE_MIRROR")" || die "Invalid mirror URL: $FORCE_MIRROR" "$EXIT_USAGE"
    local found_forced=false
    for existing in "${mirrors[@]}"; do
      [[ "$existing" != "$forced_url" ]] || found_forced=true
    done
    if [[ "$found_forced" != true ]]; then
      [[ "$OFFICIAL_ONLY" != true ]] || die "The manually supplied mirror is not verified as official." "$EXIT_USAGE"
      mirrors=("$forced_url" "${mirrors[@]}")
    fi
  fi
  printf '%s\n' "${mirrors[@]}"
}

_catalog_metadata_for_url() {
  local requested_url="$1" i
  for i in "${!_CATALOG_URLS[@]}"; do
    if [[ "${_CATALOG_URLS[$i]}" == "$requested_url" ]]; then
      printf '%s\t%s\t%s\t%s\n' "${_CATALOG_IDS[$i]}" "${_CATALOG_SOURCES[$i]}" "${_CATALOG_OFFICIAL[$i]}" "${_CATALOG_COUNTRIES[$i]}"
      return 0
    fi
  done
  printf 'manual\tmanual\tfalse\tauto\n'
}

list_mirrors() {
  detect_ubuntu
  _load_mirror_catalog
  _print_section_header "AVAILABLE MIRRORS"
  local mirror_url result_file result_line eligible score avg_latency main_code updates_code security_code redirects freshness signature reason
  local meta mirror_id source official country
  while IFS= read -r mirror_url; do
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.list.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$mirror_url" "$result_file" "$CODENAME"
    result_line="$(cat "$result_file" 2>/dev/null || true)"
    rm -f "$result_file" 2>/dev/null || true
    IFS='|' read -r eligible score avg_latency main_code updates_code security_code redirects freshness signature reason <<<"$result_line"
    meta="$(_catalog_metadata_for_url "$mirror_url")"
    IFS=$'\t' read -r mirror_id source official country <<<"$meta"
    if [[ "$eligible" == true ]]; then
      printf '  %-24s PASS avg=%ss score=%ss redirects=%s freshness=%s signature=%s source=%s official=%s\n' \
        "$mirror_id" "$avg_latency" "$score" "$redirects" "$freshness" "$signature" "$source" "$official" >&2
    else
      printf '  %-24s REJECTED reason=%s source=%s official=%s\n' \
        "$mirror_id" "${reason:-incompatible_release}" "$source" "$official" >&2
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
_validate_release_metadata() {
  local body="$1" expected_codename="$2" expected_suite="$3"
  local origin label suite codename release_date valid_until now release_epoch valid_until_epoch
  origin="$(awk -F': *' '$1 == "Origin" {print $2; exit}' "$body")"
  label="$(awk -F': *' '$1 == "Label" {print $2; exit}' "$body")"
  suite="$(awk -F': *' '$1 == "Suite" {print $2; exit}' "$body")"
  codename="$(awk -F': *' '$1 == "Codename" {print $2; exit}' "$body")"
  release_date="$(awk -F': *' '$1 == "Date" {sub(/\r$/, "", $2); print $2; exit}' "$body")"
  valid_until="$(awk -F': *' '$1 == "Valid-Until" {sub(/\r$/, "", $2); print $2; exit}' "$body")"

  [[ "$origin" == "Ubuntu" && "$label" == "Ubuntu" ]] || {
    printf 'invalid|incompatible_origin|unknown\n'
    return 1
  }
  [[ "$suite" == "$expected_suite" && "$codename" == "$expected_codename" ]] || {
    printf 'invalid|incompatible_suite|unknown\n'
    return 1
  }
  [[ -n "$release_date" ]] || {
    printf 'invalid|missing_release_date|unknown\n'
    return 1
  }
  release_epoch="$(date -d "$release_date" +%s 2>/dev/null)" || {
    printf 'invalid|invalid_release_date|unknown\n'
    return 1
  }
  now="$(date +%s)"
  if ((release_epoch > now + 600)); then
    printf 'invalid|future_release_metadata|unknown\n'
    return 1
  fi
  if ((now - release_epoch > CATALOG_MAX_RELEASE_AGE)); then
    printf 'invalid|stale_release_metadata|stale\n'
    return 1
  fi

  if [[ -n "$valid_until" ]]; then
    valid_until_epoch="$(date -d "$valid_until" +%s 2>/dev/null)" || {
      printf 'invalid|invalid_valid_until|unknown\n'
      return 1
    }
    if ((valid_until_epoch <= now)); then
      printf 'invalid|expired_release_metadata|expired\n'
      return 1
    fi
    printf 'valid|ok|valid-until\n'
    return 0
  fi
  printf 'valid|ok|not-declared\n'
}

_same_mirror_origin() {
  local requested="$1" effective="$2" requested_scheme effective_scheme requested_host effective_host
  [[ -n "$effective" ]] || return 1
  requested_scheme="${requested%%://*}"
  effective_scheme="${effective%%://*}"
  requested_host="${requested#*://}"
  requested_host="${requested_host%%/*}"
  effective_host="${effective#*://}"
  effective_host="${effective_host%%/*}"
  requested_host="$(printf '%s' "$requested_host" | tr '[:upper:]' '[:lower:]')"
  effective_host="$(printf '%s' "$effective_host" | tr '[:upper:]' '[:lower:]')"
  [[ "$requested_host" == "$effective_host" ]] || return 1
  [[ "$requested_scheme" != https || "$effective_scheme" == https ]]
}

_probe_url_code() {
  local url="$1" expected_suite="$2" expected_codename="$3"
  local ip_flag="-4" attempt=0 max_attempts=$((PROBE_RETRIES + 1))
  local http_code="000" elapsed="0.000000" redirects=0 effective_url="$url"
  local metadata_status="invalid" signature_status="unknown" freshness="unknown" reason=""
  local tmpdir body headers request_output request_error wget_output start end
  [[ "$USE_IPV6" == true ]] && ip_flag="-6"

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/${APP_SLUG}.probe.XXXXXX")" || {
    printf '000\t0.000000\t0\t%s\tinvalid\tunknown\tunknown\ttemporary_directory_failed\n' "$url"
    return 0
  }
  _tmp_dirs+=("$tmpdir")
  body="$tmpdir/inrelease"
  headers="$tmpdir/headers"

  while ((attempt < max_attempts)); do
    : >"$body"
    : >"$headers"
    request_output=""
    request_error=""
    if command -v curl >/dev/null 2>&1; then
      request_output="$(curl "$ip_flag" -sS -L --max-redirs 5 \
        --proto '=http,https' --proto-redir '=https' \
        --connect-timeout "$PROBE_TIMEOUT_CONNECT" \
        --max-time "$TIMEOUT_TOTAL" \
        --dump-header "$headers" --output "$body" \
        --write-out '%{http_code}\t%{time_total}\t%{num_redirects}\t%{url_effective}' \
        "$url" 2>"$tmpdir/curl.err")" || request_error="$(cat "$tmpdir/curl.err" 2>/dev/null || true)"
      if [[ "$request_output" == *$'\t'* ]]; then
        IFS=$'\t' read -r http_code elapsed redirects effective_url <<<"$request_output"
      else
        http_code="000"
      fi
    elif command -v wget >/dev/null 2>&1; then
      start="$(date +%s.%N)"
      wget_output="$(wget --server-response --max-redirect=5 --timeout="$TIMEOUT_TOTAL" \
        --tries=1 -q -O "$body" "$url" 2>&1)" || request_error="$wget_output"
      end="$(date +%s.%N)"
      elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.6f", e-s }')"
      http_code="$(printf '%s\n' "$wget_output" | awk '/HTTP\// {code=$2} END {print code+0}')"
      [[ "$http_code" != 0 ]] || http_code="000"
      redirects="$(printf '%s\n' "$wget_output" | grep -ci 'Location:' || true)"
      effective_url="$url"
      if ((redirects > 0)); then
        effective_url="$(printf '%s\n' "$wget_output" | sed -n 's/.*Location: *\(https\?:\/\/[^[:space:]]*\).*/\1/p' | tail -1)"
      fi
    else
      request_error="no_http_client"
    fi

    if [[ "$http_code" == "000" || "$http_code" == "408" || "$http_code" == "429" || "$http_code" =~ ^5[0-9][0-9]$ ]]; then
      ((attempt += 1))
      if ((attempt < max_attempts)); then
        sleep 0.2
        continue
      fi
    fi
    break
  done

  if [[ "$http_code" != "200" ]]; then
    if [[ -n "$request_error" ]]; then
      if command -v curl >/dev/null 2>&1; then
        reason="$(_classify_curl_error "$tmpdir/curl.err")"
      else
        reason="$(_classify_wget_error "$request_error")"
      fi
    else
      reason="http_status_${http_code}"
    fi
  elif ! _same_mirror_origin "$url" "$effective_url"; then
    reason="cross_origin_or_unresolved_redirect"
  elif ((redirects > 5)); then
    reason="too_many_redirects"
  else
    local metadata_result metadata_reason
    metadata_result="$(_validate_release_metadata "$body" "$expected_codename" "$expected_suite")" || true
    IFS='|' read -r metadata_status metadata_reason freshness <<<"$metadata_result"
    if [[ "$metadata_status" != valid ]]; then
      reason="${metadata_reason:-invalid_release_metadata}"
    elif command -v gpgv >/dev/null 2>&1 && [[ -f "$KEYRING_PATH" ]]; then
      if gpgv --keyring "$KEYRING_PATH" "$body" >/dev/null 2>&1; then
        signature_status="valid"
      else
        signature_status="invalid"
        reason="invalid_archive_signature"
      fi
    else
      signature_status="unknown"
      reason="archive_signature_verifier_unavailable"
    fi
  fi

  rm -rf "$tmpdir" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$http_code" "$elapsed" "$redirects" "$effective_url" \
    "$metadata_status" "$signature_status" "$freshness" "$reason"
}

_test_mirror() {
  local base_url="${1%/}" result_file="$2" codename="$3"
  local main_url="${base_url}/dists/${codename}/InRelease"
  local updates_url="${base_url}/dists/${codename}-updates/InRelease"
  local security_url="${base_url}/dists/${codename}-security/InRelease"
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/${APP_SLUG}.mirror.XXXXXX")"
  _tmp_dirs+=("$tmpdir")

  _probe_url_code "$main_url" "$codename" "$codename" >"$tmpdir/main" &
  local pid_main=$!
  _probe_url_code "$updates_url" "${codename}-updates" "$codename" >"$tmpdir/updates" &
  local pid_updates=$!
  _probe_url_code "$security_url" "${codename}-security" "$codename" >"$tmpdir/security" &
  local pid_security=$!
  wait "$pid_main" 2>/dev/null || true
  wait "$pid_updates" 2>/dev/null || true
  wait "$pid_security" 2>/dev/null || true

  local main_code main_time main_redirects main_metadata main_signature main_freshness main_reason
  local updates_code updates_time updates_redirects updates_metadata updates_signature updates_freshness updates_reason
  local security_code security_time security_redirects security_metadata security_signature security_freshness security_reason
  IFS=$'\t' read -r main_code main_time main_redirects _ main_metadata main_signature main_freshness main_reason <"$tmpdir/main" || true
  IFS=$'\t' read -r updates_code updates_time updates_redirects _ updates_metadata updates_signature updates_freshness updates_reason <"$tmpdir/updates" || true
  IFS=$'\t' read -r security_code security_time security_redirects _ security_metadata security_signature security_freshness security_reason <"$tmpdir/security" || true

  main_code="${main_code:-000}"
  main_time="${main_time:-0.000000}"
  main_redirects="${main_redirects:-0}"
  updates_code="${updates_code:-000}"
  updates_time="${updates_time:-0.000000}"
  updates_redirects="${updates_redirects:-0}"
  security_code="${security_code:-000}"
  security_time="${security_time:-0.000000}"
  security_redirects="${security_redirects:-0}"

  local eligible=true failure_reason="" total_redirects avg_latency score freshness_summary signature_summary
  local endpoint http_code metadata_status signature_status reason
  for endpoint in \
    "$main_code:$main_metadata:$main_signature:$main_reason" \
    "$updates_code:$updates_metadata:$updates_signature:$updates_reason" \
    "$security_code:$security_metadata:$security_signature:$security_reason"; do
    IFS=':' read -r http_code metadata_status signature_status reason <<<"$endpoint"
    if [[ "$http_code" != 200 || "$metadata_status" != valid || "$signature_status" != valid ]]; then
      eligible=false
      [[ -n "$failure_reason" ]] || failure_reason="${reason:-incompatible_or_unverified_release}"
    fi
  done

  total_redirects=$((main_redirects + updates_redirects + security_redirects))
  avg_latency="$(awk -v a="$main_time" -v b="$updates_time" -v c="$security_time" 'BEGIN { printf "%.6f", (a+b+c)/3 }')"
  score="$(awk -v avg="$avg_latency" -v redirects="$total_redirects" 'BEGIN { printf "%.6f", avg + (redirects * 0.050000) }')"
  freshness_summary="valid-until-or-date"
  if [[ "$main_freshness" == not-declared || "$updates_freshness" == not-declared || "$security_freshness" == not-declared ]]; then
    freshness_summary="valid-date-no-valid-until"
  fi
  signature_summary="verified"
  [[ "$eligible" == true ]] || signature_summary="not-fully-verified"

  rm -rf "$tmpdir" 2>/dev/null || true
  if [[ "$eligible" == true ]]; then
    printf 'true|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$score" "$avg_latency" "$main_code" "$updates_code" "$security_code" \
      "$total_redirects" "$freshness_summary" "$signature_summary" >"$result_file"
  else
    printf 'false|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$score" "$avg_latency" "$main_code" "$updates_code" "$security_code" \
      "$total_redirects" "$freshness_summary" "$signature_summary" "$failure_reason" >"$result_file"
  fi

  msg_color "$COLOR_BOLD" "  ┌─ $base_url"
  printf '  │  main: %s (%ss, HTTP %s)\n' "$([[ "$main_metadata" == valid && "$main_signature" == valid ]] && echo VERIFIED || echo REJECTED)" "$main_time" "$main_code" >&2
  printf '  │  updates: %s (%ss, HTTP %s)\n' "$([[ "$updates_metadata" == valid && "$updates_signature" == valid ]] && echo VERIFIED || echo REJECTED)" "$updates_time" "$updates_code" >&2
  printf '  │  security: %s (%ss, HTTP %s)\n' "$([[ "$security_metadata" == valid && "$security_signature" == valid ]] && echo VERIFIED || echo REJECTED)" "$security_time" "$security_code" >&2
  if [[ "$eligible" == true ]]; then
    printf '  └─ %b PASS%b score=%ss avg=%ss redirects=%s freshness=%s\n' "$COLOR_GREEN" "$COLOR_RESET" "$score" "$avg_latency" "$total_redirects" "$freshness_summary" >&2
  else
    printf '  └─ %b REJECTED%b reason=%s\n' "$COLOR_RED" "$COLOR_RESET" "$failure_reason" >&2
  fi
}

# ─── Parallel Benchmark ──────────────────────────────────────────────────────

_select_mirror() {
  local mirror_list total_mirrors bench_start bench_end bench_duration
  local bench_tmpdir idx total i pid result_line eligible score avg_latency main_code updates_code security_code redirects freshness signature reason
  local best="" best_score="999999" best_avg="" tested=0 passed=0 failed=0
  local -a mirrors
  local -a pids=()

  _load_mirror_catalog
  _print_section_header "MIRROR SELECTION"
  msg "  Ubuntu codename:  ${COLOR_BOLD}${CODENAME}${COLOR_RESET}"
  mirror_list="$(_get_mirrors)"
  mapfile -t mirrors <<<"$mirror_list"
  total="${#mirrors[@]}"
  total_mirrors="$total"
  ((total > 0)) || die "No mirrors are available for the selected catalog profile." "$EXIT_NO_MIRROR"

  msg "  Mirrors to test:  ${COLOR_BOLD}${total_mirrors}${COLOR_RESET}"
  msg "  Parallel workers: ${COLOR_BOLD}${BENCH_WORKERS}${COLOR_RESET}"
  msg "  Retry policy:     ${COLOR_BOLD}${PROBE_RETRIES} retries per transient failure${COLOR_RESET}"
  msg "  Eligibility: HTTP 200 + Ubuntu suite metadata + valid archive signature"
  echo ""

  bench_start="$(date +%s)"
  bench_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/${APP_SLUG}.bench.XXXXXX")"
  _tmp_dirs+=("$bench_tmpdir")
  _start_spinner "Testing and verifying Ubuntu mirrors..."

  _bench_worker() {
    local idx="$1" url="$2" codename="$3" result_file="$4"
    _test_mirror "$url" "$result_file" "$codename" >/dev/null 2>&1
  }

  idx=0
  while ((idx < total)); do
    pids=()
    while (("${#pids[@]}" < BENCH_WORKERS)) && ((idx < total)); do
      _bench_worker "$idx" "${mirrors[$idx]}" "$CODENAME" "${bench_tmpdir}/${idx}.result" &
      pids+=("$!")
      _bg_pids+=("$!")
      ((idx += 1))
    done

    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done
    _bg_pids=()
  done
  pids=()

  bench_end="$(date +%s)"
  bench_duration=$((bench_end - bench_start))
  _stop_spinner

  for ((i = 0; i < total; i++)); do
    result_line="$(cat "${bench_tmpdir}/${i}.result" 2>/dev/null || true)"
    [[ -n "$result_line" ]] || {
      ((failed += 1)) || true
      continue
    }
    ((tested += 1)) || true
    IFS='|' read -r eligible score avg_latency main_code updates_code security_code redirects freshness signature reason <<<"$result_line"
    if [[ "$eligible" == true ]]; then
      ((passed += 1)) || true
      if awk -v candidate="$score" -v current="$best_score" 'BEGIN { exit !(candidate < current) }'; then
        best="${mirrors[$i]}"
        best_score="$score"
        best_avg="$avg_latency"
      elif [[ "$score" == "$best_score" && -n "$best" && "${mirrors[$i]}" < "$best" ]]; then
        best="${mirrors[$i]}"
        best_avg="$avg_latency"
      fi
    else
      ((failed += 1)) || true
      msg_verbose "Rejected ${mirrors[$i]}: ${reason:-incompatible_release}"
    fi
  done
  rm -rf "$bench_tmpdir" 2>/dev/null || true

  _print_section_header "BENCHMARK RESULTS"
  printf '  %-26s %d\n' "Mirrors tested:" "$tested"
  printf '  %-26s %d\n' "Verified and compatible:" "$passed"
  printf '  %-26s %d\n' "Rejected or unavailable:" "$failed"
  printf '  %-26s %ds\n' "Total duration:" "$bench_duration"
  printf '  %-26s %s\n' "Catalog source:" "$CATALOG_SOURCE"
  printf '  %-26s %s\n' "Catalog cache:" "$CATALOG_CACHE_STATE"
  printf '  %-26s %s\n' "Official-only profile:" "$OFFICIAL_ONLY"
  if [[ -n "$best" ]]; then
    printf '\n  Best compatible mirror: %s\n' "$best"
    printf '  Average latency: %ss | deterministic score: %ss\n' "$best_avg" "$best_score"
  fi

  if [[ -z "$best" ]]; then
    error "No mirror passed the Ubuntu metadata and signature compatibility gates."
    return "$EXIT_NO_MIRROR"
  fi

  SELECTED_MIRROR="$best"
  SELECTED_TIME="$best_avg"
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

# ─── APT Source Inventory and Architecture Helpers ───────────────────────────

_apt_architecture() {
  local architecture="unknown"
  if command -v dpkg >/dev/null 2>&1; then
    architecture="$(dpkg --print-architecture 2>/dev/null || true)"
  fi
  printf '%s\n' "${architecture:-unknown}"
}

_uses_ports_archive() {
  case "$(_apt_architecture)" in
  amd64 | i386 | unknown) return 1 ;;
  *) return 0 ;;
  esac
}

_is_official_ubuntu_uri() {
  local uri="$1" host
  host="${uri#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  [[ "$host" == "ubuntu.com" || "$host" == *.ubuntu.com || "$host" == "canonical.com" || "$host" == *.canonical.com ]]
}

_is_ubuntu_archive_uri() {
  local uri="$1" host
  host="${uri#*://}"
  host="${host%%/*}"
  host="${host##*@}"
  host="${host%%:*}"
  [[ "$host" == "archive.ubuntu.com" || "$host" == *.archive.ubuntu.com || "$host" == "security.ubuntu.com" || "$host" == "ports.ubuntu.com" ]]
}

_validate_proxy_url() {
  local url="$1" authority suffix port
  [[ "$url" != *'@'* && "$url" != *'?'* && "$url" != *'#'* && "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 1
  [[ "$url" =~ ^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?$ ]] || return 1
  authority="${url#*://}"
  if [[ "$authority" == \[* ]]; then
    suffix="${authority#*]}"
    if [[ -n "$suffix" ]]; then
      [[ "$suffix" =~ ^:([0-9]{1,5})$ ]] || return 1
      port="${BASH_REMATCH[1]}"
      ((port >= 1 && port <= 65535)) || return 1
    fi
  elif [[ "$authority" == *:* ]]; then
    port="${authority##*:}"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    ((port >= 1 && port <= 65535)) || return 1
  fi
  printf '%s\n' "$url"
}

_apt_source_records() {
  local file="$1"
  if [[ "$file" == *.sources ]]; then
    awk '
      function flush_stanza(  u, s, nu, ns, i, j, has_deb) {
        has_deb = (types ~ /(^|[[:space:]])deb([[:space:]]|$)/)
        if (has_deb && enabled != "no" && uris != "" && suites != "") {
          nu = split(uris, u, /[[:space:]]+/)
          ns = split(suites, s, /[[:space:]]+/)
          for (i = 1; i <= nu; i++)
            for (j = 1; j <= ns; j++)
              if (u[i] ~ /^https?:\/\// && s[j] != "") print u[i] "|" s[j]
        }
        types = ""; uris = ""; suites = ""; enabled = "yes"; current = ""
      }
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { flush_stanza(); next }
      /^[^[:space:]][^:]*:/ {
        current = tolower($1); sub(/:$/, "", current)
        value = $0; sub(/^[^:]*:[[:space:]]*/, "", value)
        if (current == "enabled") enabled = tolower(value)
        else if (current == "types") types = types " " value
        else if (current == "uris") uris = uris " " value
        else if (current == "suites") suites = suites " " value
        next
      }
      /^[[:space:]]+/ {
        value = $0; sub(/^[[:space:]]+/, "", value)
        if (current == "types") types = types " " value
        else if (current == "uris") uris = uris " " value
        else if (current == "suites") suites = suites " " value
      }
      END { flush_stanza() }
    ' "$file"
  else
    awk '
      {
        line = $0
        sub(/[[:space:]]*#.*/, "", line)
        sub(/^[[:space:]]+/, "", line)
        n = split(line, fields, /[[:space:]]+/)
        if (fields[1] != "deb" && fields[1] != "deb-src") next
        i = 2
        if (fields[i] ~ /^\[/) {
          while (i <= n && fields[i] !~ /\]$/) i++
          i++
        }
        if (fields[i] ~ /^https?:\/\// && fields[i + 1] != "")
          print fields[i] "|" fields[i + 1]
      }
    ' "$file"
  fi
}

_collect_source_inventory() {
  local file record uri suite key
  local -A seen=()
  APT_SOURCE_TOTAL=0
  APT_SOURCE_UBUNTU=0
  APT_SOURCE_THIRD_PARTY=0
  APT_SOURCE_DUPLICATES=0
  for file in "$APT_SOURCES_FILE" "$APT_SOURCES_DIR"/*.list "$APT_SOURCES_DIR"/*.sources; do
    [[ -f "$file" ]] || continue
    while IFS='|' read -r uri suite; do
      [[ -n "$uri" && -n "$suite" ]] || continue
      ((APT_SOURCE_TOTAL += 1)) || true
      if _is_official_ubuntu_uri "$uri"; then
        ((APT_SOURCE_UBUNTU += 1)) || true
      else
        ((APT_SOURCE_THIRD_PARTY += 1)) || true
      fi
      key="$uri|$suite"
      if [[ -n "${seen[$key]:-}" ]]; then
        ((APT_SOURCE_DUPLICATES += 1)) || true
      else
        seen[$key]=1
      fi
    done < <(_apt_source_records "$file")
  done
}

_write_apt_sources() {
  local mirror_url="$1"
  local has_third_party=false security_url managed_mirror="" existing_uri existing_suite existing_count=0
  if [[ ! -f "$KEYRING_PATH" ]]; then
    warn "Keyring not found at $KEYRING_PATH; APT signature validation may fail."
  fi

  if _uses_ports_archive; then
    [[ "$mirror_url" == */ubuntu-ports ]] || {
      error "Architecture $(_apt_architecture) requires a ports archive URL ending in /ubuntu-ports."
      return 1
    }
    security_url="$mirror_url"
  else
    [[ "$mirror_url" != */ubuntu-ports ]] || {
      error "The ports archive is not valid for architecture $(_apt_architecture)."
      return 1
    }
    security_url="https://security.ubuntu.com/ubuntu"
  fi

  if [[ -L "$APT_DEB822_FILE" ]]; then
    error "Refusing to replace a symlinked APT source file: $APT_DEB822_FILE."
    return 1
  fi
  if [[ -f "$APT_DEB822_FILE" ]]; then
    if grep -q '^# Power APT Boost' "$APT_DEB822_FILE"; then
      managed_mirror="$(sed -n 's/^# Mirror: //p' "$APT_DEB822_FILE" | head -1)"
      if [[ -z "$managed_mirror" ]]; then
        error "Managed Ubuntu source file has no recorded mirror URL; refusing to replace it."
        return 1
      fi
      while IFS='|' read -r existing_uri existing_suite; do
        [[ -n "$existing_uri" && -n "$existing_suite" ]] || continue
        ((existing_count += 1))
        case "$existing_uri|$existing_suite" in
        "$managed_mirror|$CODENAME" | "$managed_mirror|$CODENAME-updates" | "$managed_mirror|$CODENAME-backports" | "$managed_mirror|$CODENAME-security" | "$security_url|$CODENAME-security") ;;
        *)
          error "Managed Ubuntu source file contains an unexpected repository entry: $existing_uri ($existing_suite)."
          error "Move the extra repository to its own .sources file; no source file was changed."
          return 1
          ;;
        esac
      done < <(_apt_source_records "$APT_DEB822_FILE")
      if ((existing_count != 4)); then
        error "Managed Ubuntu source file has an unexpected number of active URI/suite entries; refusing to replace it."
        return 1
      fi
    else
      while IFS='|' read -r existing_uri existing_suite; do
        [[ -n "$existing_uri" && -n "$existing_suite" ]] || continue
        ((existing_count += 1))
        if ! _is_ubuntu_archive_uri "$existing_uri"; then
          error "Refusing to overwrite unmanaged or non-archive Deb822 source: $existing_uri ($existing_suite)."
          return 1
        fi
      done < <(_apt_source_records "$APT_DEB822_FILE")
      if [[ -s "$APT_DEB822_FILE" && "$existing_count" -eq 0 ]]; then
        error "Refusing to overwrite an unmanaged Deb822 file that cannot be classified safely."
        return 1
      fi
    fi
  fi

  if [[ -L "$APT_SOURCES_FILE" ]]; then
    has_third_party=true
  elif [[ -f "$APT_SOURCES_FILE" ]]; then
    local legacy_uri legacy_suite legacy_count=0
    while IFS='|' read -r legacy_uri legacy_suite; do
      [[ -n "$legacy_uri" && -n "$legacy_suite" ]] || continue
      ((legacy_count += 1))
      if ! _is_ubuntu_archive_uri "$legacy_uri"; then
        has_third_party=true
      fi
    done < <(_apt_source_records "$APT_SOURCES_FILE")
    if [[ -s "$APT_SOURCES_FILE" && "$legacy_count" -eq 0 ]]; then
      has_third_party=true
    fi
  fi

  if ! _atomic_write "$APT_DEB822_FILE" 0644 <<SOURCES; then
# Power APT Boost — Ubuntu mirror configuration
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Mirror: $mirror_url
# Architecture: $(_apt_architecture)

Types: deb
URIs: $mirror_url
Suites: $CODENAME $CODENAME-updates $CODENAME-backports
Components: main restricted universe multiverse
Signed-By: $KEYRING_PATH

Types: deb
URIs: $security_url
Suites: $CODENAME-security
Components: main restricted universe multiverse
Signed-By: $KEYRING_PATH
SOURCES
    return 1
  fi

  if [[ -f "$APT_SOURCES_FILE" ]]; then
    if [[ "$has_third_party" == true ]]; then
      warn "Third-party or unclassified repositories detected in sources.list; preserving the file."
    elif ! rm -f -- "$APT_SOURCES_FILE"; then
      error "Could not remove legacy Ubuntu-only sources.list."
      return 1
    fi
  fi
}

_write_apt_config() {
  local force_ip_config proxy_config="" existing_proxy_config=""
  if [[ -L "$APT_CONF_FILE" ]]; then
    error "Refusing to replace a symlinked APT network config: $APT_CONF_FILE."
    return 1
  fi
  if [[ -f "$APT_CONF_FILE" ]] && ! grep -q '^# Power APT Boost' "$APT_CONF_FILE"; then
    error "Refusing to overwrite unmanaged APT network settings in $APT_CONF_FILE."
    return 1
  fi
  if [[ "$USE_IPV6" == true ]]; then
    force_ip_config='Acquire::ForceIPv6 "true";'
  else
    force_ip_config='Acquire::ForceIPv4 "true";'
  fi
  if [[ "$CLEAR_APT_PROXY" == true ]]; then
    proxy_config='Acquire::http::Proxy "DIRECT";
Acquire::https::Proxy "DIRECT";'
  elif [[ -n "$APT_PROXY" ]]; then
    proxy_config="$(printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";' "$APT_PROXY" "$APT_PROXY")"
  elif [[ -f "$APT_CONF_FILE" ]]; then
    existing_proxy_config="$(grep -E '^Acquire::(http|https)::Proxy ' "$APT_CONF_FILE" || true)"
    proxy_config="$existing_proxy_config"
  fi
  _atomic_write "$APT_CONF_FILE" 0644 <<APTCONF
# Power APT Boost — APT network optimization
# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

$force_ip_config
Acquire::Retries "$APT_RETRIES";
Acquire::http::Timeout "$TIMEOUT_TOTAL";
Acquire::https::Timeout "$TIMEOUT_TOTAL";
Acquire::Languages "none";
$proxy_config
APTCONF
}

_verify_apt_configuration() {
  [[ -s "$APT_DEB822_FILE" && -f "$APT_CONF_FILE" ]] || return 1
  grep -Fq "URIs: $SELECTED_MIRROR" "$APT_DEB822_FILE" || return 1
  grep -Fq "Suites: $CODENAME $CODENAME-updates $CODENAME-backports" "$APT_DEB822_FILE" || return 1
  grep -Fq "Suites: $CODENAME-security" "$APT_DEB822_FILE" || return 1
  grep -Fq "Signed-By: $KEYRING_PATH" "$APT_DEB822_FILE" || return 1
  grep -Fq "Acquire::Retries \"$APT_RETRIES\";" "$APT_CONF_FILE" || return 1
  apt-get \
    -o "Dir::Etc::sourcelist=$APT_SOURCES_FILE" \
    -o "Dir::Etc::sourceparts=$APT_SOURCES_DIR" \
    -o "Dir::Etc::main=$APT_ETC_DIR/apt.conf" \
    -o "Dir::Etc::parts=$APT_CONF_DIR" \
    --print-uris update >/dev/null 2>&1
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

  local -a target_names=()
  case "$RESTORE_SCOPE" in
  all) target_names=(sources.list sources.list.d apt.conf.d) ;;
  sources) target_names=(sources.list sources.list.d) ;;
  network) target_names=(apt.conf.d) ;;
  *)
    rm -rf "$stage_dir"
    error "Unknown restore scope: $RESTORE_SCOPE"
    return "$EXIT_RESTORE"
    ;;
  esac
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
  printf '  Architecture: %s\n' "$(_apt_architecture)"
  printf '  APT timeout/retries: %ss / %s\n' "$TIMEOUT_TOTAL" "$APT_RETRIES"
  if [[ "$CLEAR_APT_PROXY" == true ]]; then
    printf '  APT proxy: DIRECT (explicitly disabled)\n'
  elif [[ -n "$APT_PROXY" ]]; then
    printf '  APT proxy: %s\n' "$APT_PROXY"
  else
    printf '  APT proxy: preserve existing external settings\n'
  fi
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

  if ! _verify_apt_configuration; then
    warn "APT parser verification failed. Restoring the validated snapshot."
    if ! _restore_backup "$backup_dir"; then
      die "APT verification failed and rollback failed. Recovery snapshot: $backup_dir" "$EXIT_RESTORE"
    fi
    die "APT configuration verification failed. The original configuration was restored." "$EXIT_GENERAL"
  fi

  if [[ "$SKIP_UPDATE" == true ]]; then
    info "APT source and network configuration passed local parser verification."
    msg_color "$COLOR_YELLOW" "  Package-index refresh skipped by request; cached package lists were left untouched."
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
  local input="${1-}" output="" char escaped_char byte_code i
  local LC_ALL=C

  for ((i = 0; i < ${#input}; i++)); do
    char="${input:i:1}"
    # shellcheck disable=SC1003
    printf -v byte_code '%d' "'$char"
    case "$byte_code" in
    34) output+="\\\"" ;;
    92) output+="\\\\" ;;
    *)
      if ((byte_code < 32)); then
        printf -v escaped_char '\\u%04x' "$byte_code"
        output+="$escaped_char"
      else
        output+="$char"
      fi
      ;;
    esac
  done

  printf '"%s"' "$output"
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
  _collect_source_inventory
  REPORT_SOURCE_COUNT="$APT_SOURCE_TOTAL"
  REPORT_UBUNTU_SOURCE_COUNT="$APT_SOURCE_UBUNTU"
  REPORT_THIRD_PARTY_SOURCE_COUNT="$APT_SOURCE_THIRD_PARTY"
  REPORT_DUPLICATE_SOURCE_COUNT="$APT_SOURCE_DUPLICATES"
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
  printf '%-24s %s\n' "APT source records:" "$REPORT_SOURCE_COUNT"
  printf '%-24s %s\n' "Ubuntu source records:" "$REPORT_UBUNTU_SOURCE_COUNT"
  printf '%-24s %s\n' "Third-party records:" "$REPORT_THIRD_PARTY_SOURCE_COUNT"
  printf '%-24s %s\n' "Duplicate URI/suite records:" "$REPORT_DUPLICATE_SOURCE_COUNT"
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
  for cmd in apt-get apt-config awk date grep mkdir cp id mktemp tar sha256sum flock chmod stat find sort head cut chown mv rm sed gpgv; do
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
    _doctor_add_check "ubuntu_archive_keyring" "ok" "Ubuntu archive keyring exists"
  else
    _doctor_add_check "ubuntu_archive_keyring" "error" "Ubuntu archive keyring is required to verify mirror signatures"
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
  if [[ -d "$(dirname "$USER_MIRRORS_FILE")" && -w "$(dirname "$USER_MIRRORS_FILE")" ]]; then
    _doctor_add_check "custom_mirror_storage" "ok" "custom mirror catalog storage is writable"
  elif [[ "$(id -u)" -eq 0 ]]; then
    _doctor_add_check "custom_mirror_storage" "ok" "custom mirror catalog storage will be created on demand"
  else
    _doctor_add_check "custom_mirror_storage" "warning" "root is required to manage saved custom mirrors"
  fi
  if [[ "$REPORT_BACKUP_ACCESSIBLE" == true ]]; then
    _doctor_add_check "backup_directory" "ok" "$REPORT_BACKUP_COUNT backup snapshot(s) visible"
  else
    _doctor_add_check "backup_directory" "warning" "backup directory is not currently accessible or has not been created"
  fi

  if ((REPORT_DUPLICATE_SOURCE_COUNT > 0)); then
    _doctor_add_check "duplicate_sources" "warning" "$REPORT_DUPLICATE_SOURCE_COUNT duplicate URI/suite record(s) detected"
  else
    _doctor_add_check "duplicate_sources" "ok" "No duplicate URI/suite records detected"
  fi

  local insecure_sources=""
  insecure_sources="$(grep -RilE 'trusted[[:space:]]*=[[:space:]]*yes|Allow-Insecure|Allow-Unauthenticated|Check-Valid-Until:[[:space:]]*no' "$APT_SOURCES_FILE" "$APT_SOURCES_DIR" "$APT_CONF_DIR" 2>/dev/null | head -1 || true)"
  if [[ -n "$insecure_sources" ]]; then
    _doctor_add_check "signature_policy" "warning" "Potentially unsafe APT trust override detected; inspect local source/config files"
  elif [[ -f "$KEYRING_PATH" ]] && command -v gpgv >/dev/null 2>&1; then
    _doctor_add_check "signature_policy" "ok" "Archive keyring and gpgv are available; no obvious insecure override found"
  else
    _doctor_add_check "signature_policy" "error" "Archive signature verification prerequisites are unavailable"
  fi

  local list_dir="${_SYSTEM_ROOT}/var/lib/apt/lists" release_file now mtime stale_metadata=false release_count=0
  now="$(date +%s)"
  if [[ -d "$list_dir" ]]; then
    while IFS= read -r release_file; do
      [[ -n "$release_file" ]] || continue
      ((release_count += 1))
      mtime="$(stat -c '%Y' "$release_file" 2>/dev/null || echo 0)"
      if ((now - mtime > CATALOG_MAX_RELEASE_AGE)); then stale_metadata=true; fi
    done < <(find "$list_dir" -maxdepth 1 -type f -name '*_InRelease' -print 2>/dev/null)
  fi
  if ((release_count == 0)); then
    _doctor_add_check "metadata_freshness" "warning" "No cached InRelease metadata found; run apt-get update after checking connectivity"
  elif [[ "$stale_metadata" == true ]]; then
    _doctor_add_check "metadata_freshness" "warning" "At least one cached InRelease file is older than seven days"
  else
    _doctor_add_check "metadata_freshness" "ok" "$release_count cached InRelease file(s) are no older than seven days"
  fi

  local proxy_dump proxy_count
  proxy_dump="$(apt-config dump 2>/dev/null || true)"
  proxy_count="$(printf '%s\n' "$proxy_dump" | grep -Ec '^Acquire::(http|https)::Proxy[[:space:]]' || true)"
  if ((proxy_count > 0)); then
    _doctor_add_check "apt_proxy" "ok" "$proxy_count APT proxy directive(s) configured; values are masked"
  else
    _doctor_add_check "apt_proxy" "ok" "No explicit APT proxy directive detected"
  fi

  if [[ "$NETWORK_DIAGNOSTICS" == true ]]; then
    if command -v getent >/dev/null 2>&1 && getent ahosts security.ubuntu.com >/dev/null 2>&1; then
      _doctor_add_check "dns" "ok" "security.ubuntu.com resolved successfully"
    else
      _doctor_add_check "dns" "warning" "Could not resolve security.ubuntu.com"
    fi
    local tls_url="https://security.ubuntu.com/ubuntu/dists/${REPORT_CODENAME}-security/InRelease"
    if command -v curl >/dev/null 2>&1 && curl --fail --silent --show-error --connect-timeout 5 --max-time 12 --output /dev/null "$tls_url" 2>/dev/null; then
      _doctor_add_check "tls" "ok" "HTTPS request to the Ubuntu security archive succeeded"
    elif command -v wget >/dev/null 2>&1 && wget --quiet --spider --timeout=12 "$tls_url" >/dev/null 2>&1; then
      _doctor_add_check "tls" "ok" "HTTPS request to the Ubuntu security archive succeeded"
    else
      _doctor_add_check "tls" "warning" "HTTPS/TLS request to the Ubuntu security archive failed or was blocked"
    fi
  else
    _doctor_add_check "dns" "skipped" "Live DNS test skipped; use --doctor --network-diagnostics to run it"
    _doctor_add_check "tls" "skipped" "Live TLS test skipped; use --doctor --network-diagnostics to run it"
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
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "version": %s,\n' "$(_json_quote "$APP_VERSION")"
  printf '  "command": %s,\n' "$(_json_quote "$REPORT_COMMAND")"
  printf '  "status": %s,\n' "$(_json_quote "$REPORT_STATUS")"
  printf '  "timestamp": %s,\n' "$(_json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "system": {"id": %s, "pretty_name": %s, "version_id": %s, "codename": %s},\n' "$(_json_quote "$REPORT_OS_ID")" "$(_json_quote "$REPORT_OS_PRETTY")" "$(_json_quote "$REPORT_VERSION_ID")" "$(_json_quote "$REPORT_CODENAME")"
  printf '  "apt": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "current_mirror": %s, "source_records": %s, "ubuntu_source_records": %s, "third_party_source_records": %s, "duplicate_source_records": %s},\n' "$(_json_quote "$REPORT_SOURCES_LIST")" "$(_json_quote "$REPORT_DEB822")" "$(_json_quote "$REPORT_MANAGED_CONFIG")" "$(_json_quote "$REPORT_CURRENT_MIRROR")" "$REPORT_SOURCE_COUNT" "$REPORT_UBUNTU_SOURCE_COUNT" "$REPORT_THIRD_PARTY_SOURCE_COUNT" "$REPORT_DUPLICATE_SOURCE_COUNT"
  printf '  "backups": {"accessible": %s, "count": %s, "latest": %s},\n' "$REPORT_BACKUP_ACCESSIBLE" "$REPORT_BACKUP_COUNT" "$(_json_quote "$REPORT_LATEST_BACKUP")"
  printf '  "operation": {"mirror": %s, "response_time_seconds": %s, "dry_run": %s, "skip_update": %s},\n' "$(_json_quote "$SELECTED_MIRROR")" "$(_json_quote "$SELECTED_TIME")" "$DRY_RUN" "$SKIP_UPDATE"
  printf '  "catalog": {"source": %s, "cache_state": %s, "last_refresh": %s, "invalid_entries": %s},\n' "$(_json_quote "$CATALOG_SOURCE")" "$(_json_quote "$CATALOG_CACHE_STATE")" "$(_json_quote "$CATALOG_LAST_REFRESH")" "$CATALOG_INVALID_ENTRIES"
  printf '  "benchmark": {"workers": %s, "retries": %s, "official_only": %s, "country_filter": %s},\n' "$BENCH_WORKERS" "$PROBE_RETRIES" "$OFFICIAL_ONLY" "$(_json_quote "$COUNTRY_FILTER")"
  printf '  "paths": {"sources_list": %s, "deb822_sources": %s, "managed_config": %s, "backup_root": %s},\n' "$(_json_quote "$APT_SOURCES_FILE")" "$(_json_quote "$APT_DEB822_FILE")" "$(_json_quote "$APT_CONF_FILE")" "$(_json_quote "$BACKUP_BASE")"
  printf '  "checks": %s\n' "$checks_json"
  printf '}\n'
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
  ${COLOR_GREEN}    --restore-scope SCOPE${COLOR_RESET} Restore all, sources or network settings
  ${COLOR_GREEN}    --prune-backups N${COLOR_RESET}   Keep N newest verified snapshots; remove older verified snapshots
  ${COLOR_GREEN}    --dry-run${COLOR_RESET}            Test mirrors without changing config
  ${COLOR_GREEN}    --skip-update${COLOR_RESET}        Write config but skip apt-get update (preserve caches)
  ${COLOR_GREEN}    --list${COLOR_RESET}               List available mirrors and test them
  ${COLOR_GREEN}    --refresh-catalog${COLOR_RESET}     Refresh the Ubuntu mirror index, then list
  ${COLOR_GREEN}    --official-only${COLOR_RESET}       Use only built-in official Ubuntu archive hosts
  ${COLOR_GREEN}    --workers N${COLOR_RESET}           Benchmark concurrency (1-${MAX_WORKERS_LIMIT}, default: 8)
  ${COLOR_GREEN}    --retries N${COLOR_RESET}           Retry transient probe failures (0-3, default: 1)
  ${COLOR_GREEN}    --apt-retries N${COLOR_RESET}       APT network retries (0-10, default: 3)
  ${COLOR_GREEN}    --proxy URL${COLOR_RESET}           Set HTTP/HTTPS proxy (without embedded credentials)
  ${COLOR_GREEN}    --clear-proxy${COLOR_RESET}        Explicitly bypass APT proxies
  ${COLOR_GREEN}    --network-diagnostics${COLOR_RESET} Run live DNS/TLS checks with --doctor
  ${COLOR_GREEN}    --add-mirror URL${COLOR_RESET}      Verify and save a custom mirror
  ${COLOR_GREEN}    --remove-mirror ID${COLOR_RESET}    Remove a saved custom mirror
  ${COLOR_GREEN}    --disable-mirror ID${COLOR_RESET}   Disable a saved custom mirror
  ${COLOR_GREEN}    --enable-mirror ID${COLOR_RESET}    Enable a saved custom mirror
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
  sudo bash ${_SCRIPT_NAME} --doctor --network-diagnostics

  ${COLOR_DIM}# Test without changing system config${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run

  ${COLOR_DIM}# Use a specific mirror${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Restore source or network settings only${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore --restore-scope sources
  sudo bash ${_SCRIPT_NAME} --restore --restore-scope network

  ${COLOR_DIM}# Keep the five newest verified backups${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --prune-backups 5 --yes

  ${COLOR_DIM}# Configure an APT proxy and retry policy${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --proxy http://127.0.0.1:3128 --apt-retries 5 --yes

  ${COLOR_DIM}# Restore from latest backup${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --restore

  ${COLOR_DIM}# Machine-readable output for CI/CD pipelines${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --json --quiet

  ${COLOR_DIM}# List and test all available mirrors${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list

  ${COLOR_DIM}# Filter mirrors by country${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --refresh-catalog

  ${COLOR_DIM}# Test only built-in official archive hosts${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list --official-only

  ${COLOR_DIM}# Tune bounded benchmark concurrency and retry policy${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --dry-run --workers 4 --retries 2

  ${COLOR_DIM}# Add a custom mirror (each suite must pass signed metadata checks)${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --add-mirror https://mirror.example.com/ubuntu

  ${COLOR_DIM}# Disable or remove a saved custom mirror by its ID${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --disable-mirror user-0123456789ab
  sudo bash ${_SCRIPT_NAME} --remove-mirror user-0123456789ab

  ${COLOR_DIM}# Filter mirrors by country code${COLOR_RESET}
  sudo bash ${_SCRIPT_NAME} --list --country us

${COLOR_BOLD}${COLOR_BLUE}WHAT IT DOES${COLOR_RESET}
  1. Detects your Ubuntu version
  2. Loads a versioned catalog from built-in, Ubuntu-index and user-defined sources
  3. Verifies main, updates and security Release metadata and Ubuntu archive signatures
  4. Rejects stale, incompatible, redirected or unsigned mirror endpoints
  5. Ranks compatible mirrors by average latency plus a 50 ms penalty per redirect
  6. Backs up current APT configuration before an approved apply
  7. Writes optimized APT sources (deb822 format) and network configuration
  8. Preserves existing package lists and downloaded package archives when --skip-update is selected
  9. Runs apt-get update unless --skip-update is selected

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
    --restore-scope)
      case "${2:-}" in
      all | sources | network) RESTORE_SCOPE="$2" ;;
      *) die "Option $1 must be all, sources or network." "$EXIT_USAGE" ;;
      esac
      RESTORE=true
      shift 2
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
    --refresh-catalog)
      REFRESH_CATALOG=true
      LIST_REQUESTED=true
      shift
      ;;
    --official-only)
      OFFICIAL_ONLY=true
      shift
      ;;
    --workers)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires an integer from 1 to $MAX_WORKERS_LIMIT." "$EXIT_USAGE"
      (($2 >= 1 && $2 <= MAX_WORKERS_LIMIT)) || die "Option $1 must be between 1 and $MAX_WORKERS_LIMIT." "$EXIT_USAGE"
      BENCH_WORKERS="$2"
      shift 2
      ;;
    --retries)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires an integer from 0 to 3." "$EXIT_USAGE"
      (($2 >= 0 && $2 <= 3)) || die "Option $1 must be between 0 and 3." "$EXIT_USAGE"
      PROBE_RETRIES="$2"
      shift 2
      ;;
    --apt-retries)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires an integer from 0 to 10." "$EXIT_USAGE"
      (($2 >= 0 && $2 <= 10)) || die "Option $1 must be between 0 and 10." "$EXIT_USAGE"
      APT_RETRIES="$2"
      ACTION_REQUESTED=true
      shift 2
      ;;
    --proxy)
      [[ -n "${2:-}" ]] || die "Option $1 requires a proxy URL." "$EXIT_USAGE"
      [[ "$CLEAR_APT_PROXY" != true ]] || die "--proxy cannot be combined with --clear-proxy." "$EXIT_USAGE"
      APT_PROXY="$(_validate_proxy_url "$2")" || die "Invalid proxy URL. Use http(s)://host[:port] without credentials or a path." "$EXIT_USAGE"
      ACTION_REQUESTED=true
      shift 2
      ;;
    --clear-proxy)
      [[ -z "$APT_PROXY" ]] || die "--clear-proxy cannot be combined with --proxy." "$EXIT_USAGE"
      CLEAR_APT_PROXY=true
      ACTION_REQUESTED=true
      shift
      ;;
    --prune-backups)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "Option $1 requires a retention count from 1 to 100." "$EXIT_USAGE"
      (($2 >= 1 && $2 <= 100)) || die "Option $1 must be between 1 and 100." "$EXIT_USAGE"
      PRUNE_BACKUPS_KEEP="$2"
      shift 2
      ;;
    --network-diagnostics)
      NETWORK_DIAGNOSTICS=true
      shift
      ;;
    --add-mirror)
      [[ -n "${2:-}" ]] || die "Option $1 requires a mirror URL." "$EXIT_USAGE"
      MIRROR_MANAGEMENT_ACTION="add"
      MIRROR_MANAGEMENT_VALUE="$2"
      MIRROR_MANAGEMENT_REQUESTED=true
      shift 2
      ;;
    --remove-mirror)
      [[ -n "${2:-}" ]] || die "Option $1 requires a mirror ID." "$EXIT_USAGE"
      MIRROR_MANAGEMENT_ACTION="remove"
      MIRROR_MANAGEMENT_VALUE="$2"
      MIRROR_MANAGEMENT_REQUESTED=true
      shift 2
      ;;
    --disable-mirror)
      [[ -n "${2:-}" ]] || die "Option $1 requires a mirror ID." "$EXIT_USAGE"
      MIRROR_MANAGEMENT_ACTION="disable"
      MIRROR_MANAGEMENT_VALUE="$2"
      MIRROR_MANAGEMENT_REQUESTED=true
      shift 2
      ;;
    --enable-mirror)
      [[ -n "${2:-}" ]] || die "Option $1 requires a mirror ID." "$EXIT_USAGE"
      MIRROR_MANAGEMENT_ACTION="enable"
      MIRROR_MANAGEMENT_VALUE="$2"
      MIRROR_MANAGEMENT_REQUESTED=true
      shift 2
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
  [[ "$MENU_REQUESTED" != true ]] || ((mode_count += 1))
  [[ "$STATUS_REQUESTED" != true ]] || ((mode_count += 1))
  [[ "$DOCTOR_REQUESTED" != true ]] || ((mode_count += 1))
  [[ "$LIST_REQUESTED" != true ]] || ((mode_count += 1))
  [[ "$RESTORE" != true ]] || ((mode_count += 1))
  [[ "$MIRROR_MANAGEMENT_REQUESTED" != true ]] || ((mode_count += 1))
  [[ -z "$PRUNE_BACKUPS_KEEP" ]] || ((mode_count += 1))
  ((mode_count <= 1)) || die "Choose only one command mode: menu, status, doctor, list, restore, backup pruning or mirror management." "$EXIT_USAGE"
  [[ "$RESTORE_SCOPE" == all || "$RESTORE" == true ]] || die "--restore-scope requires --restore." "$EXIT_USAGE"
  [[ "$NETWORK_DIAGNOSTICS" != true || "$DOCTOR_REQUESTED" == true ]] || die "--network-diagnostics can only be used with --doctor." "$EXIT_USAGE"

  if [[ "$MENU_REQUESTED" == true ]]; then
    [[ "$YES" != true && "$JSON_OUTPUT" != true && "$ACTION_REQUESTED" != true && "$OFFICIAL_ONLY" != true && "$REFRESH_CATALOG" != true ]] || die "--menu cannot be combined with CLI operation flags." "$EXIT_USAGE"
  fi
  if [[ "$STATUS_REQUESTED" == true || "$DOCTOR_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" && "$OFFICIAL_ONLY" != true && "$REFRESH_CATALOG" != true && "$MIRROR_MANAGEMENT_REQUESTED" != true && -z "$PRUNE_BACKUPS_KEEP" ]] || die "--status and --doctor are read-only commands and cannot be combined with operation flags." "$EXIT_USAGE"
  fi
  if [[ -n "$PRUNE_BACKUPS_KEEP" ]]; then
    [[ "$ACTION_REQUESTED" != true && "$RESTORE" != true && "$LIST_REQUESTED" != true && "$MIRROR_MANAGEMENT_REQUESTED" != true && "$JSON_OUTPUT" != true && "$NETWORK_DIAGNOSTICS" != true ]] || die "--prune-backups cannot be combined with another command." "$EXIT_USAGE"
  fi
  if [[ "$LIST_REQUESTED" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" && "$MIRROR_MANAGEMENT_REQUESTED" != true ]] || die "--list cannot be combined with apply or mirror-management options." "$EXIT_USAGE"
  fi
  if [[ "$RESTORE" == true ]]; then
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && -z "$FORCE_MIRROR" && "$MIRROR_MANAGEMENT_REQUESTED" != true && -z "$PRUNE_BACKUPS_KEEP" ]] || die "--restore cannot be combined with apply or mirror-management options." "$EXIT_USAGE"
  fi
  if [[ "$MIRROR_MANAGEMENT_REQUESTED" == true ]]; then
    [[ "$JSON_OUTPUT" != true && "$OFFICIAL_ONLY" != true && "$REFRESH_CATALOG" != true ]] || die "Mirror management cannot be combined with --json, --official-only or --refresh-catalog." "$EXIT_USAGE"
    [[ "$ACTION_REQUESTED" != true && "$SKIP_UPDATE" != true && "$RESTORE" != true && "$LIST_REQUESTED" != true && -z "$FORCE_MIRROR" && -z "$PRUNE_BACKUPS_KEEP" ]] || die "Mirror management cannot be combined with other operations." "$EXIT_USAGE"
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
  *)
    info "Cancelled. No system changes were made."
    return 10
    ;;
  esac
}

_print_apply_preview() {
  _print_section_header "CHANGE PREVIEW"
  printf 'Selected mirror: %s\n' "$SELECTED_MIRROR"
  printf 'APT source file: %s\n' "$APT_DEB822_FILE"
  printf 'APT network config: %s\n' "$APT_CONF_FILE"
  printf 'APT timeout/retries: %ss / %s\n' "$TIMEOUT_TOTAL" "$APT_RETRIES"
  if [[ "$CLEAR_APT_PROXY" == true ]]; then
    printf 'APT proxy: DIRECT (explicitly disabled)\n'
  elif [[ -n "$APT_PROXY" ]]; then
    printf 'APT proxy: %s\n' "$APT_PROXY"
  else
    printf 'APT proxy: existing settings preserved\n'
  fi
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
  case "$RESTORE_SCOPE" in
  all) printf 'Restore scope: all APT source and network configuration\n' ;;
  sources) printf 'Restore scope: APT sources only\n' ;;
  network) printf 'Restore scope: APT network settings only\n' ;;
  esac
  if [[ "$RESTORE_SCOPE" == network ]]; then
    printf 'APT update: skipped for network-only restore\n'
  else
    printf 'APT update: apt-get update will run after restoration\n'
  fi
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
    IFS= read -r _ || true
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

_catalog_url_is_official() {
  local requested_url="${1%/}" entry id country region url source official enabled
  for entry in "${_MIRROR_CATALOG[@]}"; do
    IFS='|' read -r id country region url source official enabled <<<"$entry"
    if [[ "${url%/}" == "$requested_url" && "$official" == true && "$enabled" == true ]]; then
      return 0
    fi
  done
  return 1
}

_write_user_mirror_catalog() {
  local i
  mkdir -p "$(dirname "$USER_MIRRORS_FILE")" || return 1
  chmod 0700 "$(dirname "$USER_MIRRORS_FILE")" 2>/dev/null || true
  {
    printf '# power-apt-boost custom mirror catalog v1\n'
    for i in "${!_CATALOG_IDS[@]}"; do
      [[ "${_CATALOG_SOURCES[$i]}" == user ]] || continue
      printf '%s|%s|%s|%s|user|false|%s\n' \
        "${_CATALOG_IDS[$i]}" "${_CATALOG_COUNTRIES[$i]}" "${_CATALOG_REGIONS[$i]}" \
        "${_CATALOG_URLS[$i]}" "${_CATALOG_ENABLED[$i]}"
    done
  } | _atomic_write "$USER_MIRRORS_FILE" 0600
}

_run_mirror_management() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Non-interactive custom mirror changes require --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "Custom mirror management must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  _check_commands

  local mirror_id requested_url result_file result_line eligible score avg_latency main_code updates_code security_code redirects freshness signature reason
  local i target_index=-1 confirm_status=0 old_network_setting="$NO_CATALOG_NETWORK"
  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK="$old_network_setting"

  case "$MIRROR_MANAGEMENT_ACTION" in
  add)
    _check_probe_tool
    detect_ubuntu
    requested_url="$(_validate_mirror_url "$MIRROR_MANAGEMENT_VALUE")" || {
      error "Invalid Ubuntu mirror URL: $MIRROR_MANAGEMENT_VALUE"
      return "$EXIT_USAGE"
    }
    for i in "${!_CATALOG_URLS[@]}"; do
      [[ "${_CATALOG_URLS[$i]}" != "$requested_url" ]] || {
        error "This mirror URL already exists in the catalog as ${_CATALOG_IDS[$i]}."
        return "$EXIT_USAGE"
      }
    done
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.custom.XXXXXX")" || return "$EXIT_GENERAL"
    _tmp_dirs+=("$result_file")
    _print_section_header "VERIFYING CUSTOM MIRROR"
    _test_mirror "$requested_url" "$result_file" "$CODENAME"
    result_line="$(cat "$result_file" 2>/dev/null || true)"
    rm -f "$result_file" 2>/dev/null || true
    IFS='|' read -r eligible score avg_latency main_code updates_code security_code redirects freshness signature reason <<<"$result_line"
    if [[ "$eligible" != true ]]; then
      error "Custom mirror rejected: ${reason:-Ubuntu metadata or signature verification failed}."
      return "$EXIT_NO_MIRROR"
    fi
    mirror_id="user-$(printf '%s' "$requested_url" | sha256sum | cut -c1-12)"
    printf 'Mirror ID: %s\nURL: %s\nAverage latency: %ss\n' "$mirror_id" "$requested_url" "$avg_latency"
    _confirm_action "Save this verified mirror to the custom catalog?" || confirm_status=$?
    [[ "$confirm_status" -eq 0 ]] || return "$confirm_status"
    _acquire_mutation_lock
    _catalog_add_entry "$mirror_id" "auto" "Custom" "$requested_url" "user" false true || return "$EXIT_GENERAL"
    _write_user_mirror_catalog || {
      error "Could not save the custom mirror catalog."
      return "$EXIT_GENERAL"
    }
    info "Saved custom mirror: $mirror_id"
    ;;
  remove | disable | enable)
    mirror_id="$MIRROR_MANAGEMENT_VALUE"
    for i in "${!_CATALOG_IDS[@]}"; do
      if [[ "${_CATALOG_IDS[$i]}" == "$mirror_id" && "${_CATALOG_SOURCES[$i]}" == user ]]; then
        target_index="$i"
        break
      fi
    done
    if ((target_index < 0)); then
      error "Custom mirror ID not found: $mirror_id"
      return "$EXIT_USAGE"
    fi
    if [[ "$MIRROR_MANAGEMENT_ACTION" == disable && "${_CATALOG_ENABLED[$target_index]}" == false ]]; then
      info "Custom mirror is already disabled: $mirror_id"
      return 0
    fi
    if [[ "$MIRROR_MANAGEMENT_ACTION" == enable && "${_CATALOG_ENABLED[$target_index]}" == true ]]; then
      info "Custom mirror is already enabled: $mirror_id"
      return 0
    fi
    printf 'Mirror ID: %s\nURL: %s\nAction: %s\n' "$mirror_id" "${_CATALOG_URLS[$target_index]}" "$MIRROR_MANAGEMENT_ACTION"
    _confirm_action "Apply this custom catalog change?" || confirm_status=$?
    [[ "$confirm_status" -eq 0 ]] || return "$confirm_status"
    _acquire_mutation_lock

    if [[ "$MIRROR_MANAGEMENT_ACTION" == remove ]]; then
      local -a ids=() countries=() regions=() urls=() sources=() officials=() enabled=()
      for i in "${!_CATALOG_IDS[@]}"; do
        ((i == target_index)) && continue
        ids+=("${_CATALOG_IDS[$i]}")
        countries+=("${_CATALOG_COUNTRIES[$i]}")
        regions+=("${_CATALOG_REGIONS[$i]}")
        urls+=("${_CATALOG_URLS[$i]}")
        sources+=("${_CATALOG_SOURCES[$i]}")
        officials+=("${_CATALOG_OFFICIAL[$i]}")
        enabled+=("${_CATALOG_ENABLED[$i]}")
      done
      _CATALOG_IDS=("${ids[@]}")
      _CATALOG_COUNTRIES=("${countries[@]}")
      _CATALOG_REGIONS=("${regions[@]}")
      _CATALOG_URLS=("${urls[@]}")
      _CATALOG_SOURCES=("${sources[@]}")
      _CATALOG_OFFICIAL=("${officials[@]}")
      _CATALOG_ENABLED=("${enabled[@]}")
    elif [[ "$MIRROR_MANAGEMENT_ACTION" == disable ]]; then
      _CATALOG_ENABLED[target_index]=false
    else
      _CATALOG_ENABLED[target_index]=true
    fi

    _write_user_mirror_catalog || {
      error "Could not save the custom mirror catalog."
      return "$EXIT_GENERAL"
    }
    info "Custom mirror catalog updated: $mirror_id"
    ;;
  *)
    error "Unknown custom mirror management action."
    return "$EXIT_USAGE"
    ;;
  esac
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
    local forced_url result_file result_line eligible score avg_latency main_code updates_code security_code redirects freshness signature reason
    forced_url="$(_validate_mirror_url "$FORCE_MIRROR")" || {
      error "Invalid Ubuntu mirror URL: $FORCE_MIRROR"
      return "$EXIT_USAGE"
    }
    if _uses_ports_archive && [[ "$forced_url" != */ubuntu-ports ]]; then
      error "Architecture $(_apt_architecture) requires a mirror URL ending in /ubuntu-ports."
      return "$EXIT_USAGE"
    fi
    if ! _uses_ports_archive && [[ "$forced_url" == */ubuntu-ports ]]; then
      error "A ports archive URL cannot be used on architecture $(_apt_architecture)."
      return "$EXIT_USAGE"
    fi
    if _uses_ports_archive && [[ "$forced_url" != */ubuntu-ports ]]; then
      error "Architecture $(_apt_architecture) requires a mirror URL ending in /ubuntu-ports."
      return "$EXIT_USAGE"
    fi
    if ! _uses_ports_archive && [[ "$forced_url" == */ubuntu-ports ]]; then
      error "A ports archive URL cannot be used on architecture $(_apt_architecture)."
      return "$EXIT_USAGE"
    fi
    if [[ "$OFFICIAL_ONLY" == true ]] && ! _catalog_url_is_official "$forced_url"; then
      error "The specified mirror is not in the built-in official Ubuntu mirror profile."
      return "$EXIT_USAGE"
    fi

    _print_section_header "VERIFYING SPECIFIED MIRROR"
    msg "  Mirror: ${COLOR_BOLD}${forced_url}${COLOR_RESET}"
    result_file="$(mktemp "${TMPDIR:-/tmp}/${APP_SLUG}.force.XXXXXX")"
    _tmp_dirs+=("$result_file")
    _test_mirror "$forced_url" "$result_file" "$CODENAME"
    result_line="$(cat "$result_file" 2>/dev/null || true)"
    rm -f "$result_file" 2>/dev/null || true
    IFS='|' read -r eligible score avg_latency main_code updates_code security_code redirects freshness signature reason <<<"$result_line"
    if [[ "$eligible" == true ]]; then
      SELECTED_MIRROR="$forced_url"
      SELECTED_TIME="$avg_latency"
    else
      error "Specified mirror failed Ubuntu compatibility verification: ${reason:-unknown reason}"
      return "$EXIT_NO_MIRROR"
    fi
  else
    _select_mirror || return $?
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
_run_prune_backups() {
  if [[ "$YES" != true ]] && ! _is_interactive; then
    error "Non-interactive backup cleanup requires --yes."
    return "$EXIT_USAGE"
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    error "Backup cleanup must be run as root."
    return "$EXIT_NOT_ROOT"
  fi
  [[ -d "$BACKUP_BASE" ]] || {
    info "No backup directory exists; nothing to clean."
    return 0
  }

  local listing line path valid_count=0 removed_count=0 confirm_status=0
  local -a valid_backups=()
  listing="$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' 2>/dev/null | sort -rn || true)"
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    [[ -n "$path" && "$(dirname "$path")" == "$BACKUP_BASE" && ! -L "$path" ]] || continue
    [[ -f "$path/manifest" && ! -L "$path/manifest" && -f "$path/apt-config.tar" && ! -L "$path/apt-config.tar" && -f "$path/archive.sha256" && ! -L "$path/archive.sha256" ]] || continue
    grep -qx 'format=1' "$path/manifest" || continue
    (cd "$path" && sha256sum -c archive.sha256 >/dev/null 2>&1) || continue
    valid_backups+=("$path")
    ((valid_count += 1))
  done <<<"$listing"

  if ((valid_count <= PRUNE_BACKUPS_KEEP)); then
    info "Found $valid_count verified snapshot(s); retention limit is $PRUNE_BACKUPS_KEEP. Nothing to remove."
    return 0
  fi
  printf 'Verified snapshots: %s\nRetention count: %s\n' "$valid_count" "$PRUNE_BACKUPS_KEEP"
  _confirm_action "Remove $((valid_count - PRUNE_BACKUPS_KEEP)) older verified backup snapshot(s)?" || confirm_status=$?
  [[ "$confirm_status" -eq 0 ]] || return "$confirm_status"
  _acquire_mutation_lock
  local i
  for ((i = PRUNE_BACKUPS_KEEP; i < valid_count; i++)); do
    path="${valid_backups[$i]}"
    [[ "$(dirname "$path")" == "$BACKUP_BASE" && ! -L "$path" ]] || return "$EXIT_RESTORE"
    rm -rf -- "$path" || {
      error "Could not remove verified backup snapshot: $path"
      return "$EXIT_RESTORE"
    }
    ((removed_count += 1))
  done
  info "Removed $removed_count old verified snapshot(s); retained the $PRUNE_BACKUPS_KEEP newest."
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
    if [[ "$RESTORE_SCOPE" != network ]]; then apt-get update >&2 || return "$EXIT_NETWORK"; fi
    _print_json
  else
    _restore_backup "$selected_backup" || return "$EXIT_RESTORE"
    if [[ "$RESTORE_SCOPE" != network ]]; then
      apt-get update || return "$EXIT_NETWORK"
      info "APT sources restored and updated successfully."
    else
      info "APT network settings restored; package indexes were not changed."
    fi
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

_menu_manage_mirrors() {
  local choice value rc old_network_setting="$NO_CATALOG_NETWORK" i listing
  NO_CATALOG_NETWORK=true
  _load_mirror_catalog
  NO_CATALOG_NETWORK="$old_network_setting"

  while true; do
    choice="$(
      _menu_choose "Custom Ubuntu Mirrors" "Manage app-owned custom mirror entries" \
        "list" "List saved custom mirrors" \
        "add" "Add and verify a mirror URL" \
        "disable" "Disable a saved custom mirror" \
        "enable" "Enable a saved custom mirror" \
        "remove" "Remove a saved custom mirror" \
        "back" "Back"
    )" || return 0

    case "$choice" in
    list)
      listing=""
      for i in "${!_CATALOG_IDS[@]}"; do
        [[ "${_CATALOG_SOURCES[$i]}" == user ]] || continue
        listing+="${_CATALOG_IDS[$i]} | ${_CATALOG_ENABLED[$i]} | ${_CATALOG_URLS[$i]}"$'\n'
      done
      [[ -n "$listing" ]] || listing="No custom mirrors have been saved."
      _menu_message "Custom mirrors" "$listing"
      ;;
    add)
      value="$(_menu_input "Add custom mirror" "Ubuntu mirror base URL (must serve signed InRelease files)" "https://")" || continue
      MIRROR_MANAGEMENT_ACTION="add"
      MIRROR_MANAGEMENT_VALUE="$value"
      rc=0
      _run_mirror_management || rc=$?
      [[ "$rc" -eq 0 || "$rc" -eq "$EXIT_CANCELLED" ]] || _menu_message "Custom mirror result" "Add operation finished with exit code $rc."
      ;;
    disable | enable | remove)
      listing=""
      for i in "${!_CATALOG_IDS[@]}"; do
        [[ "${_CATALOG_SOURCES[$i]}" == user ]] || continue
        listing+="${_CATALOG_IDS[$i]} | ${_CATALOG_ENABLED[$i]} | ${_CATALOG_URLS[$i]}"$'\n'
      done
      [[ -n "$listing" ]] || {
        _menu_message "Custom mirrors" "There are no saved custom mirrors to change."
        continue
      }
      _menu_message "Saved custom mirror IDs" "$listing"
      value="$(_menu_input "Custom mirror ID" "Enter the exact ID shown above" "")" || continue
      MIRROR_MANAGEMENT_ACTION="$choice"
      MIRROR_MANAGEMENT_VALUE="$value"
      rc=0
      _run_mirror_management || rc=$?
      [[ "$rc" -eq 0 || "$rc" -eq "$EXIT_CANCELLED" ]] || _menu_message "Custom mirror result" "Operation finished with exit code $rc."
      ;;
    back) return 0 ;;
    esac

    old_network_setting="$NO_CATALOG_NETWORK"
    NO_CATALOG_NETWORK=true
    _load_mirror_catalog
    NO_CATALOG_NETWORK="$old_network_setting"
  done
}

_menu_apt() {
  local choice rc
  while true; do
    choice="$(
      _menu_choose "APT Management" "Choose an action" \
        "apply_best" "Find and apply the fastest mirror" \
        "apply_custom" "Test and apply a custom mirror" \
        "list" "List and test available mirrors" \
        "manage" "Manage custom mirrors" \
        "back" "Back to main menu"
    )" || return 0
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
    manage) _menu_manage_mirrors ;;
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
  choice="$(
    _menu_choose "Diagnostics" "Choose a report" \
      "status" "System status" \
      "doctor" "Run local health checks" \
      "back" "Back to main menu"
  )" || return 0
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
    choice="$(
      _menu_choose "Settings" "Settings apply to this session only" \
        "timeout" "Probe timeout: ${TIMEOUT_TOTAL}s" \
        "country" "Country filter: ${COUNTRY_FILTER:-all}" \
        "workers" "Benchmark workers: ${BENCH_WORKERS}" \
        "retries" "Probe retries: ${PROBE_RETRIES}" \
        "official" "Official-only profile: $([[ "$OFFICIAL_ONLY" == true ]] && echo enabled || echo disabled)" \
        "refresh" "Refresh Ubuntu mirror catalog on next run" \
        "ipv6" "IP family: $([[ "$USE_IPV6" == true ]] && echo IPv6 || echo IPv4)" \
        "spinner" "Spinner: $([[ "$NO_SPINNER" == true ]] && echo disabled || echo enabled)" \
        "back" "Back to main menu"
    )" || return 0
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
    workers)
      value="$(_menu_input "Benchmark workers" "Enter a value from 1 to $MAX_WORKERS_LIMIT" "$BENCH_WORKERS")" || continue
      if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= MAX_WORKERS_LIMIT)); then
        BENCH_WORKERS="$value"
      else
        _menu_message "Invalid worker count" "Enter a whole number from 1 to $MAX_WORKERS_LIMIT."
      fi
      ;;
    retries)
      value="$(_menu_input "Probe retries" "Enter a value from 0 to 3" "$PROBE_RETRIES")" || continue
      if [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 0 && value <= 3)); then
        PROBE_RETRIES="$value"
      else
        _menu_message "Invalid retry count" "Enter a whole number from 0 to 3."
      fi
      ;;
    official)
      [[ "$OFFICIAL_ONLY" == true ]] && OFFICIAL_ONLY=false || OFFICIAL_ONLY=true
      ;;
    refresh)
      REFRESH_CATALOG=true
      _menu_message "Catalog refresh" "The Ubuntu mirror catalog will be refreshed the next time you list or benchmark mirrors."
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
    choice="$(
      _menu_choose "$APP_NAME v$APP_VERSION" "Main menu" \
        "overview" "Overview" \
        "apt" "APT management" \
        "benchmark" "Mirror benchmark" \
        "backups" "Backup and Restore" \
        "diagnostics" "Diagnostics" \
        "settings" "Settings" \
        "quit" "Exit"
    )" || return 0
    case "$choice" in
    overview) _menu_overview ;;
    apt) _menu_apt ;;
    benchmark) _menu_benchmark ;;
    backups) _menu_backups ;;
    diagnostics) _menu_diagnostics ;;
    settings) _menu_settings ;;
    quit) return 0 ;;
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

  if [[ "$MIRROR_MANAGEMENT_REQUESTED" == true ]]; then
    local mirror_management_status=0
    _run_mirror_management || mirror_management_status=$?
    [[ "$mirror_management_status" -eq "$EXIT_CANCELLED" ]] && mirror_management_status="$EXIT_OK"
    exit "$mirror_management_status"
  fi

  if [[ "$LIST_REQUESTED" == true ]]; then
    local list_status=0
    _run_list_flow || list_status=$?
    exit "$list_status"
  fi

  if [[ -n "$PRUNE_BACKUPS_KEEP" ]]; then
    local prune_status=0
    _run_prune_backups || prune_status=$?
    [[ "$prune_status" -eq "$EXIT_CANCELLED" ]] && prune_status="$EXIT_OK"
    exit "$prune_status"
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
