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
    '[[ "$*" == "--connection test-machine info" ]]' \
    > "$watchdog_cli"
chmod +x "$watchdog_dir/watchdog.sh" "$watchdog_cli"

RECORD_PODMAN_CALL_LOG="$watchdog_calls" \
    RECORD_PODMAN_CLI="$watchdog_cli" \
    RECORD_PODMAN_MACHINE_NAME=test-machine \
    "$watchdog_dir/watchdog.sh"
[[ "$(cat "$watchdog_calls")" == "--connection test-machine info" ]] \
    || fail "watchdog did not health-check its managed connection"

echo "Podman CLI selection tests passed"
