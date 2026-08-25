#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/podman-cli.sh"
podman_cli="$(resolve_podman_cli || true)"

if [[ -z "$podman_cli" ]]; then
    echo "Podman is required for pinned container linting" >&2
    exit 1
fi

if "$podman_cli" info >/dev/null 2>&1; then
    printf '%s\n' "$podman_cli"
    exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Podman is installed but unreachable" >&2
    exit 1
fi

launch_agent_label="com.aindaco.record.podman-machine"
launch_agent_target="gui/$(id -u)/$launch_agent_label"

if ! launchctl print "$launch_agent_target" >/dev/null 2>&1; then
    echo "Podman is unreachable and the Record development watchdog is not installed." >&2
    echo "Run ./scripts/setup/install-podman-watchdog.sh once, then retry." >&2
    exit 1
fi

launchctl kickstart -k "$launch_agent_target"
for ((attempt = 0; attempt < 12; attempt++)); do
    if "$podman_cli" info >/dev/null 2>&1; then
        printf '%s\n' "$podman_cli"
        exit 0
    fi
    sleep 5
done

echo "Podman did not become healthy within 60 seconds" >&2
exit 1
