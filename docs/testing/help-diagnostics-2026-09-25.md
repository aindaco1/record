# Help and diagnostics validation — September 25, 2026

## Scope

Record 1.4.6 combines the already merged updater migration (PR 91) with the
Paper-style Help & diagnostics workflow. Platform remains pinned to the same
reviewed commit; the report schema, UI and XPC adapter belong to Record. The
owner explicitly authorized public submission of the filtered preview.

## Automated and local artifact evidence

- `./scripts/ci/validate.sh` (full path via the local gate): passed.
- `./scripts/ci/local-gate.sh`: passed normal tests, ThreadSanitizer,
  AddressSanitizer, source/privacy and entitlement checks, arm64 builds,
  signed package layout, DMG/ZIP checksums and signed test appcast generation.
  The existing external real-session fixture remains skipped when not supplied.
- New native cases cover projection privacy, wrong-app and oversized incidents,
  canonical helper input, retry identity across relaunch, no implicit sends,
  in-flight report locking and duplicate-click rejection, update-guard cleanup,
  bounded file reads and menu callback wiring.
- `scripts/qa/report-sender-smoke.sh`: the real packaged XPC service rejects
  synthetic private input before transport from a sandboxed disposable host.
  This is not a live report submission.
- Record's contract fixture passes the JavaScript relay validator; unknown/private
  fields and mismatched crash versions are rejected. App-owned adapter copies
  are byte-identical to the relay PR.
- The complete relay suite passes (57 tests), and Wrangler deployment dry run
  passes. [Relay PR 45](https://github.com/aindaco1/ascii-vj-remix/pull/45) adds
  Record to the existing Platform-backed grouping and GitHub delivery flow.
- `RECORD_VERSION=1.4.6 RECORD_BUILD_NUMBER=146 ./script/build_and_run.sh --verify`
  successfully assembled, signed and launched the candidate. The main app has no
  incoming/outgoing network entitlement; both dedicated helpers have exactly
  sandbox and outbound-network entitlements.

## Acceptance still pending

Native computer-use calls timed out on the menu-only Record process, including
calls targeting the exact installed app. Visual window and file-panel acceptance
is pending, not inferred from tests or process launch. The user was asked to open
the new window to permit inspection.

The Record endpoint's production deployment, GitHub App repository access and
synthetic live create/duplicate/aggregate/reopen checks remain pending. No private
report or recording was submitted. Public release, notarization, downloaded
artifact verification and the prior-release Sparkle replacement remain the
release runbook's separate gates; 1.4.6 is held until the combined change is ready.
