#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/install.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS %s\n' "$*"; }

bash -n "$INSTALLER" || fail "installer syntax"
grep -Fq 'readonly VERSION="v3.0.5"' "$INSTALLER" || fail "pinned version"
grep -Fq 'sha256sum --check --status' "$INSTALLER" || fail "checksum verification"
grep -Fq 'sudo bash "${TMP_DIR}/${SCRIPT_NAME}" "$@"' "$INSTALLER" || fail "sudo execution"
pass "installer syntax and safety guards"

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/fixture"
cat >"$TEST_DIR/fixture/linux-package-source-manager.sh" <<'FIXTURE'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${LPSM_TEST_RESULT:?}"
FIXTURE
chmod +x "$TEST_DIR/fixture/linux-package-source-manager.sh"
(cd "$TEST_DIR/fixture" && sha256sum linux-package-source-manager.sh >linux-package-source-manager.sh.sha256)

cat >"$TEST_DIR/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
destination=""
url=""
while (($#)); do
  case "$1" in
    -fsSL) shift ;;
    -o) destination="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
cp "${LPSM_TEST_FIXTURE}/${url##*/}" "$destination"
CURL
cat >"$TEST_DIR/bin/id" <<'ID'
#!/usr/bin/env bash
printf '1000\n'
ID
cat >"$TEST_DIR/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" != "-v" ]] || exit 0
exec "$@"
SUDO
chmod +x "$TEST_DIR/bin/"*
export PATH="$TEST_DIR/bin:$PATH"
export LPSM_TEST_FIXTURE="$TEST_DIR/fixture"
export LPSM_TEST_RESULT="$TEST_DIR/result"

bash "$INSTALLER" alpha beta
[[ "$(cat "$TEST_DIR/result")" == "alpha beta" ]] || fail "argument forwarding"
pass "verified execution and argument forwarding"

rm -f "$TEST_DIR/result"
printf 'tampered\n' >>"$TEST_DIR/fixture/linux-package-source-manager.sh"
set +e
bash "$INSTALLER" >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 && ! -e "$TEST_DIR/result" ]] || fail "tampered payload was executed"
pass "tampered payload rejected before execution"
