# ADR 0008: Keep system content selections ephemeral

## Context

Record 1.0 captured the main display directly even though the capture adapter
already modeled displays, applications, windows, and regions. A user-facing
picker must expose those sources without creating a second filter policy or a
preferences database of potentially sensitive window metadata.

## Decision

Use Apple's shared `SCContentSharingPicker` for display, application, and
independent-window selection. Retain the returned `SCContentFilter` only in
memory for the pending or active recording. Persist only whether the user wants
the main-display fast path, the system picker, or a custom region on the next
recording.

For screen recordings, custom-region selection uses the system picker to choose
a display and a short-lived, noncapturing AppKit overlay to produce
display-local geometry. The overlay itself never captures pixels. ADR 0014
reuses that overlay for area screenshots, then performs the separate one-shot
capture only after the overlay is gone. Before starting a selected display or
region, Record resolves the display again and rebuilds the filter through the
existing capture-privacy policy so own-app, notification, menu-bar, and
desktop-item rules are not duplicated.

## Consequences

- Window titles, application names, source identifiers, and regions do not
  enter `UserDefaults`, session manifests, diagnostics, or exported files.
- A saved picker mode asks for a fresh source after every launch or recording.
- A selected source disappearing fails closed; Record does not silently switch
  to the main display.
- Region coordinates and picker behavior still require signed-app hardware/TCC
  acceptance in addition to deterministic geometry and filter-plan tests.
