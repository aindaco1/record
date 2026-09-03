# ADR 0016: Publish a versioned Parakeet model pack outside the app

- Status: accepted; in-app acquisition amended by ADR 0017
- Date: 2026-09-02

## Context

Record's verified local model importer preserves the main app's no-network
boundary, but obtaining a directory-shaped Core ML model from Hugging Face is
confusing for people who do not already use its command-line client. The
approved model is roughly 460 MB, so adding it to Git history, Git LFS, or every
application update would make source checkouts and routine updates needlessly
large.

Record 1.3.0 already opens its setup guide from the repository's current
`main` branch and can import either a selected model directory or a parent that
contains the expected directory. An easier browser download therefore does not
require a new app binary.

## Decision

Publish one immutable `Record-Parakeet-v3-aed0274.zip` asset beside the existing
v1.3.0 GitHub release. The asset contains the 17 files in
`ParakeetModelManifest.v3`, unmodified from FluidInference revision
`aed02740059203c4a87495924f685de3722ae9ce`, plus attribution, both license texts
identified by the upstream model card, and a copy of that immutable model card.
Publish a separate outer-archive SHA-256 file.

Build and publish the pack only through the manually dispatched
`publish-parakeet-model.yml` workflow. It runs in the protected `release`
environment, verifies the existing signed release tag, allows only the
repository owner to dispatch publication, downloads the immutable source with
a pinned client, verifies every file against Record's existing size and SHA-256
manifest, creates a normalized ZIP, attests it, and refuses to replace an
existing asset.

Keep the asset outside Git, `Record.app`, the DMG, Sparkle's update archive, and
the app-release `SHA256SUMS`. The main app continues to open documentation in
the user's browser and explicitly import a user-selected local folder. It gains
no model-download code or network entitlement.

## Consequences

- Existing Record 1.3.0 installations gain a simpler setup path as soon as the
  current web guide and release asset are published; version 1.3.1 is not
  required for this distribution-only change.
- Routine clones, CI builds, app downloads, and Sparkle updates remain small.
- The model pack has independent attribution, provenance, and checksum evidence
  without changing the signed 1.3.0 application artifacts or appcast.
- A future model revision requires a reviewed manifest and a new immutable asset
  name. The existing asset must never be replaced or silently retargeted.
- Record 1.3.1 later consumes this same immutable asset through the explicit,
  sandboxed download flow defined by ADR 0017.
