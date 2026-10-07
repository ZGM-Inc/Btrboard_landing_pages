#!/usr/bin/env python3
"""
Build the BTRboard ABM landing pages.

One template + one row per builder -> dist/<slug>/index.html
Run:  python3 build.py
"""
import csv, html, re, shutil
from pathlib import Path

ROOT     = Path(__file__).parent
TEMPLATES = sorted(ROOT.glob("template*.html"))
DATA     = ROOT / "data" / "builders.csv"
ASSETS   = ROOT / "assets"
DIST     = ROOT / "dist"

TOKEN = re.compile(r"\{\{\s*(\w+)\s*\}\}")
ASSET = re.compile(r'((?:href|src)=")(\.\./assets/[^"?]+\.(?:css|js))(")')


def bust(html: str) -> str:
    """Stamp local css/js links with the file's mtime.

    Without this the browser happily serves a stale stylesheet after a rebuild,
    which looks exactly like a broken layout and wastes a lot of time.
    """
    def sub(m):
        rel = m.group(2).replace("../", "", 1)
        f = ROOT / rel
        v = int(f.stat().st_mtime) if f.exists() else 0
        return f"{m.group(1)}{m.group(2)}?v={v}{m.group(3)}"
    return ASSET.sub(sub, html)


def render(template: str, row: dict) -> str:
    def sub(m):
        key = m.group(1)
        if key not in row:
            raise KeyError(f"template uses {{{{{key}}}}} but builders.csv has no such column")
        return html.escape(row[key], quote=True)
    return bust(TOKEN.sub(sub, template))


def variant_suffix(path: Path) -> str:
    """template.html -> ''   |   template-b.html -> '-b'"""
    stem = path.stem
    return "" if stem == "template" else stem.replace("template", "", 1)


def main() -> None:
    if not TEMPLATES:
        raise SystemExit("no template*.html found")

    with DATA.open(newline="", encoding="utf-8") as fh:
        rows = [r for r in csv.DictReader(fh) if r.get("slug")]

    if not rows:
        raise SystemExit("builders.csv has no rows")

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()

    # Shared assets, minus the heavy source PNGs (only the opt/ variants ship)
    # and minus Dropbox sync artefacts, which otherwise add ~10 MB of junk.
    shutil.copytree(
        ASSETS, DIST / "assets",
        ignore=shutil.ignore_patterns("*.png", "*.sb-*", ".DS_Store", "* (1)*", "*.tmp"),
    )
    # Drop anything that arrived empty.
    for f in (DIST / "assets").rglob("*"):
        if f.is_file() and f.stat().st_size == 0:
            f.unlink()

    seen = set()
    for row in rows:
        slug = row["slug"].strip()
        if slug in seen:
            raise SystemExit(f"duplicate slug in builders.csv: {slug}")
        seen.add(slug)

        for tpl in TEMPLATES:
            # Variants live as siblings, so "../assets/" resolves the same for all.
            out = DIST / f"{slug}{variant_suffix(tpl)}"
            out.mkdir(parents=True)
            (out / "index.html").write_text(
                render(tpl.read_text(encoding="utf-8"), row), encoding="utf-8"
            )
            print(f"  dist/{out.name}/index.html   {row['company']} ({row['province']})")

    total = sum(f.stat().st_size for f in DIST.rglob("*") if f.is_file())
    print(f"\n{len(rows)} builder(s) x {len(TEMPLATES)} variant(s) — {total/1024:.0f} KB on disk")

    big = sorted(((f.stat().st_size, f) for f in DIST.rglob("*") if f.is_file()), reverse=True)[:5]
    if big and big[0][0] > 512 * 1024:
        print("  largest files:")
        for size, f in big:
            if size > 256 * 1024:
                print(f"    {size/1024:8.0f} KB  {f.relative_to(DIST)}")


if __name__ == "__main__":
    main()
