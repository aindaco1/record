# Record documentation

Start with [installation and requirements](../README.md), then choose the
relevant guide below. Commands in these guides run from the repository root
unless a procedure says otherwise.

## Use Record

- [User guide](user-guide.md): screenshots, shortcuts, recording sources,
  settings, dictation, audio-file import, local transcription, recording automation,
  recovery, updates, and uninstalling.
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
- [Handy comparison](project/handy-review-2026-10-02.md): October 2 research and
  original usability and reliability proposals, with links to the shipped 1.5.0 work.
- [Settings UX review](project/settings-ux-review-2026-10-03.md): approved sidebar
  layout, direct controls, keyboard behavior and implementation decisions.
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
- [Record 1.5.0 validation](testing/1.5.0-candidate.md): candidate history, public
  release and installed-update verification, and remaining manual coverage.
- [Transcript cleanup and Jev](testing/jev.md): local development tests,
  synthetic-only semantic evaluation, and explicit offline modes.
- [Release runbook](runbooks/release.md): preparation, signing, publication,
  and post-release verification.
- [GitHub Actions outage runbook](runbooks/github-actions-outage.md): incident
  handling and recovery.
- [Changelog](../CHANGELOG.md): user-facing changes by version.
- [Record 1.5.0 release notes](releases/1.5.0.md) and
  [earlier release notes](releases/). Version 1.4.8 was not published; its planned
  maintenance was included in 1.5.0.

## Historical records

These records describe the version or date in their title. They preserve what
was planned or observed at that time; use the live tracker for issue status and
collect fresh evidence for a new release. Candidate checks, public-asset
verification, and installed-app or hardware acceptance remain separate claims.

- [Help and diagnostics validation](testing/help-diagnostics-2026-09-25.md):
  the 1.4.6 candidate checks and coverage limits at that time.
- [Shared native migration evidence](testing/shared-native-2026-09-23.md):
  implementation comparisons and validation from September 23.
- [Apple adviser comparisons](testing/apple-adviser-2026-09-23.md) and
  [cleanup improvements](testing/cleanup-fix-2026-09-23.md): experiments and
  preservation checks that informed 1.4.5.
- [macOS 27 readiness](testing/macos-27-readiness.md): dated platform findings;
  the contributor guide and release runbook define the current toolchain.
- [Record 1.4.0 candidate validation](testing/1.4.0-candidate.md): pre-publication
  local evidence and the acceptance still outstanding at that review.
- [Source selection and pause/recovery review](testing/source-and-recovery-2026-09-07.md):
  September 7 checks, completed #26 acceptance, and the remaining #9 qualifications.
- [Record 1.4.1 release verification](testing/1.4.1-release.md): public artifacts,
  the previous-version updater, and installed capture checks.
- [Record 1.4.5 release verification](testing/1.4.5-release.md): public artifacts,
  the installed update, synthetic cleanup results and development cleanup.
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

Write changelog entries and release notes around visible features, improvements,
and fixes. Omit internal project names, dependency wiring, implementation plans,
and test-run narratives. Keep that detail in architecture, ADRs, or validation
records. Describe maintenance honestly when it changes no user behavior; do not
invent a performance or reliability benefit. Keep version dates and shipped
behavior accurate, and align release descriptions with the changelog. When a
release ships, update the overview, index, support version, and roadmap together.
Published signed assets and tags are not rewritten for a documentation edit.

Keep `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` directly in this
directory so GitHub can discover them.
Update relative links whenever a document moves. The repository root retains
its overview, license, repository-wide agent instructions, changelog linked by
the updater, and notices copied into the app bundle.

Run `./scripts/ci/validate.sh` after documentation edits. Eligible changes use
the offline documentation gate; the [contributor guide](CONTRIBUTING.md#build-and-validate)
explains the scope and full-validation overrides.
