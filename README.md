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

For a design review without Python, download the repository ZIP, unzip it, and open
`dist/riverstone-homes/index.html` in a browser. The `dist` folder is committed so the
current approved review build travels with the source files.

Pushes to `main` also run `.github/workflows/pages.yml`, rebuild `dist/`, and publish it
as the GitHub Pages review site. `review-index.html` redirects the Pages root to the
primary Riverstone Homes page; the alternate remains available at `/riverstone-homes-b/`.

## Adding builders

Append rows to `data/builders.csv` and rebuild:

```csv
slug,first_name,company,province
riverstone-homes,Michael,Riverstone Homes,Ontario
```

`slug` becomes the URL segment, so it is what the printed QR code encodes. **Slugs must be final
before the direct mail goes to print.**

## Copy

Keep supplied campaign copy verbatim. Do not rewrite it or add personalization
unless requested. Do not use em dashes in visitor-facing copy.

`data/approved-copy.json` records the approved BTR-3731 v1 campaign copy and later
user directions. Material and labour cost savings lead the product summary; the performance
section includes both savings and the approved noise-reduction benefit. The approved Jayman introduction is retained exactly as requested.
`data/copy-audit.json` records the copy reconciliation, source references and
remaining factual qualifications. These files are editorial references; the
templates contain the rendered copy.

## Images

`assets/img/*.png` are the source images and are *not* shipped. The AVIF/WebP variants in
`assets/img/opt/` are. After replacing or adding a source PNG:

```bash
python3 tools/optimize_images.py
```

Adjust the `JOBS` dict in that file to change which widths get generated.

## Typeface

Both landing pages use **Source Sans Pro**, matching the [BTRboard website](https://www.btrboard.com/products/),
including headings, body copy, buttons, the technical summary and product labels.
The regular (400), semibold (600) and bold (700) WOFF2 files are self-hosted in
`assets/fonts/`, with Latin and Latin-ext subsets for accented names. Existing
medium (500) emphasis uses semibold (600), since this family has no static 500 weight.
The regular Latin file is preloaded in both templates; other subsets and weights
load only when needed. Typography is tuned for Source Sans Pro with regular-weight
headings, relaxed tracking and line spacing, and semibold buttons and small labels.

Font files come from the site's [Source Sans Pro stylesheet](https://www.btrboard.com/wp-content/uploads/elementor/google-fonts/css/sourcesanspro.css).
The SIL Open Font License and Adobe copyright notice ship in
`assets/fonts/source-sans-pro-OFL.txt`. No external font service or subscription is required.

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

The hero uses `assets/video/hero-interior-daylight.mp4`: a silent 20-second, 1600 × 900 H.264
animated-photo loop (about 6.4 MB). Warm sunlight gradually fades into a cooler dusk over 12
seconds, then eases back over eight seconds. Broad, feathered floor-light projections shift
70 source pixels and soften as the direct light fades. A 2.5% push-in gently returns to its
starting frame; small feathered tree patches move inside the windows. Relighting keeps the
floor texture, interior geometry and printed boards fixed. This is a constructed cinemagraph,
not recorded jobsite footage. The previous 12-second `hero-interior-sunset.mp4` is retained
for comparison; switching the template's video `data-src` back restores it.

`assets/js/hero-video.js` keeps the still visible until playback starts, exposes a pause/play
control, and pauses the video when the hero is offscreen or the tab is hidden. Reduced-motion,
Save-Data, and reported 2G connections use the still without loading the MP4. If autoplay is
blocked, a Play control appears over the still; media errors keep the still visible.

To regenerate the video on an Apple Silicon Mac with Xcode Command Line Tools, follow the
compile/render commands at the top of `tools/render_hero_video.swift`. Choose a new output name
when rerendering; the script protects existing files. Normal `python3 build.py` runs simply copy
the existing video and require no Swift tooling.

**Version B hero:** `template-b.html` uses `assets/video/hero-home-winter-life.mp4`, a
20-second silent animated-photo loop of the existing snowy house. Snow drifts in front of
the scene; a small resident walks behind the upstairs-right window, then that room's light
dims and comes back on. Its lighting mask includes the illuminated sill and inner frame
edges, fading them with the room to a cool ambient tone. The house and camera remain fixed. The responsive `gen-home-dusk`
stills remain the loading/reduced-motion fallback, using the same playback controller as A.

`tools/render_winter_hero.swift` renders the loop with native macOS video tools. Its resident
uses one stable photographic cutout with continuous arm/leg movement and a small walking bob,
avoiding flicker from blending different generated poses. The cutout is filtered before
downscaling to keep fine details from shimmering. It comes from the transparent
`assets/img/hero-winter-resident-sprites.png` sheet made with the
built-in imagegen tool; the exact prompt is saved in
`tools/hero-winter-resident-sprites.prompt.txt`. Source PNGs are excluded from the built site.
This is a composited animation, not filmed activity or a generative reconstruction of the house.

**Performance on both versions:** seven benefits use the same heading size, green
stroke icons and blue dividers over the approved wall photograph. Four equal columns
wrap to a centered row of three on desktop, two columns below 1100px, and one below
580px. The performance overlay is 78% black. Resistance and savings have the same
emphasis as health, insulation, soundproofing, airflow and energy.

Previous contrast measurements and page-weight estimates applied to the original exterior hero.
Re-measure those against the selected final image. For production on large displays, use a
higher-resolution source. The page still has no third-party resource calls.

## Still open

Both versions use matching product markers, leader lines and explanations. Notes start
closed. Hovering a marker or its note reveals the explanation; click or tap keeps it open
until another click, an outside click, or Escape. Keyboard users can Tab to each marker
and press Enter or Space. The insulation note sits over the upper blue facer, including
on small screens; the other notes use a bottom caption on small screens.

The primary page's testimonial section has a contained 16:9 video area alongside Jay's attribution, with
no blue-wall background, portrait or poster image. Set the video's empty `data-src` in
`template.html` to Jay's final video file when available. Until then, the play control shows
"Video coming soon" and stays disabled; no stand-in footage is loaded. The alternate
`template-b.html` retains its existing presentation.

- Jay Westman testimonial video — final asset pending
- Calendar/scheduling tool — placeholder block in the booking section
- Real builder data — `riverstone-homes` is a stand-in
- Hosting domain, which determines the slug URLs printed on the DM
