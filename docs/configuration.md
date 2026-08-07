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
    "language": "auto"
  },
  "mic_voice_processing": false,
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

Completion hooks run only after successful local transcription. Record invokes
the absolute executable directly, never through a shell. The literal
`{session}` argument expands to the completed session directory. Sandbox rules
still apply, so a hook is an advanced personal integration rather than a
portable release feature.

Invalid schemas, relative executables, unsupported engines, missing
MacWhisper models, and invalid language values fail closed to safe defaults and
produce a local warning.
