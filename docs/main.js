/* =========================================================================
   Stoker landing page — interactions
   Zero dependencies. Respects prefers-reduced-motion.
   ========================================================================= */
(function () {
  "use strict";

  var html = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var canHover = window.matchMedia("(hover: hover)").matches;

  /* ---------------- i18n ---------------- */
  var I18N = {
    en: {
      "a11y.skip": "Skip to content",
      "meta.description": "A tiny macOS launchd scheduler that sends low-cost Claude Code and Codex check-ins on a schedule you choose — then logs every run, token, and quota snapshot. Runs entirely on your Mac.",
      "alt.activity": "Stoker activity dashboard — quota trends and per-run history",
      "alt.settings": "Stoker settings — per-tool schedules (Claude and Codex each with their own days and times), tool cards, and advanced options",
      "nav.features": "Features", "nav.how": "How it works", "nav.cost": "Cost", "nav.faq": "FAQ", "nav.download": "Download",
      "hero.eyebrow": "Keep the fire lit.",
      "hero.title": "Keep your Claude Code & Codex usage windows lit.",
      "hero.sub": "A tiny macOS launchd scheduler that sends low-cost check-ins at the times you choose — then logs every run, token, and quota snapshot. Runs entirely on your Mac.",
      "hero.cta_primary": "Download for macOS", "hero.cta_secondary": "View on GitHub",
      "hero.meta": "v0.3.6 · macOS 14+ · Free & open source (MIT)",
      "hero.schedule_label": "Default schedule · per tool",
      "hero.schedule_sr": "Default schedule for both Claude and Codex: 07:00, 12:00, 17:00 and 22:00 — set each tool's own times and days.",
      "problem.title": "Usage windows reset on a clock — not on your schedule.",
      "problem.sub": "If the first prompt of a window lands late, the whole window shifts late. Stoker fires a tiny check-in at fixed times so your windows open when you actually start working.",
      "problem.c1.t": "Fixed start times", "problem.c1.d": "Pick the hours and days that match your week — separately for Claude and Codex; each time fires independently.",
      "problem.c2.t": "Quota you can see", "problem.c2.d": "Five-hour and weekly snapshots recorded after every run.",
      "problem.c3.t": "Skips when exhausted", "problem.c3.d": "Quota preflight skips a tool gracefully instead of wasting a call.",
      "film.title": "Stoker in 40 seconds.", "film.sub": "What it does, how the schedule works, and what you see in the app.", "film.aria": "Stoker promo video",
      "how.title": "How it works", "how.sub": "Every run is the same calm, four-beat loop.",
      "how.s1.t": "Load & lock", "how.s1.d": "Reads .env, then takes a lock — a trigger that fires at the same moment waits its turn.",
      "how.s2.t": "Quota preflight", "how.s2.d": "Checks quota before sending. Exhausted tools are skipped and logged.",
      "how.s3.t": "Send a tiny prompt", "how.s3.d": "Each CLI gets a tiny check-in, kept to its own folder — no tools run, your real projects never touched.",
      "how.s4.t": "Record & release", "how.s4.d": "Appends usage + quota snapshots, then releases the lock for next time.",
      "feat.title": "Small tool, fully accountable.",
      "feat.f1.t": "Scheduled activation", "feat.f1.d": "Triggers Claude Code and Codex through macOS launchd — each tool on its own times and days.",
      "feat.f2.t": "Minimal, safe prompt", "feat.f2.d": "Each check-in stays tiny and read-only, kept to its own folder — never your real projects.",
      "feat.f3.t": "Readable run history", "feat.f3.d": "Every activation in plain text at logs/activation.log.",
      "feat.f4.t": "Per-run usage records", "feat.f4.d": "Structured token and cost rows in logs/usage.jsonl.",
      "feat.f5.t": "Quota snapshots", "feat.f5.d": "Five-hour and weekly quota status in logs/status.jsonl.",
      "feat.f6.t": "Quota preflight", "feat.f6.d": "Skips activation gracefully when a known quota is exhausted.",
      "feat.f7.t": "Clone-friendly config", "feat.f7.d": "Per-tool schedules, tools, prompts, timeouts and paths — all in one .env.",
      "cost.title": "Honest about cost. About a quarter of a cent.",
      "cost.sub": "Stoker sends real prompts, so it uses real quota. Here is exactly how much.",
      "cost.claude": "~1.6K input tokens · ≈ $0.0025 per activation",
      "cost.codex": "~38K input tokens per activation (~55% cache reads)",
      "cost.month": "≈ $0.30 / month for Claude at 4 activations a day.",
      "cost.note": "The bottleneck is the system prompt each CLI injects — Stoker keeps its own prompt under ~300 tokens.",
      "shots.title": "Built to be watched, not babysat.",
      "shots.sub": "A native menu bar app over the same engine — bilingual, light or dark.",
      "shots.tab_activity": "Activity", "shots.tab_settings": "Settings",
      "trust.b1": "Independent & unofficial", "trust.b2": "100% local — no data sent to the author", "trust.b3": "Open source · MIT",
      "trust.note": "Not affiliated with, endorsed, or sponsored by Anthropic, OpenAI, or Apple. Stoker uses your real quota; you are responsible for complying with each provider's terms.",
      "faq.title": "Questions, answered plainly.",
      "faq.q1": "How much does it cost to run?",
      "faq.a1": "About $0.0025 per Claude activation (~1.6K tokens). Roughly $0.30/month at four runs a day. Codex uses your plan quota.",
      "faq.q2": "Does it consume my quota?",
      "faq.a2": "Yes — it sends real prompts. That is the point. Quota preflight skips a tool when its quota is already exhausted.",
      "faq.q3": "Is it safe? Does it touch my projects?",
      "faq.a3": "No. It runs in its own folder with a tiny read-only check-in, and never reads or modifies your real projects. dry-run and quota send nothing.",
      "faq.q4": "Is this official?",
      "faq.a4": "No. Stoker is an independent open-source project, not affiliated with Anthropic, OpenAI, or Apple. You are responsible for following their terms.",
      "faq.q5": "How do I uninstall?",
      "faq.a5": "Run ./install.sh uninstall (or use the menu bar app) to unload and remove the LaunchAgents.",
      "faq.q6": "macOS says Stoker can’t be opened — what do I do?",
      "faq.a6": "That’s expected on first launch: the app is open source and ad-hoc signed, not notarized. Click Done, then open System Settings › Privacy & Security and click Open Anyway (on macOS 14, right-click the app ▸ Open). If it says the app is damaged, run xattr -dr com.apple.quarantine /Applications/Stoker.app in Terminal. You only do this once.",
      "dl.title": "Light the pilot.", "dl.sub": "Two ways to install — same scheduler underneath.",
      "dl.gui.t": "Menu bar app", "dl.gui.d": "For most people. A GUI monitor + settings over the bundled engine.",
      "dl.gui.btn": "Download .dmg", "dl.gui.note": "Ad-hoc signed, not notarized — macOS asks you to approve it once on first launch.",
      "dl.gui.note_link": "See the first-launch steps ↓",
      "dl.cli.t": "CLI / launchd", "dl.cli.d": "For terminal users who want the lightest install and direct shell control.",
      "dl.cli.btn": "View install steps", "dl.outro": "Keep the fire lit.",
      "fl.title": "First launch on a new Mac",
      "fl.sub": "Stoker is open source and only ad-hoc signed (no paid Apple notarization), so macOS blocks it the first time. It runs entirely on your Mac and the full source is on GitHub. Approve it once:",
      "fl.s1.t": "Drag it to Applications", "fl.s1.d": "Open the DMG and drag Stoker.app onto the Applications folder. Launch it from there, not from the DMG.",
      "fl.s2.t": "Double-click, then click Done", "fl.s2.d": "macOS shows “Stoker” Not Opened — Apple could not verify… Click Done (on macOS 14: Cancel) — not Move to Trash.",
      "fl.s3.t": "macOS 15 Sequoia / 26 and later", "fl.s3.d": "Open System Settings › Privacy & Security, scroll to Security, and click Open Anyway next to “Stoker” was blocked… Confirm with Touch ID or your password, then click Open Anyway once more. The button only shows for about an hour — if it’s missing, double-click the app again.",
      "fl.s4.t": "macOS 14 Sonoma", "fl.s4.d": "Right-click (or Control-click) Stoker.app ▸ Open, then click Open in the dialog.",
      "fl.s5.t": "Still blocked, or “damaged”?", "fl.s5.d": "Run this in Terminal, then open the app again. It only removes the download quarantine flag from this one app.",
      "fl.foot": "Only needed once. Later launches open normally — after updating to a newer version, macOS may ask you to approve it once more.",
      "footer.tagline": "A quiet macOS utility that tends your AI usage windows.",
      "footer.col_product": "Product", "footer.col_resources": "Resources", "footer.col_legal": "Legal",
      "footer.link_features": "Features", "footer.link_download": "Download", "footer.link_changelog": "Changelog",
      "footer.link_readme": "Documentation", "footer.link_source": "Source code", "footer.link_issues": "Issues",
      "footer.link_license": "License (MIT)", "footer.link_disclaimer": "Disclaimer", "footer.link_security": "Security",
      "footer.disclaimer": "Not affiliated with Anthropic, OpenAI, or Apple. © 2026 hakupao."
    },
    zh: {
      "a11y.skip": "跳到内容",
      "meta.description": "一个极小的 macOS launchd 定时器:在你选定的时间发送低成本的 Claude Code 与 Codex「打卡」,并记录每次运行、token 与配额快照。完全在你的 Mac 本机运行。",
      "alt.activity": "Stoker 活动仪表盘——配额趋势与逐次运行记录",
      "alt.settings": "Stoker 设置——按工具分开的运行时间(Claude 与 Codex 各自的星期和时间点)、工具卡与高级选项",
      "nav.features": "功能", "nav.how": "工作原理", "nav.cost": "成本", "nav.faq": "常见问题", "nav.download": "下载",
      "hero.eyebrow": "让炉火长明。",
      "hero.title": "让 Claude Code 与 Codex 的用量窗口,一直续着火。",
      "hero.sub": "一个极小的 macOS launchd 定时器:在你选定的时间发送低成本「打卡」,并记录每次运行、token 与配额快照。完全在你的 Mac 本机运行。",
      "hero.cta_primary": "下载 macOS 版", "hero.cta_secondary": "在 GitHub 查看",
      "hero.meta": "v0.3.6 · macOS 14+ · 免费开源 (MIT)",
      "hero.schedule_label": "默认调度 · 按工具",
      "hero.schedule_sr": "Claude 与 Codex 的默认调度都是 07:00、12:00、17:00、22:00——每个工具可单独设定时间和星期。",
      "problem.title": "用量窗口按时钟重置,而不是按你的作息。",
      "problem.sub": "如果一个窗口的第一次提问来得晚,整个窗口就整体后移。Stoker 在固定时间发送极小的打卡,让窗口在你真正开始工作时已经就绪。",
      "problem.c1.t": "固定的起点", "problem.c1.d": "按你一周的作息选时间点和星期——Claude 与 Codex 分开设置,每个时间点相互独立触发。",
      "problem.c2.t": "看得见的配额", "problem.c2.d": "每次运行后记录 5 小时窗口与每周配额快照。",
      "problem.c3.t": "耗尽就跳过", "problem.c3.d": "配额预检会优雅跳过已耗尽的工具,而不是浪费一次调用。",
      "film.title": "40 秒看懂 Stoker。", "film.sub": "它做什么、调度怎么设、App 里能看到什么。", "film.aria": "Stoker 宣传视频",
      "how.title": "工作原理", "how.sub": "每一次运行都是同样从容的四拍循环。",
      "how.s1.t": "读取配置并加锁", "how.s1.d": "读取 .env,再获取锁——同一时刻触发的另一次运行会排队等待。",
      "how.s2.t": "配额预检", "how.s2.d": "发送前先查配额。已耗尽的工具被跳过并记录。",
      "how.s3.t": "发送极小 prompt", "how.s3.d": "给每个 CLI 一个极小的 check-in,只在自己的目录里——不跑工具,绝不碰你的真实项目。",
      "how.s4.t": "记录并释放", "how.s4.d": "追加 usage 与配额快照,然后释放锁,等待下次。",
      "feat.title": "小工具,却处处可查。",
      "feat.f1.t": "定时触发", "feat.f1.d": "通过 macOS launchd 触发 Claude Code 与 Codex——每个工具各自设定时间和星期。",
      "feat.f2.t": "极简安全 prompt", "feat.f2.d": "每次 check-in 都极小且只读,只在自己的目录里——绝不碰你的真实项目。",
      "feat.f3.t": "可读运行历史", "feat.f3.d": "每次激活以纯文本记录在 logs/activation.log。",
      "feat.f4.t": "单次用量记录", "feat.f4.d": "结构化的 token 与成本行写入 logs/usage.jsonl。",
      "feat.f5.t": "配额快照", "feat.f5.d": "5 小时窗口与每周配额状态写入 logs/status.jsonl。",
      "feat.f6.t": "配额预检", "feat.f6.d": "已知配额耗尽时优雅跳过激活。",
      "feat.f7.t": "可克隆配置", "feat.f7.d": "按工具的时间表、工具、prompt、超时与路径——全在一个 .env。",
      "cost.title": "对成本诚实。大约一次两厘半。",
      "cost.sub": "Stoker 发送真实 prompt,因此会消耗真实额度。下面是确切数字。",
      "cost.claude": "~1.6K input tokens · 每次约 $0.0025",
      "cost.codex": "每次约 38K input tokens(约 55% 为缓存读取)",
      "cost.month": "按每天 4 次,Claude 月成本约 $0.30。",
      "cost.note": "成本瓶颈是各 CLI 注入的系统 prompt——Stoker 自身 prompt 控制在 ~300 tokens 以内。",
      "shots.title": "让你随时查看,而非时时盯守。",
      "shots.sub": "同一引擎之上的原生菜单栏 App——双语,明暗随心。",
      "shots.tab_activity": "活动", "shots.tab_settings": "设置",
      "trust.b1": "独立 · 非官方", "trust.b2": "100% 本机 — 不向作者回传数据", "trust.b3": "开源 · MIT",
      "trust.note": "与 Anthropic、OpenAI、Apple 无隶属,未获认可或赞助。Stoker 消耗你的真实额度;遵守各家服务条款由你自行负责。",
      "faq.title": "常见问题,直说。",
      "faq.q1": "运行成本是多少?",
      "faq.a1": "每次 Claude 激活约 $0.0025(~1.6K tokens),每天四次约 $0.30/月。Codex 消耗你的套餐配额。",
      "faq.q2": "会消耗我的配额吗?",
      "faq.a2": "会——它发送真实 prompt,这正是它的作用。配额预检会在配额已耗尽时跳过该工具。",
      "faq.q3": "安全吗?会碰我的项目吗?",
      "faq.a3": "不会。它在自己的目录里运行,只做一次极小的只读 check-in,绝不读取或修改你的真实项目。dry-run 与 quota 不发送任何东西。",
      "faq.q4": "这是官方工具吗?",
      "faq.a4": "不是。Stoker 是独立开源项目,与 Anthropic、OpenAI、Apple 无隶属。遵守它们的条款由你负责。",
      "faq.q5": "如何卸载?",
      "faq.a5": "运行 ./install.sh uninstall(或用菜单栏 App)即可卸载并移除所有 LaunchAgent。",
      "faq.q6": "macOS 提示无法打开 Stoker,怎么办?",
      "faq.a6": "首次打开时这是正常的:App 开源、仅 ad-hoc 签名,未经 Apple 公证。先点「完成」,再打开 系统设置 › 隐私与安全性,点「仍要打开」(macOS 14 上右键点 App ▸ 打开)。如果提示 App 已损坏,在终端运行 xattr -dr com.apple.quarantine /Applications/Stoker.app。只需操作一次。",
      "dl.title": "点燃长明灯。", "dl.sub": "两种安装方式,底层是同一个定时器。",
      "dl.gui.t": "菜单栏 App", "dl.gui.d": "适合大多数人。图形化监控 + 设置,内置同一引擎。",
      "dl.gui.btn": "下载 .dmg", "dl.gui.note": "采用 ad-hoc 签名、未经公证——首次打开时 macOS 会要求你放行一次。",
      "dl.gui.note_link": "查看首次打开步骤 ↓",
      "dl.cli.t": "CLI / launchd", "dl.cli.d": "适合想要最轻量安装、直接用 shell 控制的终端用户。",
      "dl.cli.btn": "查看安装步骤", "dl.outro": "让炉火长明。",
      "fl.title": "在新 Mac 上首次打开",
      "fl.sub": "Stoker 开源、仅 ad-hoc 签名(没有付费的 Apple 公证),所以第一次打开会被 macOS 拦下。它完全在你的 Mac 本机运行,全部源码都在 GitHub。放行一次即可:",
      "fl.s1.t": "先拖进「应用程序」", "fl.s1.d": "打开 DMG,把 Stoker.app 拖到「应用程序」文件夹,之后从那里打开,不要在 DMG 里直接运行。",
      "fl.s2.t": "双击,然后点「完成」", "fl.s2.d": "macOS 会提示「未打开 “Stoker”」——Apple 无法验证……点「完成」(macOS 14 上点「取消」),不要点「移到废纸篓」。",
      "fl.s3.t": "macOS 15 Sequoia / 26 及更新", "fl.s3.d": "打开 系统设置 › 隐私与安全性,滚到「安全性」,在 “Stoker” 已被阻止的提示旁点「仍要打开」。用 Touch ID 或密码确认后,再点一次「仍要打开」。这个按钮只在约一小时内显示——找不到时再双击一次 App。",
      "fl.s4.t": "macOS 14 Sonoma", "fl.s4.d": "右键点按(或按住 Control 点按)Stoker.app ▸ 打开,再在对话框里点「打开」。",
      "fl.s5.t": "还是打不开,或提示「已损坏」?", "fl.s5.d": "在「终端」运行下面这行,然后再打开 App。它只去掉这一个 App 的下载隔离标记。",
      "fl.foot": "只需一次。以后正常打开即可——升级到新版本后,macOS 可能会要求你再放行一次。",
      "footer.tagline": "一个安静的 macOS 工具,替你守着 AI 用量窗口。",
      "footer.col_product": "产品", "footer.col_resources": "资源", "footer.col_legal": "法律",
      "footer.link_features": "功能", "footer.link_download": "下载", "footer.link_changelog": "更新日志",
      "footer.link_readme": "文档", "footer.link_source": "源代码", "footer.link_issues": "问题反馈",
      "footer.link_license": "许可证 (MIT)", "footer.link_disclaimer": "免责声明", "footer.link_security": "安全",
      "footer.disclaimer": "与 Anthropic、OpenAI、Apple 无隶属。© 2026 hakupao。"
    }
  };

  var nodes = document.querySelectorAll("[data-i18n]");
  var altNodes = document.querySelectorAll("[data-alt-i18n]");

  function setMeta(sel, value) {
    var el = document.querySelector(sel);
    if (el && value != null) el.setAttribute("content", value);
  }

  function applyLang(lang) {
    if (lang !== "zh") lang = "en";
    var dict = I18N[lang];
    html.setAttribute("lang", lang);
    try { localStorage.setItem("stoker-lang", lang); } catch (e) {}
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute("data-i18n");
      if (dict[key] != null) nodes[i].textContent = dict[key];
    }
    // Alt text follows language; the tab shot maps to its current shot type.
    for (var a = 0; a < altNodes.length; a++) {
      var ak = altNodes[a].getAttribute("data-shot") === "settings" ? "alt.settings" : "alt.activity";
      if (dict[ak] != null) altNodes[a].setAttribute("alt", dict[ak]);
    }
    // Bilingual site → bilingual docs: point the footer "Documentation" link at the
    // matching README (中文 README when in Chinese).
    var docLink = document.querySelector("[data-doc-link]");
    if (docLink) {
      docLink.setAttribute("href", lang === "zh"
        ? "https://github.com/hakupao/stoker/blob/main/README_CN.md"
        : "https://github.com/hakupao/stoker/blob/main/README.md");
    }
    document.title = lang === "zh"
      ? "Stoker — 让 Claude Code 与 Codex 的用量窗口长明"
      : "Stoker — Keep your Claude Code & Codex usage windows lit";
    if (dict["meta.description"] != null) {
      setMeta('meta[name="description"]', dict["meta.description"]);
      setMeta('meta[property="og:description"]', dict["meta.description"]);
      setMeta('meta[name="twitter:description"]', dict["meta.description"]);
    }
    updateShots();
    updateFilm(lang, dict);
  }

  // The promo film has one cut per language; swap it (and its poster) with the page language.
  function updateFilm(lang, dict) {
    var v = document.getElementById("promoVideo");
    if (!v) return;
    var src = "./assets/stoker-promo-" + lang + ".mp4";
    if (dict["film.aria"] != null) v.setAttribute("aria-label", dict["film.aria"]);
    if (v.getAttribute("src") === src) return;
    v.pause();
    v.setAttribute("poster", "./assets/stoker-promo-" + lang + ".jpg");
    v.setAttribute("src", src);
  }

  function currentLang() {
    var l = html.getAttribute("lang");
    return l === "zh" ? "zh" : "en";
  }
  function toggleLang() { applyLang(currentLang() === "zh" ? "en" : "zh"); }

  /* ---------------- Theme ---------------- */
  function systemDark() { return window.matchMedia("(prefers-color-scheme: dark)").matches; }
  function effectiveDark() {
    var t = html.getAttribute("data-theme");
    if (t === "dark") return true;
    if (t === "light") return false;
    return systemDark();
  }
  function applyTheme(theme) {
    if (theme === "light" || theme === "dark") {
      html.setAttribute("data-theme", theme);
      try { localStorage.setItem("stoker-theme", theme); } catch (e) {}
    }
    updateShots();
  }
  function toggleTheme() { applyTheme(effectiveDark() ? "light" : "dark"); }

  /* ---------------- Screenshots (lang × theme × tab) ---------------- */
  var heroShot = document.getElementById("heroShot");
  var tabShot = document.getElementById("tabShot");
  function shotSrc(name) {
    return "./images/" + name + "-" + currentLang() + (effectiveDark() ? "-dark" : "") + ".png";
  }
  function setShot(img) {
    if (!img) return;
    var name = img.getAttribute("data-shot") || "activity";
    var next = shotSrc(name);
    if (img.getAttribute("src") === next) return;
    // Cross-fade on any src swap (language / theme / tab), not just tab clicks.
    var win = img.closest(".window");
    if (win && !reduceMotion) {
      win.classList.add("is-swapping");
      setTimeout(function () { win.classList.remove("is-swapping"); }, 220);
    }
    img.setAttribute("src", next);
  }
  function updateShots() { setShot(heroShot); setShot(tabShot); }

  /* ---------------- Tabs ---------------- */
  var tabs = document.querySelectorAll(".tab");
  for (var t = 0; t < tabs.length; t++) {
    tabs[t].addEventListener("click", function () {
      for (var j = 0; j < tabs.length; j++) {
        tabs[j].classList.remove("is-active");
        tabs[j].setAttribute("aria-selected", "false");
      }
      this.classList.add("is-active");
      this.setAttribute("aria-selected", "true");
      var name = this.getAttribute("data-tab");
      if (tabShot) {
        // setShot() now handles the cross-fade on src change; also keep alt in sync.
        tabShot.setAttribute("data-shot", name);
        var dict = I18N[currentLang()];
        var ak = name === "settings" ? "alt.settings" : "alt.activity";
        if (dict && dict[ak] != null) tabShot.setAttribute("alt", dict[ak]);
        setShot(tabShot);
      }
    });
  }

  /* ---------------- Wire toggles ---------------- */
  function bind(id, fn) { var el = document.getElementById(id); if (el) el.addEventListener("click", fn); }
  bind("langToggle", toggleLang);
  bind("langToggleFoot", toggleLang);
  bind("themeToggle", toggleTheme);

  // React to system theme changes when in auto mode.
  try {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
      if (!html.getAttribute("data-theme")) updateShots();
    });
  } catch (e) {}

  // Initial paint (respect bootstrap-set lang).
  applyLang(currentLang());

  /* ---------------- Nav scrolled state ---------------- */
  var nav = document.getElementById("nav");
  function onScroll() { if (nav) nav.classList.toggle("scrolled", window.scrollY > 36); }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ---------------- Reveal on scroll ---------------- */
  var reveals = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    for (var r = 0; r < reveals.length; r++) reveals[r].classList.add("is-in");
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("is-in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.15, rootMargin: "0px 0px -10% 0px" });
    for (var k = 0; k < reveals.length; k++) io.observe(reveals[k]);
  }

  /* ---------------- Magnetic primary buttons ---------------- */
  if (canHover && !reduceMotion) {
    var mags = document.querySelectorAll(".magnetic");
    mags.forEach(function (el) {
      el.addEventListener("pointermove", function (e) {
        var rect = el.getBoundingClientRect();
        var dx = (e.clientX - (rect.left + rect.width / 2)) * 0.2;
        var dy = (e.clientY - (rect.top + rect.height / 2)) * 0.2;
        dx = Math.max(-8, Math.min(8, dx)); dy = Math.max(-8, Math.min(8, dy));
        el.style.transform = "translate(" + dx + "px," + dy + "px)";
      });
      el.addEventListener("pointerleave", function () { el.style.transform = ""; });
    });

    /* ---------------- Bento cursor glow ---------------- */
    var cells = document.querySelectorAll(".bento__cell");
    cells.forEach(function (cell) {
      cell.addEventListener("pointermove", function (e) {
        var rect = cell.getBoundingClientRect();
        cell.style.setProperty("--mx", (e.clientX - rect.left) + "px");
        cell.style.setProperty("--my", (e.clientY - rect.top) + "px");
      });
    });
  }

  /* ---------------- Hero ember sparks ---------------- */
  var canvas = document.getElementById("sparks");
  if (canvas && !reduceMotion) {
    var ctx = canvas.getContext("2d");
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0, parts = [], raf = null, running = true;
    var COUNT = 36;

    function resize() {
      var box = canvas.getBoundingClientRect();
      W = box.width; H = box.height;
      canvas.width = Math.floor(W * dpr); canvas.height = Math.floor(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    function mk(initial) {
      return {
        x: Math.random() * W,
        y: initial ? Math.random() * H : H + Math.random() * 30,
        r: 0.6 + Math.random() * 1.3,
        vy: -(0.2 + Math.random() * 0.45),
        vx: (Math.random() - 0.5) * 0.18,
        a: 0.25 + Math.random() * 0.5,
        hot: Math.random() > 0.6
      };
    }
    function seed() { parts = []; for (var i = 0; i < COUNT; i++) parts.push(mk(true)); }
    function frame() {
      if (!running) return;
      ctx.clearRect(0, 0, W, H);
      for (var i = 0; i < parts.length; i++) {
        var p = parts[i];
        p.y += p.vy; p.x += p.vx; p.a -= 0.0016;
        if (p.y < -10 || p.a <= 0) parts[i] = mk(false);
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, 6.2832);
        ctx.fillStyle = (p.hot ? "rgba(255,179,71," : "rgba(227,110,67,") + Math.max(0, p.a).toFixed(3) + ")";
        ctx.shadowBlur = 6; ctx.shadowColor = "rgba(227,110,67,0.5)";
        ctx.fill();
      }
      ctx.shadowBlur = 0;
      raf = requestAnimationFrame(frame);
    }
    function start() { if (!raf) { running = true; raf = requestAnimationFrame(frame); } }
    function stop() { running = false; if (raf) { cancelAnimationFrame(raf); raf = null; } }

    resize(); seed(); start();
    window.addEventListener("resize", function () { resize(); seed(); });

    var hero = document.getElementById("hero");
    if (hero && "IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        if (entries[0].isIntersecting) start(); else stop();
      }, { threshold: 0.01 }).observe(hero);
    }
    document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else start(); });
  }
})();
