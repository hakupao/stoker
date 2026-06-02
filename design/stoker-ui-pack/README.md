# Stoker UI Pack

This is a non-destructive candidate art package for renaming Activation Timer to Stoker. It does not replace any current app resource.

## Brand Idea

Stoker is the quiet operator that tends the fire: it keeps Claude and Codex usage windows warm, checks quota, and records activity without making noise. The visual system uses an ember core, a schedule arc, a controlled aperture, and a sage quota bead.

## Contents

- `brand-tokens.json`: palette, type, and icon principles.
- `assets/logo/`: mark, wordmark, horizontal lockup, app-icon SVG source, and the Affinity (`.ai`) icon source.
- `assets/png/app-icon/`: 1024 PNG, full macOS iconset, and `Stoker.icns` when `iconutil` is available.
- `assets/icons/cue/`: small option cue icons for settings rows and helper affordances.
- `assets/icons/status/`: active, paused, warning, and error status badges.
- `assets/icons/menubar/`: monochrome template-style menu bar marks.
- `assets/png/scene/`: empty-state and decorative scene art.

## Usage Guidance

- App icon: start with `assets/png/app-icon/Stoker.icns` or the PNG iconset.
- In-app badge: use `assets/logo/stoker-mark.svg` or a rendered PNG derivative.
- Settings option hints: use cue icons at 16-20 pt with secondary label color, not as colorful buttons.
- Status indicators: use status badges only for semantic state, not decoration.
- Menu bar: use the monochrome template variants, not the full app icon.

## Replacement Status

No replacement has been performed. Review this folder first, then selectively copy approved assets into the app bundle/resources in a later pass.
