#!/usr/bin/env node
// Render the Stoker promo film frame-by-frame with headless Chrome → ffmpeg.
//
//   node promo/render.mjs                 # both languages → docs/assets/stoker-promo-{en,zh}.{mp4,jpg}
//   node promo/render.mjs --lang zh       # one language
//   node promo/render.mjs --stills 2,8,15 # PNG stills only (promo/out/still-<lang>-<t>.png), no video
//
// Env: CHROME=/path/to/chrome  FFMPEG=/path/to/ffmpeg  CRF=24  FPS=30  POSTER_T=39
import { spawn } from "node:child_process";
import { mkdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import puppeteer from "puppeteer-core";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const OUT = join(HERE, "out");
const ASSETS = join(ROOT, "docs", "assets");
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FFMPEG = process.env.FFMPEG || "/opt/homebrew/bin/ffmpeg";
const FPS = Number(process.env.FPS || 30);
const CRF = String(process.env.CRF || 24);
const POSTER_T = Number(process.env.POSTER_T || 39);

const argv = process.argv.slice(2);
const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
const langs = opt("--lang") ? [opt("--lang")] : ["en", "zh"];
for (const l of langs) if (!["en", "zh"].includes(l)) { console.error(`--lang must be en or zh, got: ${l}`); process.exit(2); }
const stills = opt("--stills") ? opt("--stills").split(",").map(Number) : null;

mkdirSync(OUT, { recursive: true });
mkdirSync(ASSETS, { recursive: true });

function run(cmd, args, { stdin } = {}) {
  return new Promise((ok, fail) => {
    const p = spawn(cmd, args, { stdio: [stdin ? "pipe" : "ignore", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => { err += d; if (err.length > 20000) err = err.slice(-20000); });
    p.on("error", fail);
    p.on("close", (code) => (code === 0 ? ok() : fail(new Error(`${cmd} exited ${code}\n${err.slice(-3000)}`))));
    if (stdin) stdin(p);
  });
}

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  args: ["--hide-scrollbars", "--force-device-scale-factor=1", "--allow-file-access-from-files", "--font-render-hinting=none"],
  defaultViewport: { width: 1920, height: 1080, deviceScaleFactor: 1 },
});

try {
  for (const lang of langs) {
    const page = await browser.newPage();
    let pageError = null;
    page.on("pageerror", (e) => { pageError ??= e; });
    const url = pathToFileURL(join(HERE, "index.html")).href + `?lang=${lang}&t=0`;
    await page.goto(url, { waitUntil: "load" });
    await page.evaluate(() => window.promoReady);
    const duration = await page.evaluate(() => window.DURATION);

    const frame = async (t) => {
      if (pageError) throw pageError;
      await page.evaluate((tt) => new Promise((r) => { window.renderAt(tt); requestAnimationFrame(() => requestAnimationFrame(r)); }), t);
      return page.screenshot({ type: "png", clip: { x: 0, y: 0, width: 1920, height: 1080 } });
    };

    if (stills) {
      for (const t of stills) {
        writeFileSync(join(OUT, `still-${lang}-${t}.png`), await frame(t));
      }
      console.log(`[${lang}] wrote ${stills.length} stills to ${OUT}`);
      await page.close();
      continue;
    }

    // 1) Lossless intermediate so CRF can be tuned without re-rendering.
    const master = join(OUT, `master-${lang}.mkv`);
    const total = Math.round(duration * FPS);
    const started = Date.now();
    await run(FFMPEG, ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
      "-c:v", "libx264", "-qp", "0", "-preset", "ultrafast", "-pix_fmt", "yuv444p", master], {
      stdin: async (p) => {
        for (let i = 0; i < total; i++) {
          const buf = await frame(i / FPS);
          if (!p.stdin.write(buf)) await new Promise((r) => p.stdin.once("drain", r));
          if (i % 150 === 0) process.stdout.write(`[${lang}] frame ${i}/${total} (${((Date.now() - started) / 1000).toFixed(0)}s)\n`);
        }
        p.stdin.end();
      },
    });
    await page.close();

    // 2) Web deliverable: H.264 / yuv420p / faststart / silent.
    const mp4 = join(ASSETS, `stoker-promo-${lang}.mp4`);
    await run(FFMPEG, ["-y", "-loglevel", "error", "-i", master, "-an",
      "-c:v", "libx264", "-preset", "slow", "-crf", CRF, "-tune", "stillimage", "-profile:v", "high", "-level", "4.1",
      "-pix_fmt", "yuv420p", "-r", String(FPS), "-movflags", "+faststart", mp4]);

    // 3) Poster frame from the lossless master.
    const jpg = join(ASSETS, `stoker-promo-${lang}.jpg`);
    await run(FFMPEG, ["-y", "-loglevel", "error", "-ss", String(POSTER_T), "-i", master, "-frames:v", "1",
      "-vf", "scale=1280:-2:flags=lanczos", "-q:v", "4", jpg]);

    const mb = (f) => (statSync(f).size / 1048576).toFixed(2);
    console.log(`[${lang}] ${mp4} ${mb(mp4)} MB · ${jpg} ${(statSync(jpg).size / 1024).toFixed(0)} KB`);
  }
} finally {
  await browser.close();
}
