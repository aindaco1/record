#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/podman-cli.sh"

fail() {
    echo "Podman CLI selection test failed: $1" >&2
    exit 1
}

temporary_dir="$(mktemp -d "${TMPDIR%/}/record-podman-cli.XXXXXX")"
cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

path_cli="$temporary_dir/path/podman"
homebrew_cli="$temporary_dir/homebrew/podman"
package_cli="$temporary_dir/package/podman"
override_cli="$temporary_dir/override/podman"
mkdir -p "$(dirname "$path_cli")" "$(dirname "$homebrew_cli")" \
    "$(dirname "$package_cli")" "$(dirname "$override_cli")"
touch "$path_cli" "$homebrew_cli" "$package_cli" "$override_cli"
chmod +x "$path_cli" "$homebrew_cli" "$package_cli" "$override_cli"

selected="$(select_podman_cli "" "$path_cli" "$homebrew_cli" "$package_cli")"
[[ "$selected" == "$path_cli" ]] \
    || fail "expected the active PATH client, found: $selected"

selected="$(select_podman_cli "" "" "$homebrew_cli" "$package_cli")"
[[ "$selected" == "$homebrew_cli" ]] \
    || fail "expected the Homebrew fallback, found: $selected"

selected="$(select_podman_cli "" "" "" "$package_cli")"
[[ "$selected" == "$package_cli" ]] \
    || fail "expected the package-installer fallback, found: $selected"

selected="$(select_podman_cli "$override_cli" "$path_cli" "$homebrew_cli")"
[[ "$selected" == "$override_cli" ]] \
    || fail "expected the explicit override, found: $selected"

if select_podman_cli relative/podman "$path_cli" >/dev/null; then
    fail "accepted a relative explicit override"
fi

watchdog_dir="$temporary_dir/watchdog"
watchdog_cli="$watchdog_dir/podman"
watchdog_calls="$watchdog_dir/calls"
mkdir -p "$watchdog_dir"
cp "$repo_root/scripts/setup/podman-watchdog.sh" "$watchdog_dir/watchdog.sh"
cp "$repo_root/scripts/lib/podman-cli.sh" "$watchdog_dir/podman-cli.sh"
# These lines are the literal fake CLI script.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s\n" "$*" >> "$RECORD_PODMAN_CALL_LOG"' \
    '[[ "$*" == "info" ]]' \
    > "$watchdog_cli"
chmod +x "$watchdog_dir/watchdog.sh" "$watchdog_cli"

RECORD_PODMAN_CALL_LOG="$watchdog_calls" \
    RECORD_PODMAN_CLI="$watchdog_cli" \
    RECORD_PODMAN_MACHINE_NAME=test-machine \
    "$watchdog_dir/watchdog.sh"
[[ "$(cat "$watchdog_calls")" == "info" ]] \
    || fail "watchdog did not health-check its managed connection"

echo "Podman CLI selection tests passed"

# A transient API failure must never stop an active machine, or start a second.
cat > "$watchdog_cli" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$RECORD_PODMAN_CALL_LOG"
case "$*" in
  info) exit 1 ;;
  'machine list --format {{.Name}} {{.Running}} {{.Starting}}')
    echo 'other-project* true false' ;;
  *) echo 'unexpected machine mutation' >&2; exit 99 ;;
esac
FAKE
: > "$watchdog_calls"
if RECORD_PODMAN_CALL_LOG="$watchdog_calls" RECORD_PODMAN_CLI="$watchdog_cli" \
    "$watchdog_dir/watchdog.sh" > "$watchdog_dir/output" 2>&1; then
    fail "unreachable active machine should report failure"
fi
[[ "$(wc -l < "$watchdog_calls" | tr -d ' ')" == 2 ]] \
    || fail "watchdog attempted recovery while another machine was active"
grep -q 'leaving all workloads intact' "$watchdog_dir/output" \
    || fail "missing non-disruptive diagnostic"

# Operator maintenance must suppress even health probes and startup.
touch "$watchdog_dir/podman-maintenance"
: > "$watchdog_calls"
RECORD_PODMAN_CALL_LOG="$watchdog_calls" RECORD_PODMAN_CLI="$watchdog_cli" \
    "$watchdog_dir/watchdog.sh"
[[ ! -s "$watchdog_calls" ]] || fail "watchdog ignored maintenance mode"
rm "$watchdog_dir/podman-maintenance"

# With no active VM, the selected default is the only allowed startup target.
cat > "$watchdog_cli" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$RECORD_PODMAN_CALL_LOG"
case "$*" in
  info) [[ -f "$RECORD_PODMAN_CALL_LOG.started" ]] ;;
  'machine list --format {{.Name}} {{.Running}} {{.Starting}}') echo 'shared* false false' ;;
  'system connection list --format {{if .Default}}{{.Name}}{{end}}') echo shared ;;
  'machine inspect shared') exit 0 ;;
  'machine inspect shared --format {{.State}}') echo stopped ;;
  'machine start shared') touch "$RECORD_PODMAN_CALL_LOG.started" ;;
  *) echo 'unexpected machine mutation' >&2; exit 99 ;;
esac
FAKE
: > "$watchdog_calls"
RECORD_PODMAN_CALL_LOG="$watchdog_calls" RECORD_PODMAN_CLI="$watchdog_cli" \
    "$watchdog_dir/watchdog.sh" > "$watchdog_dir/output"
grep -q '^machine start shared$' "$watchdog_calls" || fail "did not start selected machine"
! grep -Eq '^machine (stop|rm|reset)' "$watchdog_calls" || fail "destructive recovery"
echo "Shared-machine watchdog tests passed"
