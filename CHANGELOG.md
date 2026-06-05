# Changelog

All notable changes to this project will be documented in this file.

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
