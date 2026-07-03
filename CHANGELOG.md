# Changelog

All notable changes to this project will be documented in this file.

## 0.3.4 - 2026-07-03

### Fixed
- **The menu bar app pinned a CPU core at ~100% again once the main window had been opened while
  the schedule was lit — and kept burning after the window was closed.** 0.3.3 silenced the flame
  flicker's animated relayout on the menu-bar label, but the 0.45s frame counter still lived as a
  `@Published` property on the shared app model, and `objectWillChange` invalidates *every* view
  observing that object — including the main window's entire view tree, which macOS keeps alive
  (offscreen) after the window closes. Each tick re-rendered the Activity tab's Swift Charts
  history at a cost exceeding the tick interval, so the render loop never went idle (measured:
  40+ hours of accumulated CPU and ~835 MB resident on a 0.3.3 bundle). The counter now lives in
  a dedicated `FlameTicker` observable (StokerCore) observed only by the menu-bar label, so a
  tick invalidates nothing but the 18 pt icon no matter which windows exist: measured on the same
  machine, replaying the same open-window-then-close trigger, CPU is 0.1–1.6% with flat ~130 MB
  memory and the flicker preserved. Ticks also apply synchronously in the timer callback
  (`MainActor.assumeIsolated` rather than a `Task` hop), so stopping the schedule can no longer
  race a stale tick back onto a freshly reset frame counter.

## 0.3.3 - 2026-06-22

### Fixed
- **The menu bar app pinned a CPU core at ~100% (and grew to ~1 GB resident) the whole time the
  schedule was lit.** Stoker's flame icon flickers via a 0.45s `@Published` frame counter; left to
  its default transaction, every frame swap drove an *animated* status-item relayout
  (`NSAnimationContext.runAnimationGroup`) whose ~0.45s duration matched the tick interval — so the
  animations ran back-to-back and SwiftUI's display link never went idle, leaving a full view-tree
  layout/render loop spinning on the main thread. It burned a core even with the window closed,
  because the driver is the always-present `MenuBarExtra` label rather than any window. The label
  now disables implicit animation (`.transaction { $0.animation = nil }`), making each frame an
  instant redraw: measured on the same machine, CPU dropped from ~100% to ~1% (process state
  `running` → `sleeping`) and resident memory from ~1053 MB to ~18 MB, with the flicker preserved.

## 0.3.2 - 2026-06-12

### Keychain-safe quota tracking (CLI)
- Claude quota snapshots no longer shell out to `omc wait status`. In an unattended run that
  live query read the shared macOS Keychain OAuth login and, once the ~8-hour access token had
  expired, consumed its refresh token without being able to persist the replacement — silently
  logging the interactive Claude Code session out (the "must log in again every morning" bug).
  The new default `CLAUDE_STATUS_SOURCE=cache` reads the oh-my-claudecode plugin's local usage
  cache directly: no subprocess, no network, no credentials. The live query remains available as
  an explicit `CLAUDE_STATUS_SOURCE=omc` opt-in. (Root cause reported upstream and fixed:
  oh-my-claudecode#3238.)
- New `CLAUDE_STATUS_SOURCE=native` tracks Claude quota with **no omc plugin at all**: it reads
  the Keychain token read-only and queries Anthropic's usage endpoint, hard-skipping whenever
  the token has expired — it never refreshes anything, and the token never appears in argv,
  `ps` output, or logs.
- Quota preflight no longer treats a window as exhausted once its `resets_at` has passed, so
  stale last-known data can't skip the first run after an overnight reset. Snapshot rows now
  record `status_source` and `cache_age_seconds`.

### Honest quota display (menu bar app)
- The Activity gauges, header bars, and menu summary no longer present frozen snapshot numbers
  as current (the app could show "5h 70% used" while the live figure was 4%). The state contract
  now prefers the live plugin cache whenever it is newer than the last snapshot, stamps the
  display with the time the data was actually **captured** (not when the snapshot was written),
  and blanks any window whose reset has already passed instead of showing stale percentages.
- The quota card's empty state now points at both ways to enable quota tracking (the
  oh-my-claudecode plugin, or `CLAUDE_STATUS_SOURCE=native`).

