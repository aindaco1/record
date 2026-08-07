# GitHub issue triage for Record 1.0.3

Record 1.0.3 targets the four reliability and repository-maintenance issues
selected after 1.0.2. It does not add a new recording mode or editor.

| Issue | 1.0.3 disposition | Evidence / remaining work |
|---|---|---|
| #2 Interrupted recovery | Addressed | Media-aware startup recovery promotes playable partials, quarantines invalid partials without deleting bytes, and claims completion hooks at most once. Forced-phase fixtures and idempotence tests cover the filesystem policy. |
| #5 Capture health | Addressed in implemented capture paths | Audio callbacks use fixed-capacity writer queues; ScreenCaptureKit ingress reports queue pressure and write failure; manifests retain content-free per-track health. Long-duration 4K hardware performance remains a release practice, not a separate implementation blocker. |
| #6 Microphone route recovery | Implemented; hardware acceptance required | Default-input and AVAudioEngine changes debounce through one state machine, restart the same track, retry after failure, and pad downtime. Close after the signed-app unplug/Bluetooth smoke test passes. |
| #40 GitHub SSH signing key | Addressed | The existing public key fingerprint `SHA256:Fjw6n4LgGtGCmC+hhVym7ia3RwBA7HShQm2KTA0PWGo` is registered as a GitHub SSH signing key. Verify a signed commit through GitHub before closing. |

The remaining active product issues stay on the roadmap: source selection,
pause/resume, optional Homebrew distribution, and any deliberately narrowed
history or shortcut work. Transcript echo mitigation is delivered as a
reversible quality safeguard rather than reopening a broad audio-processing
feature: raw tracks stay unchanged and the unsuppressed transcript is retained
whenever filtering occurs.
