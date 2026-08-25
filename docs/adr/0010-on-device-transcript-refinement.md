# ADR 0010: Bounded on-device transcript refinement

## Context

Local speech recognition preserves source audio and timing but can leave filled
pauses, accidental immediate repetitions, and ambiguous simultaneous speech in
the readable transcript. An unconstrained generative rewrite could silently
change meaning, names, timestamps, or speaker attribution. A network model would
also violate Record's local-only boundary.

Apple's Foundation Models framework exposes the on-device system language model
on eligible macOS 26+ Macs. Record still supports macOS 15, and Apple
Intelligence can be unavailable because of hardware, settings, language, or
model readiness.

## Decision

Make readability refinement opt-in and use `SystemLanguageModel` with the
content-tagging use case behind a narrow app adapter. Pin authoritative CI and
release builds to Xcode 26.3 while retaining the macOS 15 deployment target.

`RecordCore` deterministically identifies only a bounded set of filled pauses
and immediate same-word repetitions. It excludes cross-speaker overlap from
removal candidates, identifies such overlap from existing track timing, and
keeps source speaker labels. The model receives escaped, bounded context and can
advise only `keep` or `remove`. Record rejects unknown candidate identifiers,
unknown actions, duplicates, token mismatches, numeric repetition, and any
removal that would empty an utterance. It never accepts rewritten transcript
text, timestamps, or speaker identity from the model.

If the capability is unavailable, the language is unsupported, generation is
cancelled, or generation fails, canonical transcription still completes with
no model-directed removals. When echo suppression or refinement changes output,
Record writes the complete unsuppressed, pre-refinement local transcript to
`transcript.raw.json`. An enabled pass also writes
`transcript.refinement.json` before the canonical completion marker, recording
the policy version, source SHA-256, capability outcome, validated decisions,
removals, and overlap indices without duplicating transcript text.

Speaker diarization or identity inference is not part of this pass. The current
`me` and `them` labels continue to come from Record's separate microphone and
system-audio tracks.

## Consequences

- Record gains conservative readability improvements without a network client,
  account, analytics path, or downloaded model.
- The raw local result and source hash make every changed export reversible and
  auditable.
- Older and ineligible Macs retain ordinary local transcription; the menu
  explains why refinement is unavailable.
- Foundation Models output remains nondeterministic, but its authority is
  restricted to validated whole-token removals from deterministic candidates.
- Real Apple Intelligence behavior, supported-language status, and simultaneous
  speech still require manual testing on eligible hardware.
