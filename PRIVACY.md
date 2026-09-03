# Privacy policy

Effective: September 2, 2026

Record is local-first software. It does not create an account, collect
analytics, upload screenshots or recordings, upload transcripts, sell data, or
send crash reports. Screenshot pixels, recording media, transcripts,
configuration, plugin preferences, and session diagnostics remain on the Mac
where Record runs.

## Files and permissions

Record accesses the microphone, screen, and system audio only after the user
starts the corresponding recording or screenshot command and grants any macOS
permission that command requires. Full-display and area screenshots use Screen
Recording access; window/application screenshots use Apple's selection-scoped
picker. Record writes screenshots and finished sessions only to one folder the
user approves. Each screenshot capture independently attempts to write a
lossless PNG to the local clipboard. Record reads the clipboard only when an
enabled recording-name template explicitly contains the `{clipboard}` token.

## Network access

The main Record app has no network entitlement. Sandboxed helper services make
two narrowly scoped GitHub connections. At each launch, Sparkle's downloader
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

## Retention and deletion

Record keeps exported screenshots and sessions until the user deletes them.
After a completed session is validated in the approved export folder, Record
deletes its redundant private working copy. Failed or interrupted sessions
remain in private session storage for recovery. Removing Record does not
automatically delete exported screenshots or sessions.

## Changes

Material changes to this policy are documented in the repository changelog.
Questions may be opened through the public support process, but security or
privacy vulnerabilities must use GitHub's private vulnerability reporting.
