# Installing Stoker

[English](INSTALL.md) · [中文](INSTALL_CN.md)

There are two ways to install. Both run the same scheduler.

- [Menu bar app](#menu-bar-app): for most people.
- [Command line](#command-line): for terminal users who want the lightest install.

## Before you start

- macOS 14 or later.
- The Claude Code CLI, the Codex CLI, or both, signed in with your subscription.
- For the command line install: `jq` (`brew install jq`). The app includes it.
- Optional, for quota tracking: Node.js (Codex) and the oh-my-claudecode plugin (Claude).
  Without the plugin, set `CLAUDE_STATUS_SOURCE=native`.

The Claude and ChatGPT desktop apps do not include the CLIs. Install them separately:

```sh
curl -fsSL https://claude.ai/install.sh | bash          # then run `claude` once to sign in
curl -fsSL https://chatgpt.com/codex/install.sh | sh    # then run `codex` once to sign in
```

Using only one tool? Turn the other off in the app's Settings, or set
`ACTIVATION_TOOL=claude` or `ACTIVATION_TOOL=codex` in `.env`.

## Menu bar app

### 1. Download and copy

1. Download `stoker-gui-<version>.dmg` from the
   [latest release](https://github.com/hakupao/stoker/releases/latest) and open it.
2. Drag `Stoker.app` onto the `Applications` folder.
3. Open `Stoker.app` from `Applications`, not from inside the DMG.

### 2. Approve the first launch

Stoker is open source and is not notarized with a paid Apple Developer ID. macOS therefore
blocks it the first time. You approve it once.

1. Double-click `Stoker.app`. A dialog says *"Stoker" Not Opened*.
2. Click **Done**. On macOS 14 the button is **Cancel**. Do not click **Move to Trash**.
3. Approve the app. The steps depend on your macOS version.

**macOS 15 Sequoia, macOS 26 and later**

1. Open **System Settings › Privacy & Security**.
2. Scroll down to **Security**. It says *"Stoker" was blocked to protect your Mac.*
3. Click **Open Anyway**.
4. Confirm with Touch ID or your password.
5. Click **Open Anyway** in the last dialog.

The **Open Anyway** button shows for about an hour after the blocked launch. If it is
missing, double-click `Stoker.app` again and come back. On these versions, right-click then
Open no longer works.

**macOS 14 Sonoma**

1. Right-click `Stoker.app` and choose **Open**.
2. Click **Open** in the dialog.

**Still blocked?**

If macOS says the app *is damaged and can't be opened*, or **Open Anyway** never appears,
run this in Terminal and open the app again:

```sh
xattr -dr com.apple.quarantine /Applications/Stoker.app
```

This removes the "downloaded from the internet" flag from this one app. It changes no system
setting.

After you approve it once, the app opens normally. After you replace it with a newer
version, macOS may ask once more.

### 3. Set it up

1. Click the flame in the menu bar and choose **Settings...**.
2. In the **Schedule** card, pick the days and times for Claude and for Codex. Both start
   with 07:00, 12:00, 17:00 and 22:00, every day. The card also shows the usage windows
   Stoker detected and the schedule it recommends.
3. Turn each tool on or off in its own card.
4. In the **Claude Settings** card, under **Background auth**, click **Configure token** and finish the sign-in in the browser.
   Without it, scheduled Claude runs can fail with a 401 error.
5. Click **Save**. This turns the schedule on.

The menu bar menu shows whether the schedule is on. Use the **EN/中** button at the top
right to change the language.

The schedule keeps running when the app is closed. The app keeps its engine, settings and
logs in:

```text
~/Library/Application Support/Stoker/stoker
```

## Command line

1. Download `stoker-cli-<version>.tar.gz` from the
   [latest release](https://github.com/hakupao/stoker/releases/latest) and extract it. Or
   clone the repository.
2. In that folder, copy the settings template:

   ```sh
   cp .env.example .env
   ```

3. Check, preview, then install:

   ```sh
   ./install.sh check      # are the tools installed?
   ./install.sh dry-run    # show what would be sent, send nothing
   ./install.sh install    # load the schedule
   ```

4. Give scheduled Claude runs a long-lived sign-in:

   ```sh
   claude setup-token      # opens a browser and prints sk-ant-oat01-...
   ```

   Put the token in `.env` as `CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."`.

Useful commands afterwards:

```sh
./install.sh status       # is the schedule loaded?
./install.sh recommend    # your detected windows and the schedule that fits
./install.sh quota        # record your quota, send nothing
./install.sh run-now      # send one check-in now (uses quota)
./install.sh uninstall    # remove the schedule
```

## Upgrading

- **App:** replace `Stoker.app` with the new one. Then turn the schedule off and on once.
- **Command line:** replace the folder with the new release and keep your `.env`. Then run
  `./install.sh install` again.

## More

[README.md](README.md) explains what Stoker does. [REFERENCE.md](REFERENCE.md) lists every
setting.
