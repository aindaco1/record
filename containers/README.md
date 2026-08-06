# Containers

Record uses rootless Podman for portable repository tooling only. The pinned
images invoked by `scripts/ci/container-lint.sh` provide reproducible
`actionlint` and `shellcheck` execution without adding those tools to the Mac.

```sh
./scripts/ci/container-lint.sh
```

The script selects reviewed, platform-specific image digests for Apple Silicon
developer hosts and x86-64 GitHub runners. ScreenCaptureKit builds, TCC
behavior, signing, notarization, and hardware tests stay on native macOS; a
Linux Podman VM cannot validate them.
