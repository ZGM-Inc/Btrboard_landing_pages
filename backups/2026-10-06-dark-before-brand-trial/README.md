# BTRboard — ABM landing pages

One template, one row per builder, ~40 static pages. No framework, no npm, no build toolchain
beyond Python 3 (which ships with macOS).

## Build

```bash
python3 build.py
```

Reads `template.html` + `data/builders.csv`, writes `dist/<slug>/index.html` for every row and
copies shared assets to `dist/assets/`. `dist/` is disposable — it is rebuilt from scratch each run.

## Preview

```bash
python3 -m http.server 8788 --directory dist
```

Then open <http://localhost:8788/riverstone-homes/>.

## Adding builders

Append rows to `data/builders.csv` and rebuild:

```csv
slug,first_name,company,province
riverstone-homes,Michael,Riverstone Homes,Ontario
```

`slug` becomes the URL segment, so it is what the printed QR code encodes. **Slugs must be final
before the direct mail goes to print.**

## Images

`assets/img/*.png` are the source images and are *not* shipped. The AVIF/WebP variants in
`assets/img/opt/` are. After replacing or adding a source PNG:

```bash
python3 tools/optimize_images.py
```

Adjust the `JOBS` dict in that file to change which widths get generated.

## Typeface

The design specifies **Proxima Nova**, which is commercial and not yet licensed for web use.
Self-hosted **Figtree** stands in. The CSS font stack already reads:

```css
"proxima-nova", "Proxima Nova", "Figtree", "Montserrat", -apple-system, …
```

so adding an Adobe Fonts embed (or a licensed `@font-face`) is the only change needed — nothing
else in the stylesheet has to move.

## Responsive behaviour

The original layout was verified from 390px to 3840px; the revised hero needs fresh visual
checks across that range before production.

- `--maxw` steps up on very wide screens (1400 -> 1560 at 1800px -> 1720 at 2400px) so the
  column doesn't strand itself in a field of black.
- The hero scrim's gradient stops are anchored to the **content column** via `--colx` / `--col`,
  not to the viewport, so the falloff sits in the same place relative to the text at every width.
- Below 760px the hero wash turns vertical and the frame pans (`object-position:35%`) to keep the
  windows and BTRboard in shot behind the type.
- The showcase photo is capped to the column width. It's invisible where it ends because both the
  photograph's background and the page ground are pure `#000`.

**Current hero:** `assets/img/hero-interior-sunset.png` is a 1670 × 942 sunset lighting edit of
[BTRboard's installed-interior photograph](https://www.btrboard.com/wp-content/uploads/2025/07/btr-facer-1536x866.webp).
The original is saved as `assets/img/btr-interior-original.webp`. The built-in imagegen prompt
is saved in `tools/hero-interior-sunset.prompt.txt`. The earlier exterior concepts are retained
for comparison. AVIF/WebP still variants are generated at 700, 980, 1376, and 1600px.

The hero uses `assets/video/hero-interior-sunset.mp4`: a silent 12-second, 1600 × 900 H.264
animated-photo loop. A 2.5% push-in gently returns to its starting frame; small feathered tree
patches move inside the windows. Interior geometry and printed boards are not independently
animated. This is a constructed cinemagraph, not recorded jobsite footage.

`assets/js/hero-video.js` keeps the still visible until playback starts, exposes a pause/play
control, and pauses the video when the hero is offscreen or the tab is hidden. Reduced-motion,
Save-Data, and reported 2G connections use the still without loading the MP4. If autoplay is
blocked, a Play control appears over the still; media errors keep the still visible.

To regenerate the video on an Apple Silicon Mac with Xcode Command Line Tools, follow the
compile/render commands at the top of `tools/render_hero_video.swift`. Choose a new output name
when rerendering; the script protects existing files. Normal `python3 build.py` runs simply copy
the existing video and require no Swift tooling.

Previous contrast measurements and page-weight estimates applied to the original exterior hero.
Re-measure those against the selected final image. For production on large displays, use a
higher-resolution source. The page still has no third-party resource calls.

## Still open

- Jay Westman testimonial video — placeholder block is sized and ready for the embed
- Calendar/scheduling tool — placeholder block in the booking section
- Real builder data — `riverstone-homes` is a stand-in
- Hosting domain, which determines the slug URLs printed on the DM
