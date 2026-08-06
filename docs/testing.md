# Testing strategy

Record separates deterministic logic from hardware/TCC behavior so most
regressions run on every pull request.

## Automated on every pull request

- typed configuration defaults and validation
- model identifier validation and local-only failure behavior
- session state transitions and atomic manifest round trips
- deterministic folder collision handling
- plugin activation rollback, reverse restoration, and idempotence
- debug tests plus an arm64 release build and architecture check
- Swift formatting for new modular code

Future pure tests will cover transcript merging, edit-operation serialization,
frame-timestamp normalization, queue backpressure, segment recovery, recording
name templates, click-event mapping, and plugin capability denial.

## macOS hardware matrix

Hardware tests run only on a dedicated Apple Silicon runner with intentional
TCC grants and synthetic, non-sensitive media.

| Area | Required cases |
|---|---|
| Source selection | each display, one window, one application, custom region, source disappears mid-session |
| Video | 1080p30, 1080p60, 4K30, 4K60, Retina scaling, HDR-to-SDR policy |
| Audio | mic only, system only, both, device switch, route reconfigure, silence, write failure |
| Camera | built-in/external, disconnect/reconnect, overlay positions and sizes |
| Input effects | cursor on/off, click highlight on/off, multiple displays and scale factors |
| Lifecycle | pause/resume, sleep/wake, lock/unlock, permission denial/revocation, low disk, forced quit |
| Recovery | termination before first frame, during each segment, during finalization, during plugin activation/restoration |
| Plugins | notification state, clock mask, desktop icon presentation, names, playback speed/audio pitch, Gifski handoff |

## Performance gates

Use signposts and Instruments rather than wall-clock guesses. On the reference
Mac, release candidates must demonstrate:

- no sustained dropped frames during a 30-minute 4K60 capture
- less than 50 ms A/V drift over one hour
- bounded memory across a one-hour recording
- no unbounded capture queue growth
- finalization in about two seconds when no transform is requested

Performance captures contain only generated test patterns and synthetic audio.
They are never uploaded automatically.
