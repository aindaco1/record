#!/bin/bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Works both in the repository and in the installed Application Support folder.
helper="$script_dir/podman-cli.sh"
[ -f "$helper" ] || helper="$script_dir/../lib/podman-cli.sh"
# shellcheck source=scripts/lib/podman-cli.sh
source "$helper"
podman_cli="$(resolve_podman_cli || true)"
log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }
if [[ -z "$podman_cli" || ! -x "$podman_cli" ]]; then
    log "Podman CLI is not installed"
    exit 1
fi
# An operator can pause login/interval startup during an intentional shutdown.
[[ ! -e "$script_dir/podman-maintenance" ]] || exit 0

# launchd serializes scheduled and requested runs. Project launchers consume
# the engine and never start/restart it. Do not override the configured provider.
if "$podman_cli" info >/dev/null 2>&1; then exit 0; fi
# Explicit remote endpoints are not local VMs for this watchdog to manage.
if [[ -n "${CONTAINER_HOST:-}${CONTAINER_CONNECTION:-}" ]]; then
    log "Explicit Podman endpoint is unreachable; leaving its lifecycle to the owner"
    exit 1
fi
machines="$($podman_cli machine list --format '{{.Name}} {{.Running}} {{.Starting}}' 2>/dev/null)" || exit 1
active="$(printf '%s\n' "$machines" | awk '$2 == "true" || $3 == "true" {sub(/\*$/, "", $1); print $1}')"
if [[ -n "$active" ]]; then
    log "Podman API is unreachable while a machine is active; leaving all workloads intact. Check the default connection and machine logs."
    exit 1
fi
connection="$($podman_cli system connection list --format '{{if .Default}}{{.Name}}{{end}}' 2>/dev/null | awk 'NF {print; exit}')"
machine_name="${RECORD_PODMAN_MACHINE_NAME:-${connection%-root}}"
if [[ -z "$machine_name" ]] || ! "$podman_cli" machine inspect "$machine_name" >/dev/null 2>&1; then
    log "The default connection has no local machine; initialize/select one explicitly"
    exit 1
fi
state="$($podman_cli machine inspect "$machine_name" --format '{{.State}}')" || exit 1
if [[ "$state" != "stopped" ]]; then
    log "Machine is $state; waiting for its owner rather than restarting it"
    exit 1
fi
log "Starting selected shared Podman machine: $machine_name"
# Recheck the maintenance marker just before the sole lifecycle mutation.
[[ ! -e "$script_dir/podman-maintenance" ]] || exit 0
if ! "$podman_cli" machine start "$machine_name" </dev/null; then
    log "Machine start failed or another caller is starting it; no recovery restart attempted"
fi
for _ in 1 2 3 4 5 6; do
    if "$podman_cli" info >/dev/null 2>&1; then
        log "Podman engine is healthy"
        exit 0
    fi
    sleep 5
done
log "Podman did not become reachable; no running machine was restarted"
exit 1
