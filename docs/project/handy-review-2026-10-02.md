# Handy review: improvements for Record

Review date: October 2, 2026. This historical proposal describes the baseline
and recommendations at that date, not the current app.

Status on October 4: [Record 1.5.0](../releases/1.5.0.md) shipped all six
high-priority items, language and accessibility improvements, global vocabulary,
audio-file import, Quick Dictation, and CLI/Apple Shortcuts recording controls.
Live transcript preview remains exploratory. Use the [user guide](../user-guide.md)
for current behavior and the [validation record](../testing/1.5.0-candidate.md)
for exercised workflows and remaining acceptance. The original analysis below
is retained as research history.

Record would benefit most from clearer audio controls, visible transcription
outcomes, a small session browser, and recording shortcuts. Handy provides useful
interaction patterns for these changes. Record should retain its native capture,
separate source tracks, recoverable sessions, and network-denied main app.

## Evidence and scope

- Record baseline: `2adc39a4ac1e8b1b727425b88a016b62ae9392be`. The checkout
  describes 1.4.8 as unreleased; this review does not establish an installed or
  published version.
- Handy source inspected:
  [5ec58f696354fcf64ae831102e673779e0249717](https://github.com/cjpais/Handy/tree/5ec58f696354fcf64ae831102e673779e0249717).
  The latest public release observed was
  [v0.9.7, September 18, 2026](https://github.com/cjpais/Handy/releases/tag/v0.9.7),
  tag commit `05e0aedd2906f0d82722735f930465950c476b90`. Main was compared with
  that tag; current-main changes are not assumed to be shipped.
- Record reading covered the documentation index, user/configuration/model
  guides, architecture and relevant ADRs, local-only enforcement, support,
  changelog, roadmap, testing and release procedures, shared native services,
  and dated source/recovery and transcript-cleanup evidence. Historical triage
  and release documents were used as history, not current issue status.
- Handy inspection covered onboarding, settings, shortcuts and coordinator,
  audio-device recovery, callback/drain handling, overlay, history/retry,
  vocabulary processing, model capabilities/downloads, localization, clipboard
  handling, CLI, release notes, and selected issues/merged fixes. Its bundled
  shortcut-settings screenshot was also inspected.
- This was documentation and source analysis. Neither app was installed,
  launched, recorded with, or benchmarked for this review. Reported upstream
  bugs are attributed reports, not independently reproduced results.

## Existing Record capabilities to build on

Record already has automatic recovery, bounded capture queues, microphone-route
recovery, capture-health messages, pause/resume for screen recordings, a serial
transcription queue, retry of the latest failed job, verified Parakeet setup,
optional MacWhisper, and on-device readability cleanup. It also has signed
updates, login registration, and reviewed diagnostics. These are foundations to
extend, not missing Handy features to recreate.

The [roadmap](roadmap.md) already names microphone selection as next work and
parks manifest-derived history, speech progress, localization, and accessibility.
The live [hardware acceptance issue #6](https://github.com/aindaco1/record/issues/6)
remained open when checked, including USB/Bluetooth route changes and call-length
capture. New controls do not establish that hardware acceptance.

## Priority list

P1 is the recommended first group; P2 follows once the core workflow is clearer.
Exploratory items need a separate product decision. Effort is a relative estimate,
not a schedule: S is a narrow surface change, M spans policy and adapters, and L
adds substantial lifecycle, storage, permission, or hardware work.

| Priority | Improvement | Benefit | Effort |
| --- | --- | --- | --- |
| P1 | 1. Microphone selection and audio readiness | Know which input is being captured before a meeting or take | M–L |
| P1 | 2. Per-track transcription status, progress, and retry | Make incomplete results visible and recoverable | M–L |
| P1 | 3. Recent sessions and transcript preview | Find, inspect, copy, and retry work without navigating folders | M–L |
| P1 | 4. Configurable global recording shortcuts | Start, stop, and pause without reaching for the menu | M |
| P1 | 5. Guided setup and model readiness | Make first use and setup failures understandable | M |
| P1 | 6. Optional compact recording panel | See recording, pause, audio health, and saving status at a glance | M |
| P2 | 7. Local vocabulary and reviewed corrections | Improve recurring names, titles, and technical terms | M–L |
| P2 | 8. Engine-aware language controls | Expose useful choices without promising unsupported behavior | S–M |
| P2 | 9. Localization and accessibility | Make the complete workflow usable in English/Spanish and by keyboard/VoiceOver | M |
| P2 | 10. Local file transcription and automation | Process existing audio and control Record from local tools | L |
| Explore | 11. Quick dictation mode | Turn short speech into reusable text | L |
| Explore | 12. Live transcript preview | Follow speech during capture | L |

## 1. Microphone selection and audio readiness

Handy exposes a microphone picker and, when relevant, input-channel selection.
Its [microphone UI](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/MicrophoneSelector.tsx)
and [channel UI](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/ChannelSelector.tsx)
make the active configuration visible. Its
[disconnect fix](https://github.com/cjpais/Handy/pull/1874) also demonstrates why
an open stream is not sufficient evidence that microphone samples are flowing.

For Record, add **System Default / specific microphone**, an explicit short
**Test Input** action, and separate microphone/system-audio activity indicators.
Expose microphone-only, system-only, and both-source choices through the existing
capture configuration. Add channel selection only when a multichannel device
makes it useful. The microphone preference must apply consistently to audio-only
and screen recording, which currently use different native capture adapters.

Reuse [MicRecorder](../../Sources/Record/Audio/MicRecorder.swift),
[CaptureHealth](../../Sources/RecordCore/CaptureHealth.swift), and
[CaptureAudioConfiguration](../../Sources/RecordCore/CaptureConfiguration.swift).
Distinguish silence, missing callbacks, and a disconnected input. For an explicitly
selected device, show a clear recovery choice instead of silently overwriting its
preference with another microphone. Keep default-following behavior explicit.
Device identifiers/preferences remain local and outside diagnostic reports.

Acceptance: verify both recording modes, missing selected devices, USB reconnect,
Bluetooth profile changes, Stop during recovery, and independent playable tracks.
Meters must consume bounded summaries outside capture callbacks. A test action
must visibly end microphone access when stopped or closed.

## 2. Per-track transcription status, progress, and retry

Handy's [history commands](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/commands/history.rs)
allow retrying an individual recording; its
[overlay](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/overlay/RecordingOverlay.tsx)
distinguishes capture and processing phases. Apply those ideas to Record's
two-track, post-recording workflow.

The most concrete source-level gap is in
[TranscriptionCoordinator](../../Sources/Record/Transcription/TranscriptionCoordinator.swift):
a missing or failed track is skipped, and the job succeeds if at least one track
was processed successfully. It can then publish **Transcript ready** and write
`transcript.json`, whose presence excludes that session from the pending scan.
This preserves useful partial text, but the public status cannot distinguish it
from a complete transcript. The current retry state also retains only the latest
failed session. This is an inference from the control flow, not a reproduced
hardware failure.

Add explicit per-track outcomes and stages: queued, loading model, microphone,
system audio, optional cleanup, writing, complete, partial, failed, and deferred.
Show **Microphone complete; system audio needs retry** with a targeted action.
Preserve a successful empty/silent track as a success. Keep previous good text
while retrying; publish a replacement atomically only when valid.

The pinned shared
[ParakeetTranscriber](../../shared/dust-wave-platform/native/Sources/DustWaveSpeech/ParakeetTranscriber.swift)
already accepts progress callbacks. Record's engine protocol currently drops
that capability. Reuse it through one engine-independent progress contract;
show stages rather than invented percentages where an engine has no progress.
Cancellation should stop or defer downstream work without deleting media or
restarting unexpectedly at next launch. Durable retry/defer state needs a
documented format decision with backward compatibility.

Acceptance: one failed track, both failed, legitimate silence, several failed
sessions, folder changes, quit/relaunch, stale callbacks, and repeated retry.
Progress must stay bounded and contain no transcript text. Completion hooks
retain their existing at-most-once policy.

## 3. Recent sessions and transcript preview

Handy's [history surface](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/history/HistorySettings.tsx)
offers transcript text, audio playback, copy, saved entries, and re-transcription.
Record currently reveals the latest session in Finder.

Add a small **Recent Sessions** window with date, duration, capture kind, and
capture/transcription status. Opening a session should offer a readable transcript,
explicit Copy, Reveal in Finder, source-track playback, and applicable retry or
recovery actions. A raw/cleaned comparison would make Record's existing preservation
policy useful to the user. Local title/date filtering is a sensible first step;
full transcript search is a Record proposal, not an observed Handy history feature.

Extend [RecentRecordingLocator](../../Sources/Record/RecentRecordingLocator.swift)
and existing manifests. Use approved roots, retained folder grants, contained
regular files, and bounded/lazy reads. List failed or interrupted sessions even
when they have no transcript. Avoid a second authoritative activity database.
Do not adopt automatic media expiry as part of this change: Record retains
exports until the user deletes them.

Acceptance: restart reconstruction, renamed/missing folders, revoked grants,
symlink rejection, large libraries, unavailable transcripts, and recovery entries.
The first useful slice is a recent-session list with Open, Copy Transcript, and Retry.

## 4. Configurable global recording shortcuts

Handy supports Hold, Toggle, and Auto (hold-or-toggle), while preserving existing
users' choices on upgrade. See its
[0.9.7 interaction notes](https://github.com/cjpais/Handy/blob/05e0aedd2906f0d82722735f930465950c476b90/src/content/release-notes/0.9.7.md)
and [deterministic coordinator](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/transcription_coordinator.rs).

Record has configurable global screenshot shortcuts, but recording uses menu
commands. Extend the existing Carbon registrar and shortcut recorder for screen
recording, audio-only recording, and screen pause/resume. Start with explicit
toggle behavior and the existing typed lifecycle. Hold-to-record is more useful
for a later short-note/dictation mode than long sessions. Preserve all existing
screenshot assignments and Off states; detect conflicts across command types.

Acceptance: rapid double presses, held/repeated keys, permission/source-picker
cancellation, Stop during Start/Resume, and shortcut registration failure. Avoid
globally intercepting plain Escape. Handy's open
[Escape-registration report](https://github.com/cjpais/Handy/issues/2164) is a
specific reason to serialize registration and teardown if temporary hotkeys are
ever added. Basic Record recording shortcuts should not require Accessibility.

## 5. Guided setup and model readiness

Handy has explicit [permission onboarding](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/onboarding/AccessibilityOnboarding.tsx)
and [model setup states](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/onboarding/Onboarding.tsx),
including downloading, verifying, extracting, and selecting.

Add a resumable **Ready to Record** checklist: destination, required permissions
for the chosen mode, audio test, and optional transcription readiness. Give each
problem its own explanation and repair action. Keep **Record without transcription**
available and request permissions only when the chosen action needs them.
Window/application screenshots must retain Apple's selection-scoped permission;
Handy's Accessibility requirement is not applicable to Record's ordinary capture.

Record already offers Download and Install, Import Existing Model, Later, retry,
verification, and automatic resumption of pending transcription. Improve their
presentation with bounded download progress, explicit verification/install stages,
and a cancel action backed by the helper's existing cancellation method. Retain
the single pinned model and narrow XPC contract;
content-free progress events do not justify accepting arbitrary URLs or paths.
Reuse [Doctor](../../Sources/Record/Doctor.swift),
[RecordingPermission](../../Sources/Record/RecordingPermission.swift), and the
[existing setup flow](../../Sources/Record/Record.swift).

Acceptance: clean-account start, skipped model setup, denied/revoked permission,
cancelled folder choice, interrupted download, and failed import that preserves a
working model. Never probe MacWhisper when it is not the selected engine.

## 6. Optional compact recording panel

Handy's [recording overlay](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/overlay/RecordingOverlay.tsx)
shows live microphone activity and separates arming from actual sample readiness.
Record already has an elapsed menu label, recording dot, transition states, and
health messages; make that same information easier to see.

Offer a small native panel with elapsed time, mic/system indicators, Pause/Resume,
Stop, and clear preparing/saving states. It should follow the existing presentation
policy and clock, never maintain a second capture state machine. Keep it optional,
non-activating where possible, keyboard accessible, and excluded from recordings.
Handle the deliberate policy that screenshots may include Record's own UI.

Optional start/stop cues must occur outside the captured interval, with quiet
visual feedback available. Do not copy Handy's system-mute behavior: Record often
needs to capture system audio. Validate panel placement on multiple displays,
Reduce Motion, VoiceOver, focus behavior, and absence from actual recorded frames.

## 7. Local vocabulary and reviewed corrections

Handy's [custom-word editor](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/CustomWords.tsx)
supports names and phrases. Its
[implementation](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/audio_toolkit/text.rs)
uses fuzzy, phonetic, and n-gram replacement after recognition; this is not
evidence of acoustic model training. Current main contains additional filler
cleanup changes beyond the reviewed release tag.

For Record, start with a local glossary and explicit user-approved replacement
pairs for recurring names, project titles, and terminology. Preview corrections
and preserve original text and timing. Apply them as a separately identified
derived result, not as permission for the existing Apple cleanup pass to rewrite
words. Recognition-time vocabulary hints require confirmation that the pinned
engine actually supports them.

This needs an ADR before expanding the current removal-only transcript policy.
Acceptance should include near-matches that must remain unchanged, punctuation,
quoted dialogue, code, numbers, accents, and mixed English/Spanish examples.

## 8. Engine-aware language controls

Handy's [model settings](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/general/ModelSettingsCard.tsx)
show language selection and translation only when the selected model supports
them. Use that capability-driven presentation with Record's existing engines.

Record's advanced configuration accepts a language, but its Settings UI does not
expose that choice. The current Parakeet adapter does not forward a forced-language
parameter; MacWhisper does. Present Parakeet's automatic behavior honestly and
expose only effective choices for each engine. Explain Apple cleanup availability
separately from speech recognition. Start with the existing Parakeet/MacWhisper
choices; additional Whisper models or translation need a demonstrated quality
gap and separate review, not a general model marketplace.

Acceptance: model switching preserves user intent without silently claiming an
unsupported language or translation mode, and cleanup fallback remains safe.

## 9. Localization and accessibility

Handy's [localization layer](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/i18n/index.ts)
and [translation contribution guide](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/CONTRIBUTING_TRANSLATIONS.md)
show a systematic approach to translated strings and language fallback.

Start Record with English and Spanish across setup, recording, recovery, errors,
and transcription status. Keep interface language distinct from speech language.
Use native string catalogs and accessible controls; add VoiceOver announcements
for important state changes without announcing every timer tick. Check tab order,
shortcut recording, text expansion, contrast, and Reduce Motion. This expands an
existing roadmap item; Handy's translations alone are not proof of accessibility.

## 10. Local file transcription and automation

Handy's [CLI](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/cli.rs)
can toggle transcription or cancel in the running instance. It also accepts an
existing 16-kHz mono WAV for headless transcription with an installed model.
Record's current CLI exposes `run`, `doctor`, and `inspect-session`, rather than
file transcription or remote control of an already-running capture.

A useful first addition is **Transcribe Audio File…** plus a corresponding local
command. Use explicit file selection, validate supported audio, preserve the
original, and reuse the existing queue and transcript writer. An imported file
must carry honest source provenance rather than automatically acquiring a
microphone/system speaker label. This requires a small import/session contract.

Add typed local Start, Stop, Pause, Resume, Status, and Open Last commands through
a reviewed native mechanism, with Shortcuts/App Intents integration if suitable.
Reuse the same lifecycle as the menu and hotkeys. Prefer explicit Start/Stop for
automation so retries cannot accidentally invert state. CLI invocation must not
launch a second recorder. Any process-control boundary needs an ADR and sandbox
review; it must not introduce an HTTP server, network entitlement, shell execution,
or a general-purpose file-access service.

Acceptance: duplicate commands, busy transitions, app-not-running behavior,
permission prompts, and cancellation. Existing completion hooks remain direct
executable-plus-arguments calls with their at-most-once claim intact.

## 11. Explore quick dictation separately

Handy's central [press/speak/paste workflow](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/README.md)
could become an optional short-note mode in Record. First prove a mic-only
**Record → Preview → Copy** flow using the same local engine and preserved audio.
Treat automatic insertion into another app as a later step with explicit
permission and product review.

Pasting introduces focus, Accessibility, Secure Input, and clipboard ownership
problems. Handy documents a [stale clipboard bug](https://github.com/cjpais/Handy/issues/502)
and an experimental [receipt-based paste implementation](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/paste_tx/mod.rs).
Preserve all clipboard formats, respect user clipboard changes, and leave text
available for manual copy if insertion fails. Never auto-submit the destination
form or message. This is a distinct workflow, not a prerequisite for improving
Record's meeting and screen capture.

## 12. Explore live transcript preview

Handy's overlay distinguishes committed and tentative text for compatible
streaming models. A Record preview could help confirm that speech is being
recognized, but its current post-recording engine contract does not establish
streaming capability. Progress callbacks are not partial-transcript callbacks.

Prototype only after capture controls and post-recording status are dependable.
Use a bounded, optional inference path that can be dropped under load without
affecting media writing. Label tentative text, keep source-track attribution,
and produce the canonical final transcript from preserved media. Validate long
sessions, overlap, memory pressure, source loss, and capture frame drops. Do not
change the pinned model or downloader merely to make a live preview possible.

## Reliability lessons and ideas to defer

- **Preserve the final audio tail.** Handy's merged
  [tail-audio fix](https://github.com/cjpais/Handy/pull/1958) and
  [real-time callback fix](https://github.com/cjpais/Handy/pull/1954) reinforce
  Record's existing bounded-queue and drain-before-finalize design. When adding
  meters or shortcuts, verify rapid stop, final words, pending buffers, and
  stop-during-start. These are validation targets, not newly established Record bugs.
- **Keep recovery independent of successful inference.** A Handy user
  [reported a long-recording crash with saved audio absent from History](https://github.com/cjpais/Handy/issues/2074).
  That Windows/backend-specific report does not establish a Record defect.
  It does support reconstructing Record's session list from manifests and
  testing recovery when inference never produces text.
- **Do not transplant remote post-processing.** Handy's
  [optional provider settings](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src-tauri/src/settings.rs)
  include remote LLM services alongside Apple Intelligence. Local ASR does not
  make every optional workflow local. Record retains its content-free diagnostic
  exception and forbids transcript upload.
- **Keep model acquisition narrow.** Borrow progress and repair UX, not arbitrary
  model URLs, broad cache discovery, mirrors, or unverified custom assets. Record's
  fixed helper and double verification already provide the required boundary.
- **Preserve sources and meaning.** Do not copy dictation-oriented audio expiry,
  automatic fuzzy correction, or generic filler removal into canonical media/text.
  Any VAD optimization belongs on derived inference input with exact timestamp
  mapping, padding, and quiet-speech tests; never remove silence from source tracks.
- **Measure before keeping models warm.** Handy offers
  [model unload policies](https://github.com/cjpais/Handy/blob/5ec58f696354fcf64ae831102e673779e0249717/src/components/settings/ModelUnloadTimeout.tsx).
  Record already retains its engine while queued work exists and releases it
  afterward. Consider a short opt-in idle grace only if repeated short sessions
  show a meaningful cold-start cost. Keep the microphone closed when idle.

## Suggested delivery order

1. Build explicit per-track transcription outcomes and progress, then a small
   Recent Sessions surface. These share one storage/status contract and make
   existing capture results more useful immediately.
2. Add microphone selection and bounded input testing alongside the existing
   hardware acceptance work. Add global recording shortcuts in a separate,
   focused change using the existing command policy.
3. Add the readiness checklist and optional recording panel over the same state.
   Introduce English/Spanish strings and accessibility checks as each new surface
   is built, rather than postponing all accessibility work.
4. Evaluate vocabulary, capability-aware language controls, and local automation
   from concrete usage. Keep dictation and live preview as separate experiments.

Each implementation should use RecordCore for deterministic policy, narrow native
adapters for effects, and the existing Platform speech mechanics. Run relevant
regressions and repository validation; use the full local gate and signed-app
hardware checks for capture/signing changes. Speech-quality changes retain the
frozen synthetic exact/native/Jev gates; no private transcripts go to evaluators.
Any durable format, privacy, or architecture change requires its own ADR and
corresponding user documentation before release.
