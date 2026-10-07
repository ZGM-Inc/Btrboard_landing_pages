"""Re-encode source PNGs to AVIF + WebP at sensible display sizes."""
import os
from PIL import Image

SRC = "assets/img"
OUT = "assets/img/opt"
os.makedirs(OUT, exist_ok=True)

# name -> max width on screen (2x for retina, capped at native)
JOBS = {
    # Current image sources. Earlier hero candidates remain available for comparison.
    "hero-interior-sunset": [1600, 1376, 980, 700],
    "gen-home-dusk":       [1376, 980, 700],
    "gen-board-angled":   [1400, 1000, 700],
    "gen-board-black":    [1376, 980, 700],
    "gen-wall-golden":    [1376, 980, 700],
    "performance-wall-btr": [1678, 1376, 980, 700],
    "placeholder-testimonial": [1376, 980, 700],
}

rows = []
for base, widths in JOBS.items():
    src = Image.open(f"{SRC}/{base}.png")
    has_alpha = src.mode in ("RGBA", "LA")
    for w in widths:
        if w > src.width:
            continue
        h = round(src.height * w / src.width)
        im = src.resize((w, h), Image.LANCZOS)
        if not has_alpha:
            im = im.convert("RGB")
        for ext, kw in (("avif", dict(quality=58)), ("webp", dict(quality=78, method=6))):
            p = f"{OUT}/{base}-{w}.{ext}"
            im.save(p, **kw)
            rows.append((f"{base}-{w}.{ext}", os.path.getsize(p)))

orig = sum(os.path.getsize(f"{SRC}/{b}.png") for b in JOBS)
new = sum(s for _, s in rows)
for n, s in sorted(rows):
    print(f"{n:<34} {s/1024:7.0f} KB")
print(f"\noriginal PNGs {orig/1024/1024:.1f} MB  ->  all variants {new/1024:.0f} KB")
