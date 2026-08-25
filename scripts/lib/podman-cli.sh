#!/usr/bin/env bash

# Keep Podman machine management and remote commands on the same installation.
# Mixing the package-installer client and Homebrew's helper binaries can leave a
# machine reachable to one installation while the watchdog restarts it through
# the other.
select_podman_cli() {
    local requested_cli="${1:-}"
    shift || true

    if [[ -n "$requested_cli" ]]; then
        if [[ "$requested_cli" != /* || ! -x "$requested_cli" ]]; then
            return 1
        fi
        printf '%s\n' "$requested_cli"
        return
    fi

    local candidate
    for candidate in "$@"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

resolve_podman_cli() {
    local path_cli
    path_cli="$(command -v podman 2>/dev/null || true)"
    select_podman_cli "${RECORD_PODMAN_CLI:-}" \
        "$path_cli" \
        /opt/homebrew/bin/podman \
        /opt/podman/bin/podman
}
