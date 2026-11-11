# 安装 Stoker

[English](INSTALL.md) · [中文](INSTALL_CN.md)

有两种安装方式。两种方式用的是同一套定时。

- [菜单栏 App](#菜单栏-app)：适合大多数人。
- [命令行](#命令行)：适合习惯终端、想要最轻量安装的用户。

## 开始之前

- macOS 14 或更新版本。
- Claude Code CLI、Codex CLI，或者两者都装，并已用你的订阅登录。
- 用命令行安装时需要 `jq`（`brew install jq`）。App 已经自带。
- 可选，用于跟踪额度：Node.js（Codex 用）和 oh-my-claudecode 插件（Claude 用）。没有这个插件时，设置 `CLAUDE_STATUS_SOURCE=native`。

Claude 和 ChatGPT 的桌面 App 不包含这些 CLI，需要单独安装：

```sh
curl -fsSL https://claude.ai/install.sh | bash          # 装好后运行一次 `claude` 登录
curl -fsSL https://chatgpt.com/codex/install.sh | sh    # 装好后运行一次 `codex` 登录
```

只用其中一个工具？在 App 的设置里关掉另一个，或者在 `.env` 里设置 `ACTIVATION_TOOL=claude` 或 `ACTIVATION_TOOL=codex`。

## 菜单栏 App

### 1. 下载并拷贝

1. 从[最新版本](https://github.com/hakupao/stoker/releases/latest)下载 `stoker-gui-<version>.dmg`，然后打开它。
2. 把 `Stoker.app` 拖到 `Applications` 文件夹上。
3. 从 `Applications` 里打开 `Stoker.app`。不要直接在 DMG 里打开。

### 2. 放行第一次启动

Stoker 是开源软件，没有用付费的 Apple Developer ID 做公证。所以第一次打开时，macOS 会拦下它。你只需要放行一次。

1. 双击 `Stoker.app`。弹窗提示「未打开『Stoker』」。
2. 点击 **完成**。macOS 14 上这个按钮是 **取消**。不要点 **移到废纸篓**。
3. 放行 App。步骤取决于你的 macOS 版本。

**macOS 15 Sequoia、macOS 26 及更新版本**

1. 打开 **系统设置 › 隐私与安全性**。
2. 往下滚到 **安全性**。这里会提示 Stoker 已被阻止，以保护你的 Mac。
3. 点击 **仍要打开**。
4. 用 Touch ID 或密码确认。
5. 在最后的对话框里点击 **仍要打开**。

被拦下后，**仍要打开** 按钮大约会显示一小时。找不到这个按钮时，再双击一次 `Stoker.app`，然后回到这里。在这些版本上，右键再选「打开」已经不管用了。

**macOS 14 Sonoma**

1. 右键点 `Stoker.app`，选择 **打开**。
2. 在对话框里点击 **打开**。

**还是打不开？**

如果 macOS 提示 App「已损坏，无法打开」，或者 **仍要打开** 一直不出现，就在「终端」里运行下面的命令，然后再打开 App：

```sh
xattr -dr com.apple.quarantine /Applications/Stoker.app
```

它只去掉这一个 App 的「从互联网下载」标记，不改动任何系统设置。

放行一次之后，App 就能正常打开。换成新版本后，macOS 可能会再问一次。

### 3. 完成设置

1. 点击菜单栏里的火苗，选择 **设置...**。
2. 在「运行时间」卡片里，分别为 Claude 和 Codex 选好星期和时间。两者一开始都是每天 07:00、12:00、17:00 和 22:00。这张卡片还会显示 Stoker 检测到的用量窗口，以及它推荐的运行时间。
3. 在「Claude 设置」和「Codex 设置」卡片里，分别打开或关闭对应的工具。
4. 在「Claude 设置」卡片的「后台认证」一栏里点击 **配置长效令牌**，然后在浏览器里完成登录。不配置的话，定时运行 Claude 可能会因为 401 错误而失败。
5. 点击 **保存**。这会开启定时。

菜单栏的下拉菜单会显示定时是否已开启。点击右上角的 **EN/中** 按钮可以切换语言。

App 关闭后，定时仍会继续运行。App 把它的引擎、设置和日志放在：

```text
~/Library/Application Support/Stoker/stoker
```

## 命令行

1. 从[最新版本](https://github.com/hakupao/stoker/releases/latest)下载 `stoker-cli-<version>.tar.gz` 并解压。也可以直接克隆仓库。
2. 在这个文件夹里，复制设置模板：

   ```sh
   cp .env.example .env
   ```

3. 依次检查、预览，然后安装：

   ```sh
   ./install.sh check      # 工具都装好了吗？
   ./install.sh dry-run    # 显示会发送什么，但不发送
   ./install.sh install    # 加载定时
   ```

4. 给定时运行的 Claude 配置一个长效登录：

   ```sh
   claude setup-token      # 打开浏览器，并打印出 sk-ant-oat01-...
   ```

   把令牌写进 `.env`：`CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."`。

之后常用的命令：

```sh
./install.sh status       # 定时加载了吗？
./install.sh recommend    # 检测到的窗口，以及适合它们的运行时间
./install.sh quota        # 记录额度，不发送任何内容
./install.sh run-now      # 立刻发送一次激活（消耗额度）
./install.sh uninstall    # 移除定时
```

## 升级

- **App：** 用新的 `Stoker.app` 替换旧的。然后把定时关掉再打开一次。
- **命令行：** 用新版本替换整个文件夹，保留你的 `.env`。然后重新运行 `./install.sh install`。

## 更多

[README_CN.md](README_CN.md) 介绍 Stoker 能做什么。[REFERENCE_CN.md](REFERENCE_CN.md) 列出所有设置。
