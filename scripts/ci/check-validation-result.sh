#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || "$1" != success ]]; then
    echo "change classification or documentation validation did not succeed" >&2
    exit 1
fi
case "$2:$3" in
    true:skipped)
        echo "Documentation validated; an app build was not required."
        ;;
    false:success)
        echo "Full Swift test, build, and package validation passed."
        ;;
    *)
        echo "required validation was missing, failed, or cancelled" >&2
        exit 1
        ;;
esac
