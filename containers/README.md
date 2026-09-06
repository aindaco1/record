# Containers

Record uses rootless Podman for portable repository tooling only. The pinned
images invoked by `scripts/ci/container-lint.sh` provide reproducible
`actionlint` and `shellcheck` execution without adding those tools to the Mac.

Run commands from the repository root. See the
[contributor guide](../docs/CONTRIBUTING.md) for the complete build and
validation workflow.

```sh
./scripts/ci/container-lint.sh
```

The script selects reviewed, platform-specific image digests for Apple Silicon
developer hosts and x86-64 GitHub runners. ScreenCaptureKit builds, TCC
behavior, signing, notarization, and hardware tests stay on native macOS; a
Linux Podman VM cannot validate them.

## Set up the local gate

On macOS, install the user-level Podman watchdog once before running the local
gate:

```sh
./scripts/setup/install-podman-watchdog.sh
```

The watchdog starts the existing Podman machine at login and checks it every
five minutes. It deliberately runs through launchd with an abandoned process
group so the VM and `gvproxy` survive the one-shot start command. The local
gate and watchdog use the active `podman` on `PATH`, then the Homebrew and
package-installer locations as fallbacks, so one installation owns both the VM
and its helper processes. Set `RECORD_PODMAN_CLI` to an absolute executable
path only when an explicit override is required. Recovery never resets
machines or prunes images, containers, or volumes.

The installer defaults to `podman-machine-default` with Libkrun. To dedicate a
separate AppleHV machine to the gate, initialize it first, then install the
watchdog with matching settings:

```sh
CONTAINERS_MACHINE_PROVIDER=applehv podman machine init record-release-gate
RECORD_PODMAN_MACHINE_NAME=record-release-gate \
  RECORD_PODMAN_MACHINE_PROVIDER=applehv \
  ./scripts/setup/install-podman-watchdog.sh
podman system connection default record-release-gate
```
