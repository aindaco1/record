# Settings UX review and implementation

Date: 2026-10-03. Scope: Record 1.5.0 candidate, unpublished.

## Findings

The General page sent users to separate Recent Sessions and Ready to Record
windows. Recording controls were split between Recording and Audio; screenshot
and recording shortcuts lived on different pages. Filename templates required an
Edit dialog. Unavailable options depended on tooltips, descriptions were capped
at two lines, and standard text editing lacked a responder path in this menu-bar
app. These issues made common tasks harder to find and complete.

## Implemented layout

The user selected one native sidebar window. The six destinations are:

| Page | Direct controls |
|---|---|
| Recording | Mode, screen source, audio sources, microphone, input test, activity, compact panel, readiness, permissions and Start |
| Sessions | Current-folder and private-recovery browser, filter, raw/clean preview, copy, playback, reveal, retry and defer |
| Transcription | Engine, optional model setup/status, cleanup preference and availability explanation |
| Screenshots | Format, JPEG quality, shutter sound |
| Shortcuts | All recording and screenshot assignments, screenshot-only reset, system shortcut settings |
| General | Shared save folder, inline names and example, capture privacy, login and diagnostics |

Menu commands select Recording or Sessions in the same window. The sidebar
retains its selected page; ordinary section changes do not recreate the window.
Pages use native controls, wrapping text and small shared layout helpers. The
session browser retains its existing local reader and releases browsing resources
when hidden. Input tests stop when leaving Recording or closing the window.

## Interaction details

- Invalid name tokens leave the last valid preference saved. The preview uses
  placeholder clipboard text through the existing RecordCore renderer.
- Source and input controls follow the existing capture-busy state. Audio-only
  mode disables the screen-source choice. No new capture or permission path.
- Command-A/C/X/V and undo reach native text responders; Command-W closes Settings.
- Sidebar rows and controls have accessible names. Unavailable cleanup and model
  states have visible explanations; color is supplementary.
- The sidebar, scrollable pages and resizable window replace nested navigation
  without adding a new settings model, dependencies, search, or history database.

## Acceptance

Focused regression tests cover stable window/page ownership, valid/invalid name
editing, safe clipboard examples, native select-all, and disabled recording
controls. Native visual and keyboard evidence is tracked in
[candidate testing](../testing/1.5.0-candidate.md). This review does not waive the
remaining capture, hardware, or public-release acceptance checks.
