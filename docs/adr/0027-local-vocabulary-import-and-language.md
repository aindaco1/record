# ADR 0027: Shared local vocabulary, import, and language policy

- Status: accepted for the 1.5.0 candidate
- Date: 2026-10-03

## Vocabulary

The user requested global, automatic preferred spellings rather than per-session
approval. RecordCore owns a bounded, deterministic vocabulary: up to 200 terms,
128 characters per spelling, and 20 aliases per term. Matching ignores case and
spacing/hyphen variants, respects Unicode word boundaries, protects code spans,
and applies longest matches without cascading replacements. It does not guess
phonetic matches or ask an inference model to rewrite text. Aliases cannot be
owned by different terms. Preferences stay in the app's local defaults.

Each transcription snapshots vocabulary and engine/language selection before
work begins. Vocabulary follows existing echo suppression and optional Apple
cleanup. This explicitly configured substitution policy is separate from the
conservative inference policy in [ADR 0023](0023-conservative-cleanup-preservation.md).
Canonical `transcript.json` and Markdown contain the result. Raw recognition
remains in `transcript.raw.json`; `transcript.cleaned.json` preserves the exact
pre-vocabulary document. `transcript.vocabulary.json` stores the source hash and
changed segments. This report **contains transcript content** and must remain
local; it is never an input to the reviewed diagnostic sender or developer Jev.

Sessions can reapply the current vocabulary without recognition or completion
hooks, using the preserved pre-vocabulary source. Removing rules therefore
restores the corresponding original wording. Legacy sessions adopt their current
canonical transcript as this source on first application. The existing serial
coordinator rejects application while that session is active or queued. Source
and output containment and regular-file checks continue to apply.

## File import and CLI

Explicit file selection accepts multiple local WAV, MP3, M4A, AIFF, CAF, or FLAC
files, each at most 4 GiB and 12 hours. A narrow AVFoundation adapter copies the
opened regular source with no symlink following, bounded buffers, cancellation,
and source-change detection. It decodes the entire owned copy before publishing
a finalized session by an atomic directory move. Failed imports remove only
their owned staging directory. Originals are never moved or overwritten.
Unexpected termination may leave hidden staging storage; it is excluded from
Sessions and queue discovery and is never treated as a finished session.

Manifest schema 2 adds an `imported_audio` track and provenance containing only
the original filename, bytes, and duration. Schema 1 remains readable. Imported
audio uses speaker `source`, never inferred microphone/system identities. Each
file creates its own session and uses the existing engine, checkpoint, cleanup,
vocabulary, retry/defer, and completion-hook paths. Explicit imported jobs run
even when automatic transcription of recordings is disabled. Model installation
continues to require its existing explicit setup flow.

`record transcribe` uses that same importer and coordinator. `--authorize` grants
access through native input and destination dialogs; plain paths must already be
accessible under the app's sandbox. It prints each preserved session path, keeps
processing after per-file failures, and returns nonzero if any file fails. No
recording-control IPC, shell hook, network entitlement, or new dependency is added.

## Languages and accessibility

Speech language belongs to recognition settings. MacWhisper offers Automatic,
English, and Spanish, while retaining other valid advanced-config languages.
Parakeet remains Automatic because the pinned adapter cannot force a language.
Switching engines preserves the saved MacWhisper language, and a queued session
uses one consistent engine/language snapshot for recognition and checkpoints.

Interface language follows macOS, with independent English or neutral Latin
American Spanish overrides in General. The override applies after quitting and
reopening Record. App-domain AppleLanguages also informs native system controls;
it does not change the system language. Native string catalogs are authoritative;
the generation/check script verifies both languages, matching format arguments,
and generated resources. SwiftPM owns the resource bundle; packaging includes it
and the main app's localized permission descriptions.

Persisted enums, filenames, command-line flags, and recognized speech are not
translated. Native control labels and keyboard editing remain accessible.
VoiceOver announcements follow stable recording and transcription transitions;
timer ticks, audio meters, and per-percent progress updates do not announce.

## Validation

Use synthetic fixtures for import, source preservation, language, and vocabulary
regressions. Native signed-app import/CLI grants, Spanish layout, keyboard focus,
and VoiceOver acceptance remain distinct from deterministic tests. See the
[candidate evidence](../testing/1.5.0-candidate.md) and [manual matrix](../testing.md).
