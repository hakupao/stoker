/* Stoker promo film — deterministic timeline.
 * window.renderAt(t) sets every visual property from t (seconds) alone:
 * no CSS transitions, no clocks, so headless capture is frame-exact.
 * Query params: ?lang=en|zh  ?t=12.5 (freeze a frame)  ?autoplay=1 (live preview)
 */
(function () {
  "use strict";
  var DURATION = 40;
  var params = new URLSearchParams(location.search);
  var LANG = params.get("lang") === "zh" ? "zh" : "en";

  var STR = {
    en: {
      tagline: "Keep your Claude Code & Codex usage windows lit.",
      eyebrow: "Keep the fire lit.",
      "s2.eyebrow": "The problem",
      "s2.title": "Usage windows reset on a clock — not on your schedule.",
      "s2.sub": "If the first prompt of a window lands late, the whole window shifts late.",
      "s2.rowA": "Without Stoker — the window opens at your first prompt",
      "s2.rowB": "With Stoker — anchored at the time you chose",
      "s2.markA": "first prompt · 09:40",
      "s2.shift": "Whole window shifts 2 h 40 min late",
      "s3.eyebrow": "Your schedule",
      "s3.title": "Tiny check-ins, at the times you choose.",
      "s3.sub": "Low-cost by design — and each tool now has its own schedule.",
      "s3.codexnote": "Anchors the 7-day window — skips while it's already running.",
      everyday: "Every day",
      "s4.eyebrow": "Activity",
      "s4.b1.t": "Live quota, at a glance.",
      "s4.b1.d": "Claude 5-hour and weekly. Codex weekly. Read straight from your Mac.",
      "s4.b2.t": "Health you can trust.",
      "s4.b2.d": "Each tool shows whether it's activating normally — and when it runs next.",
      "s4.b3.t": "Exhausted? Skipped.",
      "s4.b3.d": "Quota preflight skips a tool whose quota is exhausted instead of wasting a call.",
      "s4.b4.t": "About a quarter of a cent.",
      "s4.b4.unit": "per Claude activation",
      "s4.b4.d": "≈ $0.30 / month at four activations a day.",
      "s5.eyebrow": "Native menu bar app",
      "s5.title": "Light or dark.\nEnglish or 中文.",
      "s5.c1": "100% local", "s5.c2": "Open source · MIT", "s5.c3": "macOS 14+",
      cta: "Download for macOS",
      free: "Free & open source",
      disc: "Independent project · not affiliated with Anthropic or OpenAI",
      modes: [["Light", "EN"], ["Dark", "EN"], ["Dark", "中文"], ["Light", "中文"]]
    },
    zh: {
      tagline: "让 Claude Code 与 Codex 的用量窗口始终点亮。",
      eyebrow: "让炉火长明。",
      "s2.eyebrow": "问题所在",
      "s2.title": "用量窗口按时钟重置，而不是按你的节奏。",
      "s2.sub": "窗口里的第一条消息来得晚，整个窗口就跟着往后推。",
      "s2.rowA": "没有 Stoker：窗口从你的第一条消息开始计时",
      "s2.rowB": "有 Stoker：锚定在你选定的时间",
      "s2.markA": "第一条消息 · 09:40",
      "s2.shift": "整个窗口推迟了 2 小时 40 分",
      "s3.eyebrow": "你的时间表",
      "s3.title": "在你选定的时间，发一条极小的打卡。",
      "s3.sub": "成本极低。现在每个工具都有各自独立的时间表。",
      "s3.codexnote": "锚定 7 天窗口；窗口已在计时则自动跳过。",
      everyday: "每天",
      "s4.eyebrow": "活动",
      "s4.b1.t": "实时额度，一眼看清。",
      "s4.b1.d": "Claude 5 小时与每周额度、Codex 每周额度，\n全部在你的 Mac 本机读取。",
      "s4.b2.t": "状态，一目了然。",
      "s4.b2.d": "每个工具都会显示是否正常激活，\n以及下一次运行的时间。",
      "s4.b3.t": "额度耗尽，自动跳过。",
      "s4.b3.d": "配额预检：额度已耗尽的工具会被自动跳过，\n不浪费一次调用。",
      "s4.b4.t": "每次不到一美分。",
      "s4.b4.unit": "每次 Claude 激活",
      "s4.b4.d": "每天 4 次，每月约 $0.30。",
      "s5.eyebrow": "原生菜单栏应用",
      "s5.title": "浅色或深色，\nEnglish 或中文。",
      "s5.c1": "100% 本机运行", "s5.c2": "开源 · MIT", "s5.c3": "macOS 14+",
      cta: "下载 macOS 版",
      free: "免费开源",
      disc: "独立项目 · 与 Anthropic、OpenAI 无关联",
      modes: [["浅色", "中文"], ["深色", "中文"], ["深色", "EN"], ["浅色", "EN"]]
    }
  };
  var S = STR[LANG];
  document.documentElement.lang = LANG === "zh" ? "zh-CN" : "en";

  var IMG = "../docs/images/";
  var other = LANG === "zh" ? "en" : "zh";
  var SRC = {
    s3Img: IMG + "settings-" + LANG + ".png",
    s4Img: IMG + "activity-" + LANG + ".png",
    s5i0: IMG + "activity-" + LANG + ".png",
    s5i1: IMG + "activity-" + LANG + "-dark.png",
    s5i2: IMG + "activity-" + other + "-dark.png",
    s5i3: IMG + "activity-" + other + ".png"
  };

  var $ = function (id) { return document.getElementById(id); };
  document.querySelectorAll("[data-k]").forEach(function (el) {
    var v = S[el.getAttribute("data-k")];
    if (typeof v === "string") el.textContent = v;
  });
  Object.keys(SRC).forEach(function (id) { $(id).src = SRC[id]; });

  // Axis 06:00 → 18:00, 120 px per hour on a 1440 px track.
  var PX_H = 120, H0 = 6;
  var hx = function (h) { return (h - H0) * PX_H; };
  (function buildAxis() {
    var axis = $("s2Axis"), html = "";
    for (var h = 6; h <= 18; h++) {
      html += '<div class="tick" style="left:' + hx(h) + 'px"></div>';
      if (h % 3 === 0) html += '<div class="tlbl" style="left:' + hx(h) + 'px">' + (h < 10 ? "0" : "") + h + ":00</div>";
    }
    axis.innerHTML = html;
  })();

  // ---------- math ----------
  var clamp = function (x, a, b) { return Math.min(b, Math.max(a, x)); };
  var lerp = function (a, b, p) { return a + (b - a) * p; };
  var prog = function (t, a, b) { return clamp((t - a) / (b - a), 0, 1); };
  var eOut = function (p) { return 1 - Math.pow(1 - p, 3); };
  var eInOut = function (p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; };
  var eOutBack = function (p) { var c = 1.4; return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); };
  // in over [a,b], out over [c,d]
  var env = function (t, a, b, c, d) { return eInOut(prog(t, a, b)) * (1 - eInOut(prog(t, c, d))); };
  var mix = function (c1, c2, p) {
    return "rgb(" + [0, 1, 2].map(function (i) { return Math.round(lerp(c1[i], c2[i], p)); }).join(",") + ")";
  };
  var set = function (el, o, tf) {
    el.style.opacity = o.toFixed(4);
    if (tf !== undefined) el.style.transform = tf;
  };
  // Fade + rise for a text element entering at time a.
  var rise = function (el, t, a, dur, outA, outB, dist) {
    var p = eOut(prog(t, a, a + (dur || 0.8)));
    var o = p * (outA === undefined ? 1 : 1 - eInOut(prog(t, outA, outB)));
    set(el, o, "translateY(" + ((1 - p) * (dist || 26)).toFixed(2) + "px)");
  };
  var fmt = function (mins) {
    mins = Math.round(mins);
    var h = Math.floor(mins / 60) % 24, m = mins % 60;
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
  };
  var spot = function (el, r, o) {
    el.style.left = r[0].toFixed(1) + "px"; el.style.top = r[1].toFixed(1) + "px";
    el.style.width = r[2].toFixed(1) + "px"; el.style.height = r[3].toFixed(1) + "px";
    el.style.opacity = o.toFixed(4);
  };
  var lerpRect = function (a, b, p) { return a.map(function (v, i) { return lerp(v, b[i], p); }); };

  // Scene windows [start, end]; neighbours overlap by 0.2 s for dissolves.
  var SC = { s1: [0, 4.6], s2: [4.4, 10.8], s3: [10.6, 18.8], s4: [18.6, 28.8], s5: [28.6, 34.8], s6: [34.6, DURATION + 1] };
  var sceneOpacity = function (k, t) {
    var a = SC[k][0], b = SC[k][1];
    var inP = a === 0 ? 1 : eInOut(prog(t, a, a + 0.6));
    var outP = eInOut(prog(t, b - 0.6, b));
    return inP * (1 - outP);
  };

  // Spotlight rects in screenshot pixel space (760×720).
  var R_SCHED = [12, 179, 721, 287];
  var R_CARDS = [12, 177, 735, 210];
  var R_HEALTH = [20, 337, 727, 40];
  var R_RUNS = [8, 521, 744, 140];

  var COLD = [11, 14, 20], WARM = [18, 13, 10];

  function renderAt(t) {
    t = clamp(t, 0, DURATION);

    // ---- heat: cold stage → lit fire ----
    var heat = eInOut(prog(t, 0.6, 2.8));
    var s2l = t - SC.s2[0];
    if (t > SC.s2[0] && t < SC.s3[0] + 1) heat *= lerp(1, 0.45, eInOut(prog(s2l, 0.2, 1.4))) + (1 - lerp(1, 0.45, eInOut(prog(s2l, 0.2, 1.4)))) * eInOut(prog(s2l, 3.3, 4.6));
    var endBoost = eInOut(prog(t, SC.s6[0] + 0.2, SC.s6[0] + 2.2));
    $("bg").style.background = "radial-gradient(ellipse 120% 100% at 50% 40%, " + mix(COLD, [30, 20, 15], heat) + ", " + mix(COLD, WARM, heat) + " 70%)";
    $("glowCold").style.opacity = (0.9 * (1 - heat)).toFixed(4);
    var breathe = 0.06 * Math.sin(t * 1.3);
    $("glowWarm").style.opacity = clamp(heat * (0.55 + breathe) + endBoost * 0.35, 0, 1).toFixed(4);

    // ---- S1: ignition ----
    var o1 = sceneOpacity("s1", t);
    $("s1").style.opacity = o1.toFixed(4);
    if (o1 > 0) {
      var ip = eOut(prog(t, 0.1, 1.2));
      var icon = $("s1Icon");
      icon.style.opacity = ip.toFixed(4);
      var ig = eInOut(prog(t, 0.7, 2.4));
      icon.style.filter = "grayscale(" + (0.85 * (1 - ig)).toFixed(3) + ") brightness(" + lerp(0.62, 1, ig).toFixed(3) + ")";
      icon.style.transform = "scale(" + (lerp(0.9, 1, ip) + 0.01 * Math.sin(t * 1.6) * ig).toFixed(4) + ")";
      set($("s1Halo"), ig * (0.85 + 0.15 * Math.sin(t * 2.1)), "scale(" + lerp(0.6, 1, ig).toFixed(3) + ")");
      rise($("s1Title"), t, 1.2, 0.9);
      rise($("s1Tag"), t, 1.8, 0.9);
      rise($("s1Eyebrow"), t, 2.4, 0.8);
      var drift = -8 * prog(t, 3.6, 4.6);
      $("s1").style.transform = "translateY(" + drift.toFixed(2) + "px)";
    }

    // ---- S2: problem ----
    var o2 = sceneOpacity("s2", t);
    $("s2").style.opacity = o2.toFixed(4);
    if (o2 > 0) {
      var l = s2l;
      rise($("s2Eyebrow"), l, 0.2, 0.7);
      rise($("s2Title"), l, 0.3, 0.8);
      rise($("s2Sub"), l, 0.7, 0.8);
      rise($("s2Chart"), l, 1.0, 0.8, undefined, undefined, 30);
      // Row A: window that drifts late with the first prompt.
      var aIn = eOut(prog(l, 1.4, 1.9));
      var slide = eInOut(prog(l, 2.0, 3.3));
      var startH = lerp(7, 9 + 40 / 60, slide);
      var barA = $("barA");
      barA.style.left = hx(startH).toFixed(1) + "px";
      barA.style.width = (5 * PX_H) + "px";
      barA.style.opacity = aIn.toFixed(4);
      $("barALbl").textContent = fmt(startH * 60) + " → " + fmt((startH + 5) * 60);
      var markA = $("markA");
      markA.style.left = hx(9 + 40 / 60) + "px";
      set(markA, eOut(prog(l, 1.9, 2.4)), "translateX(-50%) translateY(" + ((1 - eOut(prog(l, 1.9, 2.4))) * -14).toFixed(2) + "px)");
      var shiftA = $("shiftA");
      shiftA.style.left = hx(9 + 40 / 60) + "px";
      set(shiftA, eOut(prog(l, 3.2, 3.7)));
      // Row B: anchored at 07:00, lit by a spark.
      var mB = eOut(prog(l, 3.3, 3.7));
      var markB = $("markB");
      markB.style.left = hx(7) + "px";
      set(markB, mB, "translateX(-50%) translateY(" + ((1 - mB) * -14).toFixed(2) + "px)");
      var sp = prog(l, 3.45, 4.5);
      var sparkB = $("sparkB");
      sparkB.style.left = hx(7) + "px";
      set(sparkB, Math.sin(sp * Math.PI) * 0.95, "scale(" + lerp(0.3, 1.6, eOut(sp)).toFixed(3) + ")");
      var gB = eOut(prog(l, 3.55, 4.4));
      var barB = $("barB");
      barB.style.left = hx(7) + "px";
      barB.style.width = (5 * PX_H * gB).toFixed(1) + "px";
      barB.style.opacity = (gB > 0 ? 1 : 0).toString();
      var gB2 = eOut(prog(l, 4.3, 5.0));
      var barB2 = $("barB2");
      barB2.style.left = hx(12) + "px";
      barB2.style.width = (5 * PX_H * gB2).toFixed(1) + "px";
      barB2.style.opacity = (gB2 > 0 ? 1 : 0).toString();
    }

    // ---- S3: schedule ----
    var o3 = sceneOpacity("s3", t);
    $("s3").style.opacity = o3.toFixed(4);
    if (o3 > 0) {
      var l3 = t - SC.s3[0];
      var tx = $("s3Text").children;
      rise(tx[0], l3, 0.3, 0.7); rise(tx[1], l3, 0.4, 0.8); rise(tx[2], l3, 0.8, 0.8);
      rise($("s3c1"), l3, 2.2, 0.8); rise($("s3c2"), l3, 2.8, 0.8);
      var sIn = eOut(prog(l3, 0.2, 1.4));
      var sc = lerp(1.14, 1.2, eInOut(prog(l3, 0.2, 8.2)));
      set($("s3Shot"), sIn, "translateX(" + ((1 - sIn) * 80).toFixed(2) + "px) scale(" + sc.toFixed(4) + ")");
      var spIn = eInOut(prog(l3, 1.8, 2.5)) * (1 - eInOut(prog(l3, 7.0, 7.6)));
      var grow = eOut(prog(l3, 1.8, 2.6));
      var r = R_SCHED, pad = (1 - grow) * 18;
      spot($("s3Spot"), [r[0] - pad, r[1] - pad, r[2] + 2 * pad, r[3] + 2 * pad], spIn);
    }

    // ---- S4: activity ----
    var o4 = sceneOpacity("s4", t);
    $("s4").style.opacity = o4.toFixed(4);
    if (o4 > 0) {
      var l4 = t - SC.s4[0];
      var aIn4 = eOut(prog(l4, 0.2, 1.4));
      var sc4 = lerp(1.14, 1.2, eInOut(prog(l4, 0.2, 10)));
      set($("s4Shot"), aIn4, "translateX(" + ((aIn4 - 1) * 80).toFixed(2) + "px) scale(" + sc4.toFixed(4) + ")");
      rise($("s4Text").children[0], l4, 0.4, 0.7);
      var B = [[0.6, 3.3], [3.3, 5.6], [5.6, 8.0], [8.0, 11]];
      ["b1", "b2", "b3", "b4"].forEach(function (id, i) {
        var a = B[i][0], b = B[i][1];
        var inP = eOut(prog(l4, a, a + 0.6));
        var outP = i === 3 ? 0 : eInOut(prog(l4, b - 0.3, b + 0.05));
        set($(id), inP * (1 - outP), "translateY(" + ((1 - inP) * 22 - outP * 10).toFixed(2) + "px)");
      });
      // Spotlight travels cards → health → runs, then lifts for the cost beat.
      var rect = R_CARDS;
      var m1 = eInOut(prog(l4, 3.1, 3.6)), m2 = eInOut(prog(l4, 5.4, 5.9));
      rect = lerpRect(lerpRect(R_CARDS, R_HEALTH, m1), R_RUNS, m2);
      var so = eInOut(prog(l4, 0.9, 1.5)) * (1 - eInOut(prog(l4, 7.8, 8.3)));
      spot($("s4Spot"), rect, so);
    }

    // ---- S5: light/dark + EN/中 ----
    var o5 = sceneOpacity("s5", t);
    $("s5").style.opacity = o5.toFixed(4);
    if (o5 > 0) {
      var l5 = t - SC.s5[0];
      var tx5 = $("s5Text").children;
      rise(tx5[0], l5, 0.3, 0.7); rise(tx5[1], l5, 0.4, 0.8);
      ["chip1", "chip2", "chip3"].forEach(function (id, i) { rise($(id), l5, 1.4 + i * 0.25, 0.6, undefined, undefined, 14); });
      rise(tx5[3], l5, 1.0, 0.6);
      var sIn5 = eOut(prog(l5, 0.1, 1.2));
      set($("s5Shot"), sIn5, "translateY(" + ((1 - sIn5) * 40).toFixed(2) + "px) scale(" + lerp(1.15, 1.2, eInOut(prog(l5, 0, 6.2))).toFixed(4) + ")");
      var X = [null, [1.5, 2.1], [2.9, 3.5], [4.3, 4.9]];
      var active = 0;
      for (var i = 1; i <= 3; i++) {
        var p5 = eInOut(prog(l5, X[i][0], X[i][1]));
        $("s5i" + i).style.opacity = p5.toFixed(4);
        if (p5 >= 0.5) active = i;
      }
      var md = S.modes[active];
      var modeHtml = md[0] + "  ·  " + md[1];
      var modeEl = $("s5Mode");
      if (modeEl.getAttribute("data-m") !== modeHtml) {
        modeEl.innerHTML = "<b>" + md[0] + "</b>  ·  <b>" + md[1] + "</b>";
        modeEl.setAttribute("data-m", modeHtml);
      }
    }

    // ---- S6: end card ----
    var o6 = sceneOpacity("s6", t);
    $("s6").style.opacity = o6.toFixed(4);
    if (o6 > 0) {
      var l6 = t - SC.s6[0];
      var ip6 = eOut(prog(l6, 0.2, 1.2));
      set($("s6Icon"), ip6, "scale(" + lerp(0.88, 1, eOutBack(prog(l6, 0.2, 1.3))).toFixed(4) + ")");
      set($("s6Halo"), eInOut(prog(l6, 0.4, 1.8)) * (0.85 + 0.15 * Math.sin(t * 2.1)));
      rise($("s6Title"), l6, 0.6, 0.8);
      rise($("s6Eyebrow"), l6, 1.0, 0.8);
      rise($("s6Cta"), l6, 1.5, 0.8);
      rise($("s6Links"), l6, 1.9, 0.8);
      rise($("s6Free"), l6, 2.2, 0.8);
      rise($("s6Disc"), l6, 2.6, 0.8);
    }
  }

  window.DURATION = DURATION;
  window.renderAt = renderAt;
  window.promoReady = Promise.all([
    document.fonts.ready,
    Promise.all(Array.prototype.map.call(document.images, function (img) {
      return img.decode().catch(function () { throw new Error("image failed: " + img.src); });
    }))
  ]).then(function () { renderAt(0); return true; });

  var tq = params.get("t");
  if (tq !== null) { window.promoReady.then(function () { renderAt(parseFloat(tq) || 0); }); }
  else if (params.get("autoplay") === "1") {
    window.promoReady.then(function () {
      var t0 = null;
      (function loop(ts) { if (t0 === null) t0 = ts; renderAt(((ts - t0) / 1000) % DURATION); requestAnimationFrame(loop); })(performance.now());
    });
  } else { window.promoReady.then(function () { renderAt(0); }); }
})();
