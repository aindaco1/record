# ADR 0013: Finalize source audio as 24-bit PCM WAV

## Context

Record has used independently playable AAC/CAF files for microphone and system
audio. CAF is a good private capture container because writers can preserve
completed media across interruption, and pause/resume can retime compatible AAC
packets without decoding them. User-facing CAF files are less convenient in
common editing and interchange workflows than WAV files.

Changing only the extension would mislabel the media. Writing WAV directly on
capture would also weaken the reviewed recovery boundary because a conventional
RIFF/WAV header needs clean finalization. Record must preserve raw media until a
complete exported session has been validated.

## Decision

Keep the existing AAC/CAF capture and pause/resume pipeline as private recovery
media. After capture and any segment concatenation complete, pass every finished
audio source through one shared AVFoundation adapter. The adapter decodes the
CAF source into an uncompressed little-endian 24-bit integer PCM WAV while
preserving its sample rate and channel layout.

Each WAV is first written to a unique hidden sibling. All requested tracks must
convert successfully before any output is promoted. Promotion never overwrites
an existing file, and a partial promotion is rolled back. Only after the WAV
files exist does the atomic session manifest transition to `finalized` and name
`mic.wav` and `system.wav` as its canonical tracks.

The source CAF files remain untouched in private storage through conversion and
whole-session export validation. The exporter copies only manifest-declared
canonical tracks, then removes the complete private working directory. A failed
conversion or export therefore leaves the recoverable CAF sources in place.
Existing sessions are not migrated, and schema version 1 remains valid because
track filenames and formats were already manifest-driven.

## Consequences

- Screen and audio-only modes share one WAV finalization policy and produce the
  same canonical filenames and format.
- Transcription, completion hooks, inspection, and exported sessions consume
  WAV files; interrupted and failed recovery sessions may still contain CAF.
- WAV output is substantially larger than the AAC source and finalization now
  performs a duration-proportional decode/write pass after capture stops.
- The 24-bit PCM container improves editing compatibility but does not restore
  information already discarded by the private AAC encoder.
- Automated tests must verify the RIFF/WAVE container, linear PCM codec,
  24-bit depth, source preservation, atomic promotion, and both session modes.
- Hardware release testing must listen to both exported WAV tracks and measure
  finalization time with representative short and long recordings.
