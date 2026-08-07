# ADR 0006: Shared local speech primitives

## Status

Accepted on 2026-08-07.

## Context

Record's Parakeet integration was implemented inside the app executable. The
Podcast Visualizer also needs the same pinned FluidAudio model loading,
word-timing, offline-mode, and error behavior. Copying that engine would allow
the two products to drift on privacy controls and model semantics.

FluidAudio also exposes an offline batch diarizer suitable for assigning
anonymous speaker colors. Its manager does not yet declare `Sendable`, even
though its initialized model handles are read-only and the intended use here is
serialized ownership.

## Decision

Expose a `RecordSpeech` SwiftPM library product containing:

- the fail-closed FluidAudio offline policy;
- a typed Parakeet transcriber that accepts only an already-present local model
  directory and returns stable token and word timing values;
- the same pinned Parakeet v3 file allowlist and streaming SHA-256 verifier used
  by Record's model importer;
- a bounded offline diarization adapter that returns anonymous cluster turns
  and caps the result at six speakers.

Record's existing `ParakeetEngine` remains responsible for app-specific
transcript segmentation and adapts the shared result into Record's domain
types. `OfflineSpeakerDiarizer` serializes access in an actor and supplies a
narrow audited `@unchecked Sendable` conformance for FluidAudio's offline
manager until upstream provides one.

The shared library does not download models. Every preparation path enforces
`ModelHub.offlineMode` immediately before loading explicit local assets.

## Consequences

- Record and sibling local tools share one Parakeet implementation and pinned
  FluidAudio revision.
- Product-specific storage, review, and transcript contracts remain outside
  the shared target.
- Consumers still own model allowlists and installation UX.
- A future FluidAudio `Sendable` declaration can replace the temporary audited
  conformance without changing the public API.
