# ADR 0004: Signed manual updates and native login registration

- Status: accepted
- Date: 2026-08-07

## Context

Record needs a convenient GitHub release update path without turning the
recording process into a general network client. It also needs an optional
login item without a persistent helper or hand-written LaunchAgent.

## Decision

Record uses Sparkle 2's standard updater in manual-check mode. The main app has
no network entitlement. Sparkle's sandboxed downloader and installer XPC
services perform the narrowly scoped fetch and installation. The appcast and
update archive require Ed25519 signatures; release artifacts also require
Developer ID signing and Apple notarization.

The feed URL is the immutable `appcast.xml` asset on the latest GitHub release.
Automatic and background checks are disabled. Record initiates network access
only when the user chooses **Check for Updates…**.

Record uses `SMAppService.mainApp` for **Open at Login**. The option is disabled
by default, exposes macOS's requires-approval state, and never installs a
custom daemon or LaunchAgent. Because `.notFound` may be returned before first
registration for a valid installed main app, Record treats it as an actionable
off state; `register()` remains macOS's authoritative eligibility check.

## Consequences

- Sparkle is an intentional reviewed dependency and its helper services are
  signed inside-out before the containing app.
- The app entitlements contain only Sparkle's two bundle-scoped Mach lookup
  exceptions; they still omit network client/server entitlements.
- The release environment holds the update private key. Its public key is
  compiled into the app, and the private key never enters the repository.
- A compromised GitHub release alone cannot produce an accepted update without
  the update key and Apple signing/notarization chain.
- Login behavior remains visible and revocable in macOS Login Items settings.