### Install guidance
- Fixed the onboarding install hint for `omc`, which pointed at an unrelated squatted npm
  package — the real package behind the `omc` binary is `oh-my-claude-sisyphus`. The claude and
  codex hints now use the official curl installers (the desktop apps don't ship the CLIs).
- The app's environment check now respects `ACTIVATION_TOOL`: a Claude-only (or Codex-only)
  setup is no longer nagged about the other CLI.
- New "Don't have the CLIs yet?" sections in README/INSTALL (EN + CN) with one-line installers
  and the note that CLI usage shares the same subscription quota windows as the desktop apps;
  `install.sh check` now prints an installer hint when a CLI is missing.

## 0.3.1 - 2026-06-08

### Quota chart redesign (menu bar app)
- The Activity tab's quota chart is now a clearer **Quota Overview**: per-tool gauges show the
  current remaining quota with an explicit "Remaining N%" label (health-colored, so low quota warns
  at a glance) and a reset countdown, above a clean mini-trend. The trend drops the decorative
  shaded area, breaks the line at each window reset instead of drawing a misleading "refill" ramp,
  dots the real snapshots, adds top headroom so a full 100% no longer clips, and shows the value on
  hover.
- A tool that isn't reporting now reads an honest "Quota unknown" with an "updated HH:mm" stamp
  instead of a blank or misleading line.
- The quota *health* color is now shared between the header mini-bar and the gauge (one definition),
  and the gauge reads the same single quota source as the header and the menu summary instead of
  recomputing it.

## 0.3.0 - 2026-06-05

### Headless authentication (CLI)
- Scheduled `claude -p` runs can now authenticate with a dedicated long-lived
  `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) set in `.env`, instead of borrowing the
  short-lived interactive Keychain login. That shared login was being rotated out from under
  unattended runs and caused intermittent `401 Invalid authentication credentials`. The token
  bills against your existing Claude subscription (no extra API charges); `dry-run` and
  `activation.log` now report the auth mode, and a failed run prints an actionable re-mint hint.

### One-click background authentication (menu bar app)
- New **Background auth** card in Settings shows at a glance whether scheduled runs use their own
  long-lived token or are falling back to the rotating Keychain login, with one-click setup.
- **Configure token** runs `claude setup-token` for you in a pseudo-terminal (so the real OAuth
  browser flow opens), captures the printed `sk-ant-oat01-…`, and writes it to `.env` — no
  terminal, no copy-paste. A manual "run in Terminal + paste" path with format validation is
  always available as a fallback, and token capture is hardened (escape-stripped, frame-split,
  length-checked) so a truncated or garbled value can never overwrite a working token.
- A compact auth-status chip in the header (visible from both tabs) jumps straight to the card and
  highlights it.

## 0.2.4 - 2026-06-02

### Run history — clear status markers
- Activity log rows now show a normalized status marker (icon + word, colored to match the row)
  — Success / Skipped · reason / Failed · exit N — instead of the model's raw reply text, which
  was chatty and differed on every run. The full model reply moves into the expanded row detail.
- Sub-cent Claude check-in costs no longer round to "$0.00"; amounts below a cent now show with
  enough precision to read the real number.

### Reliable language switching
- Switching the UI language now updates the whole window immediately. Some views (notably the
  run-history rows) previously re-localized only after a hover, because the language was not an
  observable source of truth.
- Closed i18n gaps: the language-toggle tooltip, the Settings tab label, and the onboarding tool
  descriptions (which were frozen at check time) now all follow the active language.

## 0.2.3 - 2026-05-31

### New app icon
- Replaced the app icon with a refined vector master (the ember-aperture "Forge" mark),
  rendered into the full macOS iconset and `Stoker.icns` from
  `design/stoker-ui-pack/assets/logo/stoker-app-icon-master.pdf`. The Dock/Finder icon, the
  in-window badge, the DMG volume icon, and both README headers now use the new art; the
  monochrome menu-bar template is intentionally unchanged.
- The icon pipeline now renders from the committed vector master (sips + Pillow, no rsvg
  dependency) and no longer reverts to the previous AI-concept render on rebuild. The retired
  concept builder and its 1.8 MB raster were removed.

## 0.2.2 - 2026-05-30

### Codex model selection
- New `CODEX_MODEL` setting (default `gpt-5.4-mini`; set `default` to let the Codex CLI choose).
  The runner passes `--model` to Codex unless it is `default`, records the model in
  `logs/usage.jsonl`, and reports it in `./install.sh check`.
- Added a **Codex model** field in the menu bar app's Advanced settings, surfaced through the
  app-status JSON contract (`config.codex_model`).

### Installer (DMG) — beginner-friendly
- The GUI DMG now opens a **branded "Forge" installer window**: a warm background with an ember
  arrow from **Stoker** to **Applications**, bilingual drag-to-install and first-launch steps,
  proper icon layout, and a custom volume icon (graceful fallback to a plain DMG if Finder
  styling is unavailable). The background is rendered deterministically and regenerated at
  package time.
- **Fixed: the app bundle was never code-signed.** `build-app.sh` now seals the whole bundle
  with a deep ad-hoc signature as the final step, so a downloaded copy is a valid bundle that
  macOS treats as "unidentified developer" (approvable) instead of **damaged**.
- First-launch instructions corrected for **macOS 15 (Sequoia) / macOS 26+**: approve via
  **System Settings › Privacy & Security › Open Anyway** (the old right-click → Open shortcut no
  longer works on those versions); macOS 14 still uses right-click → Open.
- OS-generated `.fseventsd`/`.Trashes` are removed from the image so the installer window stays
  clean even when "show hidden files" is enabled.

### Documentation & compliance
- Rebuilt `README.md` / `README_CN.md` into a polished "GitHub app page" layout (centered app
  icon, badges, light + dark bilingual screenshots) using the new ember "Forge" app icon, and
  refreshed all menu bar app screenshots.
- Updated `INSTALL.md` / `INSTALL_CN.md` to mirror the new installer flow and per-macOS-version
  first-launch approval.
- Added **`DISCLAIMER.md`** (no-affiliation, trademark, no-warranty, terms-of-service
  responsibility, cost/quota, privacy, and bundled-`jq` third-party notices) and **`SECURITY.md`**
  (vulnerability reporting), with Disclaimer sections linked from both READMEs.

## 0.2.1 - 2026-05-29

### "Forge" design language — refreshed UI and icon
- New ember-on-graphite visual system. When the schedule turns on, the **entire window — header included — warms together** from a cool idle palette to a warm ember "active" state, in both Light and Dark. This replaces the old partial pale-green tint that only covered part of the window.
- Introduced an appearance- and state-aware `StokerTheme` (Light/Dark × idle/active) driven from a single `design-tokens.json`; all text/surface pairings are WCAG contrast-checked.
- New app icon: an ember/aperture "forge" mark replacing the generic blue/teal/gold clock-and-bolt, with transparent squircle corners and distinct simplified artwork at small sizes. The Dock icon, the in-window badge, and the menu-bar mark are now consistent.
- The menu-bar icon is now a branded monochrome template mark instead of the stock SF "timer" symbol.

### Project rename — Activation Timer is now Stoker
- Renamed the project and app from **Activation Timer** to **Stoker** (Chinese name 司炉 — the person who keeps a furnace fed so the fire never goes out).
- Bundle identifier changed from `com.activation-timer.menu-bar` to `com.stoker.menu-bar`; the LaunchAgent label changed from `com.activation-timer.ai-window` to `com.stoker.ai-window`.
- The menu bar app's working copy moved from `~/Library/Application Support/Activation Timer/` to `~/Library/Application Support/Stoker/`.
- Upgrading in place automatically boots out the old `com.activation-timer.ai-window` LaunchAgent (wired into `LEGACY_LABELS`); reinstall/reload the schedule after updating.
- Old data under `~/Library/Application Support/Activation Timer/` is left untouched — remove it manually once you have confirmed the new install works.

## 0.2.0 - 2026-05-29

### Menu bar app
- Rebuilt the menu bar app into a two-tab control panel: **Activity** and **Settings**.
- Activity dashboard: per-tool quota-trend chart (5-hour / weekly), a run-history timeline with expandable per-run details (tokens, cost, duration, session), summary stats (total / success / skipped / errors / average cost), and date-range / status / tool filters.
- Export run history to CSV.
- Bilingual in-app UI with an EN / 中 switch (previously only the documentation was bilingual).
- Appearance now follows the system Light/Dark setting instead of a fixed theme.
- Environment Check onboarding that detects required and optional CLI tools and shows install hints.
- In-app schedule editing with independent add/remove time points, per-tool enable toggles, and advanced options (quota preflight, post-run snapshots, keep-awake mode and duration, launch at login).
- The main window now comes to the front when opened from the menu.

### Fixes & reliability
- Fixed unreadable secondary text (dark-on-dark in Light mode) and the Quota Trend chart bleeding outside its card.
- Made activation timing reproducible across machines; runtime status checks are easier to discover.
- Skip prompts gracefully when a quota is already exhausted.
- Guarded `ProjectLocator` against an infinite directory walk; stabilized CI (pinned runner/Xcode/Homebrew, removed a deprecated Actions runtime).

### Internal
- Split the menu bar app into modular views (`MainView` / `ActivityView`) plus a `LogStore` core type.

## 0.1.0 - 2026-05-27

- Initial macOS `launchd` activation scheduler.
- Added Claude Code and Codex low-cost activation runner.
- Added structured usage and quota snapshot logs.
- Added quota preflight so exhausted quotas are skipped and logged before prompts are sent.
- Added optional macOS menu bar app distribution that reuses the existing CLI/launchd engine.
- Added JSON app status output through `./install.sh app-status`.
- Added keep-awake settings backed by macOS `caffeinate`.
- Added release packaging for separate CLI and GUI artifacts.
- Added generated macOS app icon and beginner-focused installation docs.
- Added configurable `.env` support.
- Added English and Chinese documentation.
- Added validation script and GitHub Actions workflow.
