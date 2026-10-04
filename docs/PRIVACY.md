# Privacy policy

Updated: October 4, 2026

Record is local-first software. It does not create an account, collect
analytics, upload screenshots or recordings, upload transcripts, sell data, or
automatically send crash reports. Screenshot pixels, recording media, transcripts,
configuration, plugin preferences, and session diagnostics remain on the Mac
where Record runs.

## Files and permissions

Record accesses the microphone, screen, and system audio only after the user
starts a recording, screenshot, dictation, or input test and grants any macOS
permission that action requires. Test Input listens briefly without saving audio.
Quick Dictation saves microphone audio and transcripts locally; copying its text
requires an explicit Copy action. Full-display and area screenshots use Screen
Recording access; window/application screenshots use Apple's selection-scoped
picker. Record writes screenshots and finished sessions to the folder the user approves.
Import Audio and the transcription CLI copy selected files into local sessions;
the originals remain unchanged. CLI output also requires access permitted by
the app sandbox. Each screenshot capture independently attempts to write a
lossless PNG to the local clipboard. Record reads the clipboard only when an
enabled recording-name template explicitly contains the `{clipboard}` token.

## Network access

The main Record app has no network entitlement. Sandboxed helper services make
narrowly scoped update, model-download and reviewed-report connections. At each launch, Sparkle's downloader
checks Record's signed release feed; the same check remains available through
**Check for Updates…**. When the user explicitly chooses **Download and
Install** for Parakeet, a separate model helper downloads only Record's fixed,
pinned model-pack URL. It receives no caller-provided URL, recording content,
transcript, clipboard content, session metadata, diagnostic, local path, or
Record account identifier. These requests disclose ordinary network connection
metadata to GitHub and its release-asset host. Automatic update installation
and Sparkle system profiling are disabled.

The downloaded model is verified before local installation. If the user
explicitly selects MacWhisper, audio is passed locally to the separately
installed MacWhisper app; MacWhisper's own privacy policy and settings then
apply.

If the user enables **Improve Transcript Readability**, bounded transcript
snippets are processed by Apple's on-device Foundation Models framework. They
do not leave the Mac, and Record does not send them to an Apple or third-party
network service. Record preserves the pre-refinement local transcript whenever
the readable output changes.

## Reviewed diagnostic reports

**Help & diagnostics…** opens a preview without uploading anything. The report
contains numeric app/build/macOS versions, fixed capture activity/source and
transcription categories, cleanup/model-setup booleans, and up to 20 event
categories from this launch. It excludes recordings, screenshots, transcripts,
clipboard content, names, paths, session identifiers, raw errors and logs.

You may select a Record `.ips` crash file up to 2 MiB. Record keeps only a
filtered crash category, a known code location and offset, and version numbers.
The raw file and stack symbols stay local. No automatic crash discovery or
submission occurs.

**Send report to developer** sends exactly the displayed report, up to 8 KiB,
to Record's reporting service. That service publishes reports in the public
[Record issue tracker](https://github.com/aindaco1/record/issues) on GitHub and
groups matching reports together. Retrying the same report reuses its identifier
to avoid duplicate counting within the service's retry window. Counts represent
submissions, not unique users or confirmed causes. **Refresh** creates a new report.
The main app remains network-denied; a dedicated helper submits the validated
preview. The [security boundary](security/local-only-boundary.md) describes that
helper and its restrictions.

The relay receives ordinary connection metadata and uses it for abuse prevention,
not issue content. GitHub issues are public. Use [private security reporting](SECURITY.md)
for vulnerabilities. Record keeps one filtered pending report in local preferences
for retry across relaunches; Refresh replaces it, and removing the container deletes
it. Saved JSON remains until you delete it. Published issues are subject to GitHub's
retention and moderation; deleting local data does not remove a public submission.

## Vocabulary and automation

Vocabulary, interface language, microphone choices, and shortcuts are stored
locally. Transcript variants preserve original recognition and the text before
vocabulary corrections. Applying vocabulary again does not modify source audio.

CLI recording commands and Apple Shortcuts use the same local recording controls.
Their responses contain the recording state, not audio, transcript text, or
session paths. A shortcut may open Record and request interactive setup; the
terminal requires the app to be running already.

## Retention and deletion

Record keeps exported screenshots and sessions until the user deletes them.
After a completed session is validated in the approved export folder, Record
deletes its redundant private working copy. Failed or interrupted sessions
remain in private session storage for recovery. Removing Record does not
automatically delete exported screenshots or sessions. Imported source copies and
dictation sessions follow the same retention rules. Removing the app container
also removes its preferences, vocabulary, model, and private recovery sessions;
it does not remove copies exported elsewhere.

## Changes

Material changes to this policy are documented in the [changelog](../CHANGELOG.md).
Questions may be opened through the [support process](SUPPORT.md), but security
or privacy vulnerabilities must use [private vulnerability reporting](SECURITY.md).
