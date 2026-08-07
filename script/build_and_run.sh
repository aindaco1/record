#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
if [[ $# -gt 1 ]]; then
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/local-signing.sh"
built_app="$repo_root/.build/release-artifacts/Record.app"
temporary_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
run_root="$temporary_root/record-local-run"
app_bundle="$run_root/Record.app"
app_binary="$app_bundle/Contents/MacOS/record"
process_name="record"

stop_running_app() {
    if ! pgrep -x "$process_name" >/dev/null; then
        return
    fi

    # Record handles SIGINT by finalizing the active session before exiting.
    pkill -INT -x "$process_name"
    for _ in {1..25}; do
        if ! pgrep -x "$process_name" >/dev/null; then
            return
        fi
        sleep 0.2
    done

    echo "Record did not stop cleanly; refusing to force-quit a possible recording" >&2
    exit 1
}

open_app() {
    /usr/bin/open -n "$app_bundle"
}

wait_for_launch() {
    for _ in {1..50}; do
        if pgrep -x "$process_name" >/dev/null; then
            return
        fi
        sleep 0.2
    done
    echo "Record did not remain running after launch" >&2
    exit 1
}

case "$mode" in
    run | --debug | debug | --logs | logs | --telemetry | telemetry | --verify | verify) ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac

cd "$repo_root"
stop_running_app
RECORD_VERSION="${RECORD_VERSION:-0.0.0-local}" \
    RECORD_BUILD_NUMBER="${RECORD_BUILD_NUMBER:-1}" \
    ./scripts/release/build-app.sh

case "$run_root" in
    "$temporary_root"/record-local-run) ;;
    *) echo "refusing unsafe local run path: $run_root" >&2; exit 1 ;;
esac
rm -rf "$run_root"
mkdir -p "$run_root"
ditto --norsrc --noextattr "$built_app" "$app_bundle"
available_identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
signing_identity="$(
    select_local_codesign_identity \
        "${RECORD_CODESIGN_IDENTITY:-}" \
        "$available_identities"
)"
if [[ -n "$signing_identity" ]]; then
    echo "Signing local app with stable identity $signing_identity"
    codesign --force --options runtime --timestamp=none \
        --sign "$signing_identity" \
        --entitlements Configuration/Record.entitlements "$app_bundle"
else
    echo "warning: no Apple signing identity found; TCC grants will not survive rebuilds" >&2
    codesign --force --sign - \
        --entitlements Configuration/Record.entitlements "$app_bundle"
fi
./scripts/ci/check-signed-entitlements.sh "$app_bundle"

case "$mode" in
    run)
        open_app
        ;;
    --debug | debug)
        exec /usr/bin/lldb -- "$app_binary"
        ;;
    --logs | logs)
        open_app
        wait_for_launch
        exec /usr/bin/log stream --info --style compact \
            --predicate 'process == "record"'
        ;;
    --telemetry | telemetry)
        open_app
        wait_for_launch
        exec /usr/bin/log stream --info --style compact \
            --predicate 'subsystem == "com.aindaco.record"'
        ;;
    --verify | verify)
        open_app
        wait_for_launch
        echo "Record launched successfully; use the ring in the menu bar"
        ;;
esac
