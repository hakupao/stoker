# Stoker promo film

A 40-second silent product film (1920×1080, 30 fps) built as an HTML/CSS/JS page and rendered
frame-by-frame with headless Chrome. It reuses the real app screenshots in `docs/images/` and the
app icon in `docs/assets/app-icon/`; nothing is fetched from the network.

```sh
cd promo && npm ci && node render.mjs   # → docs/assets/stoker-promo-{en,zh}.{mp4,jpg}
```

- `index.html` + `promo.css` + `promo.js` — the film. `window.renderAt(t)` sets every visual from
  `t` alone (no CSS transitions, no clocks), so each frame is exact and reproducible.
  Open it in a browser with `?lang=en|zh` plus `?autoplay=1` (live preview) or `?t=12.5` (freeze).
- `render.mjs` — captures each frame with `puppeteer-core` + Google Chrome, pipes PNGs into a
  lossless master (`promo/out/master-<lang>.mkv`), then encodes the web MP4 (H.264, yuv420p,
  `+faststart`, no audio) and a 1280-wide JPEG poster.
  Options: `--lang en|zh` (one language), `--stills 2,8,15` (PNG stills only, for checking layout).
  Env: `CHROME`, `FFMPEG`, `CRF` (default 24), `POSTER_T` (default 39 s).
- Needs Google Chrome at `/Applications/Google Chrome.app` (or `CHROME=`) and `ffmpeg`
  (`/opt/homebrew/bin/ffmpeg` or `FFMPEG=`). A full render of both languages takes roughly 10–15 minutes.

Copy rules: the numbers on screen (≈ $0.0025 per Claude activation, ≈ $0.30/month at 4/day) come
from the landing page / README cost section (measured averages; see CHANGELOG Unreleased › Docs).
Render on macOS: the film uses the system font stack (SF Pro / PingFang SC / SF Mono). The film adds no version text of its own (only what the screenshots show), so it is not a version-bump site.
Strings live in the `STR` table at the top of `promo.js`.
