# ADR 0005: Verified local model import

- Status: accepted
- Date: 2026-08-07

## Context

Parakeet is Record's default transcription engine, but its roughly 460 MB model
does not belong in every application update. A missing model must be
discoverable without weakening Record's local-only boundary or risking an
untrusted model replacement.

## Decision

Record detects a missing selected Parakeet model at launch and exposes the same
setup action in the Transcript model menu. The user downloads the model from
FluidInference's immutable Hugging Face revision in a browser or external CLI,
then explicitly selects the downloaded directory.

Record has no model-download code or network entitlement. Its importer accepts
only the Parakeet v3 allowlist, rejects symbolic-link traversal, verifies exact
sizes and pinned SHA-256 hashes with bounded-memory streaming, copies into a
same-volume staging directory, re-verifies the staged files, and atomically
swaps the model into FluidAudio's cache. An existing model remains recoverable
if validation or installation fails.

## Consequences

- Recording never depends on model availability; only queued transcription is
  delayed until setup succeeds.
- Updating the approved model revision or hashes is a reviewed source change,
  not runtime remote configuration.
- Record cannot provide one-click in-process download without a separately
  sandboxed, narrowly reviewed downloader design.
- Parakeet v2 remains a configuration-compatible engine for existing local
  installations; the guided importer currently provisions the v3 default.
