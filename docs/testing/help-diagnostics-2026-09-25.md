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
  The probe gives its disposable bundle and copied helper unique identities,
  retaining the helper's entitlements, to avoid collisions with production
  sandbox containers. Reusing a test identity across ad hoc and Developer ID
  signatures stalled in macOS sandbox initialization before main; isolation
  resolved it, and an external timeout bounds future infrastructure failures.
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

## Signed-app visual acceptance

Native computer-use calls timed out on the menu-only Record process, including
calls targeting the exact installed app. After the user opened Help & diagnostics,
the signed 1.4.6 window was inspected directly. The preview and controls were
readable, Refresh created a new report ID, and local export produced the reviewed
JSON on disk. Import cancellation and invalid synthetic input preserved the prior
preview. A valid synthetic incident produced the expected allowlisted summary,
excluding fabricated paths, names and symbols; Refresh removed the crash summary.
No actual diagnostic report was sent during the visual checks.

## Live relay acceptance

The existing relay was deployed from `df012070a526b2b504f825aef59c7239df945c56`
by [deployment 36131834810](https://github.com/aindaco1/ascii-vj-remix/actions/runs/36131834810),
Cloudflare version `a0f12e77-4abd-43fa-8334-f6b920714557`. The owner added Record
to the existing GitHub App installation after its issue-create request returned
403. The same pending report then succeeded without increasing its count twice.

The signed packaged helper's explicit synthetic mode used fixed app version
`0.0.0`, build `99999999`, OS `15.0.0` and a fabricated crash. It exercised the
production endpoint and created [synthetic issue 94](https://github.com/aindaco1/record/issues/94):

- Creation after failed delivery retained count 1.
- Repeating the same ID returned a duplicate receipt; issue body and count were
  unchanged.
- Closing the issue, then submitting a second ID with the same crash, reopened
  that same issue with count 2.
- Both published projections exactly matched the fixed synthetic JSON.

The synthetic issue was closed after verification. No actual diagnostic report,
recording, transcript or raw incident was sent. The main app's send-state UI is
covered by deterministic client tests; live transport used the isolated signed
helper host described above.

## Security scan and release acceptance

The combined feature's [main CI](https://github.com/aindaco1/record/actions/runs/36131246541)
passed at `312dfa9095b9267a754438bc3518228ec786a46a`. CodeQL failed before source
compilation when its rewritten `sandbox-exec` could not launch on the runner.
[PR 93](https://github.com/aindaco1/record/pull/93) confines the workaround to
SwiftPM's build-time manifest sandbox in the isolated security scan. Normal
builds, release packaging and application/helper entitlements retain their guards;
the full security scan must pass before release.

Public release, notarization, downloaded-artifact verification and the prior-release
Sparkle replacement remain the release runbook's separate gates; 1.4.6 is held until
the combined change and post-merge checks are ready.
