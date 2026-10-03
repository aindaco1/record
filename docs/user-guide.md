# Using Record

This guide covers everyday capture, settings, and recovery. See the
[repository overview](../README.md) for installation and requirements, and
[Support](SUPPORT.md) for help with a problem.

## Menu bar and settings

Record has no Dock icon. Open its camera in the menu bar for immediate capture,
source-selection, open, retry, and update commands. **Settings…** groups durable
preferences and recording tools into one sidebar: Recording, Sessions,
Transcription, Screenshots, Shortcuts, and General. Reopening
Record from Finder returns to the same window and last-used section. Use the
Up/Down keys in the sidebar to change sections. Text fields support standard
Command-A, Command-C, Command-X, Command-V, and undo shortcuts. Command-W closes
the window; it does not quit Record.

During screen or audio recording, a red dot blinks at the camera's lower-right
corner. The dot is steady when Reduce Motion is enabled and disappears while
paused.

## Recording setup

Open **Settings… → Recording** or **Recording Setup…** from the menu. Choose
screen or audio-only mode, screen source, audio sources, and microphone directly
on this page. The inline checklist covers the save folder, required permissions,
input test, and optional local transcription model. A new setup opens here.
The save folder is in General; model setup is in Transcription.
Choose **Start Screen Recording** or **Start Audio Recording** when ready.
It never begins recording or downloads a model by itself.

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
quality and adjust shutter sound. Edit or disable shortcuts in **Shortcuts**.
JPEG transparency is flattened onto white. The shutter sound is suppressed
while recording.

Record 1.4 preserves existing screenshot shortcuts, including Off and the
original Command-Shift-4 Area shortcut for users who never customized it.
Choose **Settings… → Shortcuts → Restore Screenshot Defaults** to adopt the new Area
shortcut explicitly. Full Display and Window/Application defaults remain
Command-Shift-1 and Command-Shift-2.

## Screen and audio recording

Use **Settings… → Recording → Screen source** or the menu to select a display, window, application, or
custom region for screen recording. The main display is the default.

Application choices remain restricted to the selected application, including
when macOS describes that choice as display-bound. On macOS 15.0–15.1, Record
rejects picker results whose scope cannot be verified; use **Main Display** or
update macOS. The same scope check protects window/application screenshots.

- **Start screen recording** creates a video-only `recording.mov` and writes
  enabled `mic.wav` and `system.wav` sources independently as uncompressed 24-bit PCM.
- **Start audio-only recording** writes the enabled independent audio tracks
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

### Inputs, activity, and recording controls

**Settings… → Recording** selects Microphone + System Audio, Microphone Only, or
System Audio Only for either recording mode. Choose System Default or a specific
microphone. Record does not change the Mac's default input. If a specifically
selected microphone disconnects, Record stops and preserves the session, then
offers input selection for the next recording. It never silently substitutes a
microphone for that selection.

**Test Input** listens for ten seconds and displays microphone activity without
saving audio. Stop the test at any time. The two activity indicators show enabled
microphone and system sources independently during recording.

The compact panel appears automatically while preparing, recording, or saving.
It shows the same elapsed time and controls as the menu. Screen recordings exclude
Record's windows, including the panel. Close it for the current session or turn off
**Show compact panel while recording** in Recording settings. Closing the panel does
not stop recording.

**Settings… → Shortcuts → Recording** assigns screen start/stop, audio
start/stop, and screen pause/resume keys. Click a control and type a combination;
Delete turns it Off and Escape cancels editing. New recording shortcuts start Off.
A start/stop shortcut stops its own active recording mode; it does not change
modes during capture. Held keys trigger once. Conflicts with other Record actions
are rejected; unavailable system combinations are reported in Settings.

## Save location and recovery

**Settings… → General → Save to** changes the one approved destination shared
by screenshots and completed screen or audio recordings. Desktop is suggested
on first use, and the sandbox grant persists across launches.

Each exported recording session contains an atomic `session.json` manifest,
the enabled `mic.wav` and/or `system.wav` sources. Screen sessions also contain
`recording.mov`.
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

Specific microphone choices use raw input in audio-only mode. **System Default**
retains the existing voice-processing option. This avoids changing the system
output device or creating a virtual aggregate device for a selected input.

## Recent Sessions

Choose **Sessions** in the sidebar or **Recent Sessions…** from the menu to
browse the current approved save folder and private recovery sessions. The list shows title, date, duration, recording type, and state.
Filter by title or date (`YYYY-MM-DD`), select a session, then preview or copy the
final, pre-vocabulary, or raw transcript, play a source in its default local application, reveal
its folder, or retry unfinished transcription. **Refresh** picks up folder changes.
Previous save folders are not indexed or scanned after you change destinations.

## Local transcription

Parakeet v3 is the default engine. Follow the [Parakeet setup guide](models/parakeet.md)
for verified download, manual import, and developer setup. Transcription waits
for the model; recording remains available. Download setup reports received bytes,
then verification and installation stages. **Cancel** stops the download or waits
for the current verification/extraction step to finish before cancelling; partial
setup files are removed and an existing model is preserved.

Each source is transcribed independently. The menu shows the current source and
real engine progress where available; engines without progress show the current
stage. A failed source produces a clearly marked partial transcript when another
source succeeds. Use **Recent Sessions → Retry unfinished tracks** to resume.
Successful raw recognition is reused only when the source and recognition settings
still match. **Transcribe later** defers queued or active work and keeps that choice
across relaunches. An engine may finish its current operation before stopping.
Media is preserved, and completion hooks wait for the entire transcript.

