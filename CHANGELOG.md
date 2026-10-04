# Changelog

New features, improvements, and fixes in each Record release. For current
instructions, see the [user guide](docs/user-guide.md). Technical decisions and
validation evidence live in the [developer documentation](docs/README.md#contribute).

## [1.5.0] - 2026-10-04

### Added

- Quick Dictation: speak into your microphone, review the transcript, and copy it when ready.
- Apple Shortcuts actions and terminal commands to start, stop, pause, resume, and check recording status.
- Custom vocabulary that applies preferred spellings across sessions, with original transcripts kept for comparison.
- Import and transcribe multiple audio files, from Sessions or the terminal, without changing the originals.
- English and Spanish interface options, plus speech-language selection for MacWhisper.
- Microphone selection, microphone-only or system-only recording, input testing, and separate audio activity indicators.
- A Sessions browser with search, transcript previews, copy, playback, and transcription retry controls.
- Configurable recording shortcuts, a setup checklist, and a compact recording panel.

### Improved

- Settings now uses one sidebar, with General first and direct access to recording and sessions.
- Model setup shows download and installation progress and supports cancellation.
- Clearer recording-name editing, help text, diagnostic-report wording, and accessibility labels and announcements.

### Fixed

- Failed transcription tracks can be retried without repeating successful work; deferred sessions stay deferred after relaunch.
- Model setup resumes pending transcription in both the save folder and recovery storage.
- Losing a selected microphone stops safely and preserves the recording.
- Recording requests only the permissions needed by the selected audio sources.
- Fixed text-editing shortcuts, clipped Settings descriptions, and shortcut-conflict detection.

## [1.4.7] - 2026-09-25

### Improved

- Internal maintenance of diagnostic reporting. Report review, explicit sending, and update prompts retain their existing behavior.

## [1.4.6] - 2026-09-25

### Added

- Help & diagnostics lets you review a filtered report, include a crash summary, save it locally, or send it to the developer.
- Similar submitted reports are grouped together. Reports are public and are sent only when you choose; recordings, transcripts, and raw logs stay local.

## [1.4.5] - 2026-09-23

### Fixed

- Improved optional transcript cleanup to remove unnecessary fillers while preserving quotations, emphasis, meaningful repetition, and overlapping speech.
- Original audio, raw recognition, speaker labels, and timestamps remain available. Existing sessions are not changed automatically.

## [1.4.4] - 2026-09-22

### Improved

- Updated the app updater with installation and file-handling improvements for macOS 27.
- Updated build compatibility while retaining support for macOS 15 and newer on Apple Silicon.

## [1.4.3] - 2026-09-15

### Fixed

- Changing the save folder no longer interrupts transcription or prevents retrying a session saved in the previous folder.

## [1.4.2] - 2026-09-15

### Improved

- Updated the local transcription engine and macOS 27 build compatibility.
- Recording and transcription continue to work locally, with microphone and system audio kept separate.

## [1.4.1] - 2026-09-07

### Fixed

- Application capture no longer includes unrelated windows when macOS reports an ambiguous selection.
- Recordings stop safely and preserve recoverable media when the selected application exits, with additional detection on macOS 15.2 and newer.
- Area selection appears correctly on displays positioned above or to the left of the main display.
- Stopping during recording startup or resume no longer fails because a requested track has not started writing.

### Improved

- Reorganized installation, support, privacy, and developer documentation.

## [1.4.0] - 2026-09-03

### Improved

- Added a camcorder app and menu-bar icon with a clear red recording indicator. The indicator respects Reduce Motion and hides while paused.
- New installations use Option-Command-Shift-4 for area screenshots to avoid the macOS shortcut. Existing assignments and disabled shortcuts are preserved.

## [1.3.2] - 2026-09-02

### Fixed

- Download and Install now finds the model correctly inside the downloaded model pack.

## [1.3.1] - 2026-09-02

### Added

- Download and Install sets up the local transcription model directly in Record, with recovery from temporary connection interruptions.
- Downloads are verified before installation; manual model import remains available.

## [1.3.0] - 2026-09-02

### Added

- Native-resolution screenshots of a full display, a selected window or application, or a selected area.
- Configurable screenshot shortcuts, PNG or JPEG saving, and an independent lossless PNG copy on the clipboard.
- A brief capture confirmation and optional shutter sound, suppressed while recording.

### Improved

- Combined preferences into one Settings window.
- Window and application screenshots use Apple's selection-specific permission.
- Screenshots can include Record's own windows; screen recordings continue to exclude them.

## [1.2.3] - 2026-08-31

### Fixed

- Recording settings stay disabled throughout preparation, pause, resume, and saving when changing them would conflict with the active recording.
- Invalid or redirected media files are rejected during recovery, export, playback handoff, and transcription.
- Fixed signed-update feed generation during release packaging.

## [1.2.2] - 2026-08-27

### Improved

- Finished recordings now export microphone and system audio as separate, uncompressed 24-bit WAV files for use in editing tools.
- Original capture files are kept until the complete export has been validated. Existing sessions are unchanged.

### Fixed

- Audio-only recordings preserve the measured timing offset between microphone and system audio.

## [1.2.1] - 2026-08-26

### Added

- Record checks for updates when it opens and prompts when a newer version is available. Downloading and installing remain your choice.
- Check for Updates remains available for manual checks.

## [1.2.0] - 2026-08-25

### Added

- Optional on-device Apple Intelligence cleanup reduces fillers and immediate repetitions on supported Macs running macOS 26 or newer.
- Cleanup preserves original recognition, timestamps, speaker labels, and audio, and marks overlapping speech.
- Ordinary transcription still completes when Apple Intelligence is unavailable.

## [1.1.3] - 2026-08-24

### Improved

- Updated the local speech engine and strengthened update-installation security.

## [1.1.2] - 2026-08-17

### Improved

- The disk image includes an Applications shortcut for clearer drag-to-install setup.
- Added a direct download link and stronger checks of the signed installer before publication.

## [1.1.1] - 2026-08-07

### Fixed

- Selecting or cancelling a screen source no longer crashes Record.
- Custom-region selection opens correctly and responds to dragging and Escape.
- Open Last Video in Gifski remains available after relaunch, even when a newer recording contains only audio.

## [1.1.0] - 2026-08-07

### Added

- Record a selected display, application, window, or custom region.
- Pause and resume screen recordings while preserving separate video and audio tracks.
- The elapsed counter reflects recorded time, excluding pauses. Interrupted recordings retain their segments for recovery.

## [1.0.3] - 2026-08-07

### Added

- Local capture diagnostics identify silence, device changes, and writing failures.
- Recovery validates interrupted media, restores playable partial files, and preserves damaged files for inspection.
- Voice processing and conservative transcript echo reduction, with original audio and unsuppressed text preserved.

### Fixed

- Improved recovery when the default audio input changes and prevented repeated microphone restarts after headset changes.
- Reduced unnecessary audio startup restarts and preserved timing across input interruptions.
- Preserved audio duration when the speech engine reports a zero-length result.
- Local completion actions are not launched twice during recovery.

## [1.0.2] - 2026-08-07

### Added

- Open last recording finds the newest finished or interrupted session after relaunch.
- Recovery notifications provide access to preserved interrupted recordings.
- Retry failed transcription without restarting Record or modifying the audio.

## [1.0.1] - 2026-08-07

### Added

- Guided setup when the local transcription model is missing, with verification before import.
- Release checks preserve Record's identity so macOS can retain existing permissions across updates.

### Fixed

- Open at Login works when an installed app has not yet been registered with macOS.
- MacWhisper is offered only when the required local app and command-line integration are available.

## [1.0.0] - 2026-08-07

### Added

- A native menu-bar recorder for Apple Silicon Macs running macOS 15 or newer.
- Screen and audio-only recording with separate microphone and system-audio files.
- Export to Desktop or another approved folder, with recovery after interruptions.
- Local transcription with Parakeet and optional MacWhisper integration.
- Capture privacy controls, custom recording names, and handoff to Gifski.
- Signed updates, optional Open at Login, and a notarized installer.
- Local storage and processing without accounts, analytics, or media uploads.

[1.5.0]: https://github.com/aindaco1/record/compare/v1.4.7...v1.5.0
[1.4.7]: https://github.com/aindaco1/record/compare/v1.4.6...v1.4.7
[1.4.6]: https://github.com/aindaco1/record/compare/v1.4.5...v1.4.6
[1.4.5]: https://github.com/aindaco1/record/compare/v1.4.4...v1.4.5
[1.4.4]: https://github.com/aindaco1/record/compare/v1.4.3...v1.4.4
[1.4.3]: https://github.com/aindaco1/record/compare/v1.4.2...v1.4.3
[1.4.2]: https://github.com/aindaco1/record/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/aindaco1/record/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/aindaco1/record/compare/v1.3.2...v1.4.0
[1.3.2]: https://github.com/aindaco1/record/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/aindaco1/record/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/aindaco1/record/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/aindaco1/record/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/aindaco1/record/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/aindaco1/record/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/aindaco1/record/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/aindaco1/record/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/aindaco1/record/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/aindaco1/record/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/aindaco1/record/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/aindaco1/record/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/aindaco1/record/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aindaco1/record/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aindaco1/record/releases/tag/v1.0.0
