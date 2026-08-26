# ADR 0011: Automatic signed update checks at launch

- Status: accepted
- Date: 2026-08-26
- Supersedes: the manual-only update cadence in ADRs 0002 and 0004

## Context

Record already ships signed Sparkle updates, but a manual-only check can leave
an infrequently visited menu-bar app behind on security and reliability fixes.
Podcast Visualizer 1.2.2 established a reviewed Dust Wave pattern for checking
the signed feed at launch without automatically installing a release or sending
product data.

## Decision

Record performs one silent background update check after Sparkle starts on each
app launch. The existing **Check for Updates…** command remains a manual
fallback and uses the same updater.

`SUEnableAutomaticChecks` authorizes the launch check. Both
`SUAllowsAutomaticUpdates` and `SUAutomaticallyUpdate` remain false, so an
available release uses Sparkle's standard prompt and downloading and
installation remain user approved. `SUEnableSystemProfiling` remains false.

The deterministic launch decision lives in `RecordCore`; the application
adapter owns the single Sparkle call. Sparkle's sandboxed downloader and
installer XPC services remain the only update network path. The main Record app
retains no incoming or outgoing network entitlement.

An update request contains no recording, transcript, clipboard, session,
diagnostic, model, local-path, or account data. Accepted appcasts and archives
still require Record's Ed25519 signatures, and release artifacts still require
Developer ID signing and Apple notarization.

## Consequences

- Opening Record discloses ordinary connection metadata to GitHub's public
  release feed even when the installed version is current.
- A current-version check is silent. When a newer signed version exists,
  Sparkle presents its standard prompt so the user can defer or install it.
- The manual update command remains available for troubleshooting and an
  immediate recheck.
- CI tests the pure launch policy and audits the packaged plist flags, signed
  feed configuration, helper services, and main-app entitlement boundary.
