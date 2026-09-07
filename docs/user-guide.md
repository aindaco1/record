# Using Record

This guide covers everyday capture, settings, and recovery. See the
[repository overview](../README.md) for installation and requirements, and
[Support](SUPPORT.md) for help with a problem.

## Menu bar and settings

Record has no Dock icon. Open its camera in the menu bar for immediate capture,
source-selection, open, retry, and update commands. **Settings…** groups durable
preferences into General, Screenshots, and Recording sections.

During screen or audio recording, a red dot blinks at the camera's lower-right
corner. The dot is steady when Reduce Motion is enabled and disappears while
paused.

## Screenshots

| Command | Default shortcut for new installations | Captures |
|---|---|---|
| Capture Full Display | Command-Shift-1 | The display containing the pointer |
| Capture Window or Application… | Command-Shift-2 | A window or an application's visible windows, selected with Apple's picker |
| Capture Area… | Option-Command-Shift-4 | A dragged area on one display |

Full-display and area capture request Screen Recording access on first use.
Window/application capture uses Apple's selection-scoped permission and does
not request broad Screen Recording access. Screenshots can include Record's
own windows, exclude the cursor, and run during a recording; the area overlay
is removed before capture.

Screenshots save immediately to the approved export folder and independently
copy a lossless PNG to the clipboard. Disk files default to native-resolution
lossless PNG. **Settings… → Screenshots** can select JPEG at a default 95%
quality, adjust quality and shutter sound, edit a shortcut, or turn one Off.
JPEG transparency is flattened onto white. The shutter sound is suppressed
while recording.

Record 1.4 preserves existing screenshot shortcuts, including Off and the
original Command-Shift-4 Area shortcut for users who never customized it.
Choose **Settings… → Screenshots → Restore Defaults** to adopt the new Area
shortcut explicitly. Full Display and Window/Application defaults remain
Command-Shift-1 and Command-Shift-2.

## Screen and audio recording

Use **Screen source** in the menu to select a display, window, application, or
custom region for screen recording. The main display is the default.

Application choices remain restricted to the selected application, including
when macOS describes that choice as display-bound. On macOS 15.0–15.1, Record
rejects picker results whose scope cannot be verified; use **Main Display** or
update macOS. The same scope check protects window/application screenshots.

- **Start screen recording** creates a video-only `recording.mov` and writes
  `mic.wav` and `system.wav` independently as uncompressed 24-bit PCM.
- **Start audio-only recording** writes the same two independent audio tracks
  without capturing the display.
- Screen recording supports pause and resume. Pausing closes the active media
  segment; resuming continues from the same in-memory source selection.
  Start and Resume remain in progress until video and the requested audio
  tracks are ready. A pending quit waits for this transition before saving.
- If the selected application quits, Record stops capture and retains its media
  in recovery storage. For system-picker application/window choices, this
  independent application-exit check requires macOS 15.2 or later; earlier
  systems rely on ScreenCaptureKit to report source loss.
- **Open last recording** reveals the newest finished session from private or
  approved export storage. Record derives this from `session.json` and keeps
  no separate activity database.

## Save location and recovery

**Settings… → General → Save to** changes the one approved destination shared
by screenshots and completed screen or audio recordings. Desktop is suggested
on first use, and the sandbox grant persists across launches.

Each exported recording session contains an atomic `session.json` manifest,
`mic.wav`, and `system.wav`. Screen sessions also contain `recording.mov`.
Screenshots are individual image files and do not create session manifests.

Record keeps its AAC/CAF capture sources in private recovery storage until it
has validated the complete exported session, then removes the private working
directory. A failed conversion or export leaves those private sources
recoverable. A startup recovery scan validates interrupted media, restores
playable partials, and quarantines invalid partials without deleting them.
Recovery notifications open only Record's temporary recovery folder.

**Open Recovery Folder…** appears only while private failed, interrupted, or
unexported session material needs inspection. See the
[testing and inspection guide](testing.md) for structural inspection commands.
Follow the [support guidance](SUPPORT.md) when reporting a failure.

## Local transcription

Parakeet v3 is the default engine. Follow the [Parakeet setup guide](models/parakeet.md)
for verified download, manual import, and developer setup. Transcription waits
for the model; recording remains available.

### MacWhisper

If MacWhisper and its bundled `mw` CLI are installed, Record provisions its
own bundled, content-checked user-script bridge. Open **Settings… → Recording**
and choose **MacWhisper (Small)** from **Model**. This option is absent unless
MacWhisper, its bundled `mw`, and Record's sandbox helper are all available.
Record validates the MacWhisper application signature before each invocation
and never falls back silently from one engine to another. MacWhisper's own
privacy policy and settings apply when it processes audio locally.

Development checkouts can install the same bridge explicitly; see the
[contributor guide](CONTRIBUTING.md#local-transcription-setup).

### Failed transcription and echo reduction

If local transcription fails, **Retry Failed Transcription** appears in the
Record menu until the job is retried. Record keeps both source audio files
unchanged.

Voice processing reduces speaker-to-microphone echo by default. When aligned
cross-track speech still duplicates, Record conservatively removes only
high-confidence mic copies from the readable transcript and keeps the
unsuppressed result in `transcript.raw.json`.

### Improve transcript readability

On macOS 26 or newer, an eligible Mac with Apple Intelligence enabled can opt
in to **Settings… → Recording → Improve Transcript Readability**. Apple's
on-device model advises Record only on bounded filled-pause and immediate-repeat
candidates. Record validates every decision, preserves timing and source-speaker
labels, and marks simultaneous cross-speaker segments as overlapping. It never
asks the model to rewrite a transcript or identify a person.

If the model is unavailable or generation fails, the ordinary local transcript
still completes. A changed transcript retains the complete pre-refinement
result in `transcript.raw.json`; `transcript.refinement.json` records the
content-free policy decisions and a source hash. See
[advanced configuration](configuration.md) for automation settings.

## Built-in plugins

Settings groups small, capability-specific features by what they affect:

- hide notifications, the menu bar, or Desktop items from screen capture;
- rename completed sessions using sanitized templates;
- hand the last completed video to an already-installed Gifski app from the
  Record menu.

These settings do not modify global macOS display preferences, download
helpers, or grant plugins network access. See the
[local-only boundary](security/local-only-boundary.md) for security details.

## Updates, login, and uninstalling

Record silently checks its signed GitHub release feed once at launch. When a
newer version is available, Sparkle presents its standard update prompt;
download and installation remain user approved. **Check for Updates…** retains
the same signed flow as a manual fallback.

**Settings… → General → Open Record at Login** uses the macOS Login Items
service and is off by default.

To uninstall, turn off **Open Record at Login**, quit Record, and move
Record.app to the Trash. Remove Record's container only if you also want to
delete its preferences, temporary recovery sessions, and installed transcription
model. Exported screenshots and sessions remain until you delete them. See the
[privacy policy](PRIVACY.md) for retention details.
