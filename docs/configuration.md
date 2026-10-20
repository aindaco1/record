# Advanced configuration

Most settings belong in Record's Settings window. Advanced development and
automation settings use a versioned JSON file at
`~/.config/record/config.json` relative to Record's sandbox home:

```json
{
  "schema_version": 1,
  "recordings_directory": "~/Recordings",
  "transcription": {
    "enabled": true,
    "engine": "parakeet",
    "model": "parakeet-tdt-0.6b-v3-coreml",
    "language": "auto",
    "suppress_speaker_echo": true,
    "refine_with_apple_intelligence": false
  },
  "mic_voice_processing": true,
  "mic_automatic_gain_control": false,
  "mic_disable_voice_processing_for_zoom": true,
  "completion_hook": {
    "executable": "/absolute/path/to/local-tool",
    "arguments": ["--session", "{session}"]
  }
}
```

`recordings_directory` controls private working and recovery storage, not the
finished export folder. Choose **Settings → General → Change…** beside **Save to**
so macOS can issue and persist the one scoped sandbox grant shared by screenshots
and completed recordings.

Supported transcription engines are `parakeet` and `macwhisper`. Parakeet model
aliases are `v2` and `v3`; v3 is the default. MacWhisper requires an explicit
local model identifier and may optionally use an absolute `executable` path.
`language` is `auto` or a two-letter language code for MacWhisper. The Settings
choice overrides this baseline; other valid advanced codes remain visible.
Parakeet always uses automatic detection with the pinned adapter. Interface
language is independent and applies on restart. Vocabulary lives in local app
preferences and is managed in **Transcription → Vocabulary**, not this JSON file.

`mic_voice_processing` enables Apple's local VoiceProcessingIO echo canceller
for System Default input in audio-only recording and dictation. It is on by
default; **Settings → Recording → Use Apple voice processing** overrides this
baseline. Record also falls back to raw capture when the route cannot produce
live processed samples. A specific microphone uses raw input; screen recording uses
ScreenCaptureKit's microphone path. `suppress_speaker_echo` is a
second, transcript-only safeguard: aligned high-confidence microphone copies
of system speech are omitted from `transcript.json` and `transcript.md`, while
`transcript.raw.json` retains the unsuppressed local result. Voice processing
affects microphone capture; transcript echo suppression never modifies the
captured media or private recovery sources.

`mic_disable_voice_processing_for_zoom` defaults to `true`, including in older
configuration files. **Turn off while Zoom is open** overrides this baseline.
Record checks whether the native Zoom app is running, including in the background,
before each microphone engine starts. A Zoom launch during capture releases the
voice processor and restarts raw input using the existing writer and bounded
recovery. The bypass lasts through route recovery and until capture ends, even
if Zoom quits. A later recording after Zoom quits restores processing if enabled.
This intentionally includes idle Zoom windows; it does not detect a meeting or
browser-based Zoom. No window content or application inventory is collected.
Manual off and explicit microphone selection always keep voice processing off.
See [ADR 0030](adr/0030-zoom-voice-processing-compatibility.md).

`mic_automatic_gain_control` defaults to `false`, including in older configuration
files that omit it. **Settings → Recording → Automatically adjust microphone
volume** overrides this baseline. It controls only Apple's automatic gain in
the audio-only and dictation voice-processing path; turning it off does not
disable echo cancellation or noise suppression. It has no effect while voice
processing is bypassed. The choice is captured when a microphone
recorder is created and reapplied if its engine recovers after a route change.
It does not change Zoom's gain, system microphone volume, or playback ducking.
See [ADR 0029](adr/0029-independent-microphone-gain-control.md).

`refine_with_apple_intelligence` is an opt-in baseline for the same Transcription setting
and defaults to `false`. On macOS 26+, Record checks the local Foundation Models
capability, selected language, device eligibility, Apple Intelligence setting,
and model readiness before enabling it. The model can advise only whether
preselected filled pauses and immediate repetitions should be kept or removed;
deterministic RecordCore policy applies the result and marks cross-speaker time
overlap. Model unavailability or generation failure leaves transcript wording
unchanged. New transcription writes original recognition to `transcript.raw.json`
before echo suppression, cleanup, or vocabulary. `transcript.cleaned.json`
preserves the result before vocabulary, and `transcript.vocabulary.json` records
the applied corrections. Both contain transcript content and stay local. The
content-free `transcript.refinement.json` report stores the policy version, source SHA-256,
candidate decisions, removals, overlap indices, and capability outcome.

Completion hooks wait for all requested transcription tracks to succeed. When
automatic transcription is disabled for an ordinary recording, the hook runs
after the session is finalized instead. Explicit imports and dictation still
transcribe before running the hook; failed or deferred transcription waits.
Record invokes
the absolute executable directly, never through a shell. The literal
`{session}` argument expands to the completed session directory. Sandbox rules
still apply, so a hook is an advanced personal integration rather than a
portable release feature.
Record atomically claims each hook before launch, so recovery will not run the
same hook twice. A process failure in the narrow interval after the claim can
therefore omit a hook rather than duplicate its side effects.

Invalid schemas, relative executables, unsupported engines, missing
MacWhisper models, and invalid language values fail closed to safe defaults and
produce a local warning.

## Dictation and recording commands

Quick Dictation reuses the selected microphone and transcription settings. It
temporarily selects microphone-only capture and explicitly transcribes the
session even if automatic transcription is disabled. Its optional toggle shortcut
is configured in Settings, not the JSON file. Copying text is always explicit.

`record control start --mode screen|audio|dictation`, `stop`, `pause`, `resume`,
and `status` operate on the running app's saved setup. Add `--json` for a coarse
state response. They accept no arbitrary path, source name, executable or config
payload. CLI capture cannot prompt for setup; screen starts require Main Display.
Apple Shortcuts exposes the same five commands and can open the app's normal
interactive setup. See [the user guide](user-guide.md#recording-automation).
