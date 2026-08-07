# Privacy policy

Effective: August 7, 2026

Record is local-first software. It does not create an account, collect
analytics, upload recordings, upload transcripts, sell data, or send crash
reports. Recording media, transcripts, configuration, plugin preferences, and
session diagnostics remain on the Mac where Record runs.

## Files and permissions

Record accesses the microphone, screen, and system audio only after the user
starts the corresponding recording mode and grants macOS permission. It writes
finished sessions only to a folder the user approves. It may read the clipboard
only when an enabled recording-name template explicitly contains the
`{clipboard}` token.

## Network access

The main Record app has no network entitlement. When the user chooses **Check
for Updates…**, Sparkle's sandboxed downloader contacts Record's public GitHub
release feed. That request includes ordinary network connection metadata but
does not contain recording content, transcripts, clipboard content, session
metadata, or a Record account identifier. Automatic update checks are disabled.

Record does not download transcription models. If the user explicitly selects
MacWhisper, audio is passed locally to the separately installed MacWhisper app;
MacWhisper's own privacy policy and settings then apply.

## Retention and deletion

Record keeps files until the user deletes them. After a completed session is
validated in the approved export folder, Record deletes its redundant private
working copy. Failed or interrupted sessions remain in private session storage
for recovery. Removing Record does not automatically delete exported sessions.

## Changes

Material changes to this policy are documented in the repository changelog.
Questions may be opened through the public support process, but security or
privacy vulnerabilities must use GitHub's private vulnerability reporting.
