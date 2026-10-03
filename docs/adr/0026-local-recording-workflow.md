# ADR 0026: Resumable local recording workflow

- Status: accepted for the 1.5.0 candidate
- Date: 2026-10-02

## Decision

Extend the existing capture, shortcut, permission, and transcription adapters.
Use `RecordCore` for audio configuration, readiness, bounded activity state,
and versioned transcription checkpoints. Add no dependencies or history database.

Recent Sessions enumerates direct, non-symlink session folders under the current
approved save folder and private recovery root. Changing the save folder changes
this scope; previous destinations are not indexed. Hold the existing security
scope lease while reading or processing an approved folder. Playback and copying
are explicit local actions. Session metadata, previews, and audio stay local.

Store `transcription.state.json` beside each session. It preserves successful raw
recognition by source filename, size, modification time, speaker, timing offset,
engine, model, and language. Changed sources or recognition settings invalidate
the corresponding cached work. Failed tracks can be retried independently of
successful tracks. Deferred jobs stay deferred across relaunches. Cancellation
may finish an engine's current operation; it must preserve media and checkpoints.

`transcript.json` may now represent a partial result. Such results include
`incomplete_tracks`, and the readable transcript explicitly identifies them as
partial. The checkpoint determines completion for new jobs. Legacy sessions
without checkpoints retain the previous canonical-file completion convention.
Completion hooks run only after complete transcription, or after export when
transcription is disabled, using the existing direct-executable, at-most-once
claim. Raw recognition is retained before optional cleanup.

Microphone selection is a local device UID preference, not a system-wide input
change. System Default retains normal route recovery. A specifically selected
microphone disappearing stops capture through the existing finalization path;
Record offers another input for a new recording. Disabled audio sources do not
request permission or create tracks. The explicit input test captures no file.

The compact panel renders the same presentation and elapsed clock as the menu.
It appears automatically, can be disabled, and is excluded from screen recordings
by the existing own-application capture filter. Activity indicators retain only
a bounded amplitude summary in memory. They do not store or transmit samples.

New recording shortcuts use the existing Carbon registrar and native key recorder.
They begin Off; screenshot defaults, custom assignments, and Off remain intact.
Physical keys and modifiers determine conflicts, regardless of display labels.

Model setup reuses the fixed, pinned downloader. Its only new XPC message travels
from the service to the app and contains a bounded received-byte count. The app
still supplies only the pre-opened output handle; it supplies no URL, path, user
content, or recording metadata. Cancelling invalidates the connection and stops
the helper's download. Verification and atomic installation retain existing
size, checksum, signature, and path guards. The main app has no network entitlement.

## Validation

Deterministic tests cover partial retry, deferred recovery, source invalidation,
disabled-source permissions and finalization, shortcut conflicts, and readiness.
Native UI, TCC, audio routing, capture exclusions, signed XPC progress/cancellation,
and the updater require separate manual acceptance. Available hardware for this
candidate is built-in audio only; USB/Bluetooth behavior must not be reported as
verified without those devices. Follow the [release runbook](../runbooks/release.md).

## Explicit input routing

Audio-only capture uses raw input for a specifically selected microphone. The
macOS VoiceProcessingIO duplex route failed native validation when its current
device was changed to an input-only device. System Default retains the existing
voice-processing and bounded fallback behavior. Record does not change system
defaults or create aggregate devices to work around this limitation. The input
test restarts its stopped engine after a route configuration notification and
bounds that recovery to two attempts; receiving silent samples remains distinct
from receiving no callbacks.
