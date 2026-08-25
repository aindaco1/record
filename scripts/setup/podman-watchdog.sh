#!/bin/bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/podman-cli.sh
source "$script_dir/podman-cli.sh"

machine_name="${RECORD_PODMAN_MACHINE_NAME:-podman-machine-default}"
machine_provider="${RECORD_PODMAN_MACHINE_PROVIDER:-libkrun}"
podman_cli="$(resolve_podman_cli || true)"

export CONTAINERS_MACHINE_PROVIDER="$machine_provider"

log() {
    /bin/echo "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

if [[ -z "$podman_cli" || ! -x "$podman_cli" ]]; then
    log "Podman CLI is not installed"
    exit 1
fi

for attempt in 1 2 3; do
    if "$podman_cli" --connection "$machine_name" info >/dev/null 2>&1; then
        exit 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
        /bin/sleep 5
    fi
done

machine_state="$($podman_cli machine inspect "$machine_name" \
    --format '{{.State}}' 2>/dev/null || true)"

if [[ "$machine_state" == "running" ]]; then
    log "machine reports running but is unreachable; restarting it"
    "$podman_cli" machine stop "$machine_name" || true
    /bin/sleep 2
else
    log "machine is unreachable with state ${machine_state:-unknown}; starting it"
fi

if ! "$podman_cli" machine start "$machine_name"; then
    log "Podman machine start failed"
    exit 1
fi

for attempt in 1 2 3 4 5 6; do
    if "$podman_cli" --connection "$machine_name" info >/dev/null 2>&1; then
        log "Podman machine is healthy"
        exit 0
    fi
    /bin/sleep 5
done

log "Podman machine did not become healthy within 30 seconds"
exit 1
