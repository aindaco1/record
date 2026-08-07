#!/usr/bin/env bash

# Select a stable local signing identity so macOS TCC grants remain valid after
# a rebuild. The caller decides whether an empty result may fall back to ad hoc
# signing. Arguments are used instead of reading the keychain here so this
# policy stays deterministic and unit-testable.
select_local_codesign_identity() {
    local requested_identity="${1:-}"
    local available_identities="${2:-}"
    local selected_identity

    if [[ -n "$requested_identity" ]]; then
        printf '%s\n' "$requested_identity"
        return
    fi

    selected_identity="$(
        printf '%s\n' "$available_identities" \
            | /usr/bin/awk '/"Developer ID Application:/ { print $2; exit }'
    )"
    if [[ -z "$selected_identity" ]]; then
        selected_identity="$(
            printf '%s\n' "$available_identities" \
                | /usr/bin/awk '/"Apple Development:/ { print $2; exit }'
        )"
    fi
    printf '%s\n' "$selected_identity"
}
