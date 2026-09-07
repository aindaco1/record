# Record documentation

Start with [installation and requirements](../README.md), then choose the
relevant guide below. Commands in these guides run from the repository root
unless a procedure says otherwise.

## Use Record

- [User guide](user-guide.md): screenshots, shortcuts, recording sources,
  settings, local transcription, recovery, updates, and uninstalling.
- [Parakeet model setup](models/parakeet.md): verified in-app download, manual
  import, and developer setup.
- [Advanced configuration](configuration.md): the versioned JSON schema,
  transcription policy, and local completion hooks.
- [Support](SUPPORT.md): supported platforms and safe bug reporting.
- [Privacy policy](PRIVACY.md): permissions, data handling, and retention.
- [Security policy](SECURITY.md): supported security-update versions and private
  vulnerability reporting.

## Contribute

- [Contributor guide](CONTRIBUTING.md): development setup, build and validation
  commands, dependency review, and pull requests.
- [Container tooling](../containers/README.md): Podman setup and watchdog
  operation for the local gate.
- [Repository instructions](../AGENTS.md): requirements for automated contributors.
- [Roadmap](project/roadmap.md): current direction, deferred ideas, and non-goals.
- [GitHub issues](https://github.com/aindaco1/record/issues): live issue status
  and acceptance criteria.

## Architecture and security

- [Architecture](architecture.md): module ownership, session format, and shared
  state boundaries.
- [Local-only enforcement](security/local-only-boundary.md): security invariants,
  sandbox and helper boundaries, limitations, and verification.
- [ScreenCaptureKit adapter](capture/screencapturekit.md): source selection,
  permission routing, and capture callbacks.
- [Bounded media ingress](media/bounded-ingress.md): asynchronous media handoff.
- [Hardware segment writer](media/segment-writer.md): encoding and finalization.
- [Architecture decision records](adr/): numbered decisions and their rationale.
- [Third-party notices](../THIRD_PARTY_NOTICES.md) and
  [Parakeet model attribution](models/PARAKEET_MODEL_ATTRIBUTION.md): provenance
  and bundled or separately distributed notices.

## Test and release

- [Testing strategy and acceptance](testing.md): automated gates, manual smoke
  procedures, hardware matrices, and performance criteria.
- [macOS 27 readiness](testing/macos-27-readiness.md): dated platform findings
  and criteria for promoting the preview toolchain.
- [Release runbook](runbooks/release.md): candidate preparation, signing,
  publication, and post-release verification.
- [GitHub Actions outage runbook](runbooks/github-actions-outage.md): incident
  handling and recovery.
- [Changelog](../CHANGELOG.md): unreleased work and versioned change history.
- [Release notes](releases/): user-facing notes for each published version,
  including [Record 1.4.1](releases/1.4.1.md).

## Historical records

These records describe the version or date in their title. They preserve what
was planned or observed at that time; use the live tracker for issue status and
collect fresh evidence for a new release. Candidate checks, public-asset
verification, and installed-app or hardware acceptance remain separate claims.

- [Record 1.4.0 candidate validation](testing/1.4.0-candidate.md): pre-publication
  local evidence and the acceptance still outstanding at that review.
- [Source selection and pause/recovery review](testing/source-and-recovery-2026-09-07.md):
  September 7 checks, completed #26 acceptance, and the remaining #9 qualifications.
- [Record 1.4.1 release verification](testing/1.4.1-release.md): public artifacts,
  the previous-version updater, and installed capture checks.
- Issue-triage snapshots: [1.3.0](project/issue-triage-1.3.0.md),
  [1.1.3](project/issue-triage-1.1.3.md), [1.1.0](project/issue-triage-1.1.0.md),
  [1.0.3](project/issue-triage-1.0.3.md), [1.0.2](project/issue-triage-1.0.2.md),
  and [August 7, 2026](project/issue-triage-2026-08-07.md).
- [Quill migration ledger](migration/quill-triage.md): upstream issue and
  pull-request decisions reviewed during the migration.

## Maintain these docs

Keep everyday instructions in the user guide, developer procedures in the
contributor guide, and enforcement details in the local-only boundary document.
Other pages should summarize and link to those guides. The roadmap describes
future work; the changelog and release notes describe shipped changes. ADRs
retain decision history, and dated evidence records retain their original scope.

Keep `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` directly in this
directory so GitHub can discover them.
Update relative links whenever a document moves. The repository root retains
its overview, license, repository-wide agent instructions, changelog linked by
the updater, and notices copied into the app bundle.

Run `./scripts/ci/validate.sh` after documentation edits. Eligible changes use
the offline documentation gate; the [contributor guide](CONTRIBUTING.md#build-and-validate)
explains the scope and full-validation overrides.
