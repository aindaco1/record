#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "$(uname -m)" in
    arm64 | aarch64)
        actionlint_digest="2ed5f65788d18230778f7187b1917bf5d3fcd6cb68bbc811a004078b9c935f27"
        shellcheck_digest="6646e6ce8c88047680de61ee5eddd32c0d7260628847383cd3a17db32b384efe"
        ;;
    x86_64 | amd64)
        actionlint_digest="1d74bfc9fd1963af8f89a7c22afaaafd42f49aad711a09951d02cb996398f61d"
        shellcheck_digest="7c6a5115899d99323b22fc84b29e924aef5b6fa985612e450a8c356969ebb577"
        ;;
    *)
        echo "unsupported container architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
actionlint_image="docker.io/rhysd/actionlint@sha256:$actionlint_digest"
shellcheck_image="docker.io/koalaman/shellcheck-alpine@sha256:$shellcheck_digest"

podman run --rm --pull=missing \
    --volume "$repo_root:/workspace:ro" --workdir /workspace \
    "$actionlint_image" -color

podman run --rm --pull=missing \
    --entrypoint /bin/shellcheck \
    --volume "$repo_root:/workspace:ro" --workdir /workspace \
    "$shellcheck_image" \
    scripts/ci/validate.sh \
    scripts/ci/verify-package.sh \
    scripts/ci/container-lint.sh \
    scripts/release/build-app.sh \
    scripts/release/package.sh
