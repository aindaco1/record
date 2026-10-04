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
  "completion_hook": {
    "executable": "/absolute/path/to/local-tool",
    "arguments": ["--session", "{session}"]
  }
}
```

`recordings_directory` controls private working and recovery storage, not the
finished export folder. Choose **Settings → General → Save to** so macOS can
issue and persist the one scoped sandbox grant shared by screenshots and
completed recordings.

Supported transcription engines are `parakeet` and `macwhisper`. Parakeet model
aliases are `v2` and `v3`; v3 is the default. MacWhisper requires an explicit
local model identifier and may optionally use an absolute `executable` path.
`language` is `auto` or a two-letter language code for MacWhisper. The Settings
choice overrides this baseline; other valid advanced codes remain visible.
Parakeet always uses automatic detection with the pinned adapter. Interface
language is independent and applies on restart. Vocabulary lives in local app
preferences and is managed in **Transcription → Vocabulary**, not this JSON file.

`mic_voice_processing` enables Apple's local VoiceProcessingIO echo canceller.
It is on by default and falls back to raw microphone capture when the active
route cannot produce live processed samples. `suppress_speaker_echo` is a
second, transcript-only safeguard: aligned high-confidence microphone copies
of system speech are omitted from `transcript.json` and `transcript.md`, while
`transcript.raw.json` retains the unsuppressed local result. Neither option
modifies the finalized `mic.wav` or `system.wav` tracks or their private CAF
recovery sources.

`refine_with_apple_intelligence` is an opt-in baseline for the same Transcription setting
and defaults to `false`. On macOS 26+, Record checks the local Foundation Models
capability, selected language, device eligibility, Apple Intelligence setting,
and model readiness before enabling it. The model can advise only whether
preselected filled pauses and immediate repetitions should be kept or removed;
deterministic RecordCore policy applies the result and marks cross-speaker time
overlap. Model unavailability or generation failure leaves transcript wording
unchanged. When refinement changes the transcript, `transcript.raw.json`
preserves the complete pre-refinement local result. The content-free
`transcript.refinement.json` report stores the policy version, source SHA-256,
candidate decisions, removals, overlap indices, and capability outcome.

Completion hooks run only after successful local transcription. Record invokes
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
