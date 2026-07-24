# lyrebird

A minimal macOS meeting recorder. One menu-bar click records your mic and all
system audio as two separate tracks on disk. Nothing leaves the machine —
transcription is your problem, later, with whatever you like.

Named for the bird that records and replays ambient sound. Sibling of
[parrot](../parrot/), same skeleton: single Swift binary, menu-bar tray,
no app bundle.

## Install

```sh
cd lyrebird
swift build -c release
sudo cp .build/release/lyrebird /usr/local/bin/lyrebird
lyrebird install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 15+ (uses Core Audio process taps for system audio — no
virtual device, no kernel extension).

## How to use

1. **Run it** (`lyrebird` in a terminal, or the LaunchAgent).
2. **Click the feather in the menu bar → Start recording.** First use prompts
   for microphone and System Audio Recording permissions. While recording, the
   icon turns red with a running elapsed counter, and macOS shows the purple
   recording indicator.
3. **Click → Stop recording** when the meeting ends.

Each session lands in `~/Recordings/meetings/<yyyy.MM.dd-HHmm>/`:

| File | Contents |
|---|---|
| `mic.caf` | your side (default input device, AAC) |
| `system.caf` | everything the Mac played — the other side of the call (AAC) |
| `meta.json` | start/end timestamps, duration |

Two tracks on purpose: speech models do better on clean single-source audio,
and mic-vs-system is free two-party diarization. CAF on purpose: unlike m4a,
it needs no finalization pass — if the process dies mid-meeting, everything
already written is still readable.

## Transcribing later

Anything that reads audio via ffmpeg handles CAF directly, e.g.:

```sh
whisper mic.caf --model turbo
parakeet-mlx mic.caf
```

Transcribe both tracks, interleave by timestamp: `mic` = you, `system` = them.

## CLI

```sh
lyrebird                        # run the menu-bar daemon (^C to quit)
lyrebird run --out <dir>        # custom recordings root (default ~/Recordings/meetings)
lyrebird doctor                 # check permissions + recordings folder
lyrebird install --launch-at-login
lyrebird install --uninstall
```

## Stack

- **Swift** — single SPM executable target
- **Core Audio process tap** (`AudioHardwareCreateProcessTap`, macOS 14.2+) —
  system audio capture via a private aggregate device
- **AVAudioEngine** — mic capture
- **AVAudioFile** — streaming AAC encode into CAF
- **NSStatusItem** — the whole UI

## Gotchas

- A global tap records *everything* the Mac plays — notification dings,
  music, all of it. Don't play Spotify during meetings (or ask for a
  per-process picker if it bothers you).
- If recordings come out silent, check System Settings → Privacy & Security →
  Screen & System Audio Recording.
- The binary embeds its Info.plist (`__TEXT,__info_plist`) so TCC can
  attribute permissions to lyrebird itself when running as a LaunchAgent.
