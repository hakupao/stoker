# Stoker 安装方式

Stoker 会发布成两种形态。

## 小白初学者：菜单栏 App

1. 下载 `stoker-gui-<version>.dmg`，双击打开。安装窗口里有一个从 **Stoker** 指向 **Applications** 的箭头。
2. **顺着箭头，把 `Stoker.app` 拖到 `Applications` 文件夹**。
3. **首次打开（一次性放行）**：双击 `Stoker.app`。第一次会被 macOS 拦下，因为本 App 是开源、仅 ad-hoc 签名（未做 Apple 公证）。按你的系统版本放行一次：
   - **macOS 15（Sequoia）/ macOS 26 及更新**：打开 **系统设置 › 隐私与安全性**，往下找到「已阻止使用 “Stoker”」的提示，点 **仍要打开**，再用 Touch ID / 密码确认。（这些版本上，旧的「右键 → 打开」已经不管用了。）
   - **macOS 14（Sonoma）**：右键点 `Stoker.app` → **打开** → **打开**。

   放行一次之后，以后就能正常双击打开。
4. 在菜单栏下拉中点击 **设置...**，选择运行时间、工具和其他选项。界面跟随系统语言，可用右上角 **EN/中** 切换。
5. 点击 **保存** 应用设置并开启定时。
6. 打开菜单栏下拉，状态会自动刷新，确认定时器已开启。

App 会把工作副本放在：

```text
~/Library/Application Support/Stoker/stoker
```

定时触发仍然由 macOS `launchd` 执行，所以 App 关闭后，已经安装的 schedule 也会继续生效。

## IT 高手：CLI / launchd

1. 下载 `stoker-cli-<version>.tar.gz`。
2. 解压。
3. 复制 `.env.example` 为 `.env`。
4. 运行：

```sh
./install.sh check
./install.sh dry-run
./install.sh install
```

常用命令：

```sh
./install.sh status
./install.sh quota
./install.sh run-now
./install.sh uninstall
```

升级时，把新版本解压后替换旧目录，保留自己的 `.env`，然后重新运行
`./install.sh install`。

## 环境要求

- macOS 和 `launchctl`。
- 已登录的 Claude Code CLI 和/或 Codex CLI。
- `jq`。
- Node.js：用于 Codex quota 快照（可选）。
- oh-my-claudecode 插件：用于 Claude quota 快照（可选；也可用 `CLAUDE_STATUS_SOURCE=native`）。

还没装 CLI？桌面 App 并不自带 CLI，但 CLI 用量和 App 共享同一套订阅额度窗口。
一次性安装，无需 Node 或 Homebrew：

```sh
curl -fsSL https://claude.ai/install.sh | bash   # 装好后运行 `claude` 登录一次
curl -fsSL https://chatgpt.com/codex/install.sh | sh   # 装好后运行 `codex` 登录一次
```

只用其中一个？在 `.env` 里设 `ACTIVATION_TOOL=claude`（或 `codex`）即可。
