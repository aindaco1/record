# ADR 0018: Lightweight validation for documentation-only changes

- Status: accepted
- Date: 2026-09-06
- Amends: [ADR 0012](0012-verified-ci-app-reuse.md)

## Context

Moving guides or correcting prose triggered Swift builds, sanitizer runs, app
packaging, and CodeQL. Those jobs do not validate the edited documentation and
recreate artifacts after routine documentation cleanup.

Required pull-request checks must still report a useful result, and release
must retain its exact-commit build, security, and provenance requirements.

## Decision

Use one conservative change classifier for local validation, CI, and CodeQL.
Only explicitly allowed, regular, non-executable Markdown takes the lightweight
path. It includes guides, ADRs, release notes, and repository instructions.
Bundled licenses/notices and model-pack attribution are excluded. Unknown
files, missing history, empty ranges, symbolic links, executable mode changes,
and any mixed source/documentation range require full validation.

Local validation compares the working tree, including untracked files, against
the merge base with `origin/main`, with an explicit base override available.
Hosted validation compares the complete PR or push range. Rename detection is
disabled so moving source into the documentation directory cannot hide it.

The offline documentation gate checks Markdown code fences, local inline and
reference links, heading anchors, and whitespace. It does not fetch external
URLs or attempt to validate every Markdown/HTML extension. Deterministic
fixtures exercise both classification and required-check failure propagation.

CI always starts a small scope/documentation job. Existing protected status
names remain available; the required build result is an aggregate that accepts
either successful documentation checks with a skipped build, or successful
documentation checks and a completed full build. A failed or cancelled
dependency cannot produce a green aggregate. Source-affecting changes retain
the existing macOS tests, packaging, sanitizers, and preview lane.

CodeQL skips only documentation-only pushes. Scheduled scans and manual CI or
CodeQL dispatches always run in full. Scan concurrency belongs to the analysis
job so a docs-only push cannot cancel an active source scan.
A full CI push or dispatch on `main`
creates and attests the exact-commit app archive described in ADR 0012.

Release requires successful full build and analysis jobs from successful push
or manual runs on the exact `main` commit. A green docs-only workflow is
insufficient. Existing attestation, source ref/digest, run identity, extraction,
signature, entitlement, and package checks remain in force. An earlier app
artifact from another commit cannot substitute for a missing candidate build.

## Consequences

- Routine documentation changes need only Python and Git locally and small
  Ubuntu jobs in CI. They produce no app or package artifacts.
- `validate.sh --full` and `local-gate.sh` always run the full local checks.
- A release following a docs-only merge needs manual full CI and CodeQL runs
  on the candidate, as described in the [release runbook](../runbooks/release.md).
- New packaged Markdown inputs must be excluded from the documentation
  allowlist when their build path is introduced.
- App behavior, local-only boundaries, and hardware acceptance are unchanged.