New sessions retain raw ASR in `transcript.raw.json` before optional cleanup and
track progress in the local `transcription.state.json` sidecar. A partial canonical
JSON transcript includes `incomplete_tracks`; the Markdown also labels the result.
Do not treat the mere presence of `transcript.json` as proof that every track is
complete for these sessions.

### Speech and interface languages

**Transcription → Speech language** offers Automatic, English, and Spanish when
MacWhisper is selected. Parakeet detects language automatically, so this control
is disabled for it. Your MacWhisper choice survives engine changes. A language
change applies to the next session processed, including queued sessions; it does
not change work already in progress.

**General → Interface language** follows macOS by default. Choose English or
Español for an override, then quit and reopen Record. Spanish uses neutral Latin
American wording. Interface language does not change the language spoken in a
recording or translate transcript content.

### Global vocabulary

In **Transcription → Vocabulary**, choose **Add word**, enter a preferred spelling
such as `Dust Wave`, then **Save vocabulary**. New transcripts automatically use
that spelling for `dustwave`, `Dustwave`, `DUST WAVE`, or `dust-wave`. For a different
recurring mishearing, add explicit aliases separated with semicolons, for example
`dust waive; dust way`. Record matches complete words and phrases, never guesses
phonetic corrections, and leaves code spans alone. The list is local to this Mac.

In **Sessions**, **Transcript** shows the result, **Before vocabulary** shows the
text after optional cleanup, and **Raw transcript** shows original recognition.
**Apply Vocabulary** applies the current list to an existing session without
transcribing again. Remove a rule and apply again to restore its earlier wording.
Wait for queued/active transcription to finish before applying rules manually.
Older sessions use their current transcript as the baseline on first application.

### Import audio files

Choose **Sessions → Import Audio…** and select one or several audio files. Each
gets its own session in the current save folder and joins the transcription queue.
Record copies your originals, validates the copies, and keeps them even if speech
recognition fails. Imported files use the neutral source label `source`; they
are not labeled as your microphone or the system audio. Play, copy, retry, defer,
cleanup, and vocabulary work through the same Sessions controls.

Supported formats are WAV, MP3, M4A, AIFF, CAF, and FLAC, up to 4 GiB and 12 hours
per file. Symbolic links, empty/corrupt audio, and files changing while copied are
rejected. One failed file does not stop the remaining imports. Install the chosen
local transcription engine/model first. Import is an explicit transcription
request even if automatic transcription is disabled in advanced configuration.

For scripts, invoke the executable inside your installed Record app:

```sh
record transcribe first.wav second.m4a --output ./sessions
record transcribe --authorize
```

Here `record` means `Record.app/Contents/MacOS/record` at your installation path;
Record does not install a global shell command. The output directory must exist.
Omit `--output` to use the app's approved save folder. Sandboxed builds can only
read accessible paths; `--authorize` opens native dialogs to choose files and a
destination with macOS permission. When this flag is present, those dialog
selections determine the batch. The command prints preserved session paths and
returns nonzero if any import or transcription fails. It does not control live
recording or download a model automatically.

### MacWhisper

If MacWhisper and its bundled `mw` CLI are installed, Record offers the engine.
Selecting it provisions Record's bundled, content-checked user-script bridge. Open **Settings… → Transcription**
and choose **MacWhisper (Small)** from **Engine**. This option is absent unless
MacWhisper and its bundled `mw` are available. Record prepares and validates its
sandbox helper only for the selected MacWhisper integration.
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
in to **Settings… → Transcription → Improve Transcript Readability**. Apple's
on-device model advises Record only on bounded filled-pause and immediate-repeat
candidates. Record validates every decision, preserves timing and source-speaker
labels, and marks simultaneous cross-speaker segments as overlapping. It never
asks the model to rewrite a transcript or identify a person.

Record keeps segments containing quotation or code-literal marks verbatim, so
extra hesitation around quoted dialogue may remain. Other repeated words are
preserved unless they form a short pronoun/article stutter that the model
approves for removal. Punctuation boundaries, longer repetition runs and
overlapping speech remain protected.

If the model is unavailable or generation fails, the ordinary local transcript
still completes. A changed transcript retains the complete pre-refinement
result in `transcript.raw.json`; `transcript.refinement.json` records the
content-free policy decisions and a source hash. See
[advanced configuration](configuration.md) for automation settings.

### Recording names

In **General**, enable **Rename finished recordings** and edit **Name template**
directly. Valid changes save immediately; an invalid token shows an explanation
and leaves the last valid template saved. The example uses placeholder clipboard
text and never reads the clipboard. Actual clipboard content is read only when
a recording name requests `{clipboard}`.

## Built-in plugins

Settings groups small, capability-specific features by what they affect:

- hide notifications, the menu bar, or Desktop items from screen capture;
- rename completed sessions using sanitized templates;
- hand the last completed video to an already-installed Gifski app from the
  Record menu.

These settings do not modify global macOS display preferences, download
helpers, or grant plugins network access. See the
[local-only boundary](security/local-only-boundary.md) for security details.

## Help and diagnostics

Choose **Help & diagnostics…** in the menu or **Settings… → General → Help & diagnostics…**.
Review the filtered JSON, import an optional Record `.ips` crash summary, save a
local copy, or explicitly send the preview to Record's public GitHub issues.
Nothing is sent automatically. Retry an unconfirmed submission with the same
preview; **Refresh** creates a new report. See [Support](SUPPORT.md) for the full
workflow and the [privacy policy](PRIVACY.md) for the exact data boundary.

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
