# Advanced configuration

Most settings belong in Record's menu. Advanced development and automation
settings use a versioned JSON file at `~/.config/record/config.json` relative
to Record's sandbox home:

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
finished export folder. Choose the export folder from Record's menu so macOS can
issue and persist a scoped sandbox grant.

Supported transcription engines are `parakeet` and `macwhisper`. Parakeet model
aliases are `v2` and `v3`; v3 is the default. MacWhisper requires an explicit
local model identifier and may optionally use an absolute `executable` path.
`language` is `auto` or a two-letter language code.

`mic_voice_processing` enables Apple's local VoiceProcessingIO echo canceller.
It is on by default and falls back to raw microphone capture when the active
route cannot produce live processed samples. `suppress_speaker_echo` is a
second, transcript-only safeguard: aligned high-confidence microphone copies
of system speech are omitted from `transcript.json` and `transcript.md`, while
`transcript.raw.json` retains the unsuppressed local result. Neither option
modifies `mic.caf` or `system.caf`.

`refine_with_apple_intelligence` is an opt-in baseline for the same menu toggle
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
