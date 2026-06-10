# Stoker Installation

Stoker is published in two forms.

## Beginner: menu bar app

1. Download `stoker-gui-<version>.dmg` and double-click it. The installer window opens with an arrow pointing from **Stoker** to **Applications**.
2. **Drag `Stoker.app` onto the `Applications` folder**, following the arrow.
3. **First launch (one-time approval).** Double-click `Stoker.app`. macOS blocks it the first time because the app is open-source and only ad-hoc signed (not notarized). Approve it once:
   - **macOS 15 (Sequoia) / macOS 26 and later:** open **System Settings › Privacy & Security**, scroll to the note about *“Stoker” was blocked*, click **Open Anyway**, and confirm with Touch ID / your password. (On these versions the old right-click → Open shortcut no longer works.)
   - **macOS 14 (Sonoma):** right-click `Stoker.app` → **Open** → **Open**.

   After approving once, the normal double-click works from then on.
4. From the menu bar dropdown, click **Settings...** and choose your schedule, tools, and other options. The app follows your system language; use the **EN/中** toggle in the top-right corner to switch.
5. Click **Save** to apply your settings and enable the schedule.
6. The status updates automatically — open the menu bar dropdown to confirm the schedule is on.

The app stores its working copy at:

```text
~/Library/Application Support/Stoker/stoker
```

Scheduled activation continues through macOS `launchd`, even when the app is not open.

## Advanced: CLI / launchd

1. Download `stoker-cli-<version>.tar.gz`.
2. Extract it.
3. Copy `.env.example` to `.env`.
4. Run:

```sh
./install.sh check
./install.sh dry-run
./install.sh install
```

Useful commands:

```sh
./install.sh status
./install.sh quota
./install.sh run-now
./install.sh uninstall
```

To upgrade, replace the extracted folder with the new release, keep your `.env`,
then run `./install.sh install` again.

## Requirements

- macOS with `launchctl`.
- Authenticated Claude Code CLI and/or Codex CLI.
- `jq`.
- Node.js for Codex quota snapshots (optional).
- oh-my-claudecode plugin for Claude quota snapshots (optional; or `CLAUDE_STATUS_SOURCE=native`).

Don't have the CLIs yet? The desktop apps don't ship them, but CLI usage shares the
same subscription quota windows as the apps. One-time setup, no Node or Homebrew:

```sh
curl -fsSL https://claude.ai/install.sh | bash   # then run `claude` to log in once
curl -fsSL https://chatgpt.com/codex/install.sh | sh   # then run `codex` to log in once
```

Only using one of the two? Set `ACTIVATION_TOOL=claude` (or `codex`) in `.env`.
