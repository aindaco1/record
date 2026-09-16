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

The user-level launchd service starts the selected shared machine at login and
checks every five minutes. It keeps VM helper processes alive after startup.
The service uses `ProcessType=Interactive` because the VM and its network helper
serve interactive development apps and inherit their launch policy; background
CPU/I/O throttling is inappropriate for this shared engine. See Apple's
[launchd process classifications](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5).
Concurrent gate requests use `launchctl kickstart` without `-k`; launchd
serializes them instead of interrupting a start already in progress.

The watchdog first checks Podman's selected engine. If a VM is already active
but the API fails, it reports the problem and leaves every workload intact. It
never restarts, resets, removes, or prunes a VM. If all VMs are stopped, it starts
the machine matching the default connection. Select that once with
`podman system connection default <name>`. An explicit
`RECORD_PODMAN_MACHINE_NAME` remains an optional fallback override; the watchdog
never changes providers or stops a different active machine.

The installer pins the absolute Podman executable selected from PATH (Homebrew
then the package installer are fallbacks). `RECORD_PODMAN_CLI` can select an
explicit executable. Use the same installation for projects and the host
service, and keep the host/VM major and minor versions aligned with an in-place
`podman machine os apply` update during an idle maintenance window.

To pause automatic startup for maintenance or an intentional shutdown:

```sh
touch "$HOME/Library/Application Support/RecordDevelopment/podman-maintenance"
```

Remove that marker after maintenance and kickstart the service to resume.
Before stopping the VM, inspect `podman ps` across the shared engine. Pool,
Store, Record's ephemeral lint containers, and ASCII VJ Remix can share it;
project launchers must manage only their own containers and use distinct host
ports. No VM reset or storage prune is part of routine recovery.

Run `./scripts/ci/test-podman-cli.sh` for selection, safe failure, maintenance,
and stopped-machine startup regressions. Re-run the installer after changing
watchdog source; installed copies do not update themselves.
