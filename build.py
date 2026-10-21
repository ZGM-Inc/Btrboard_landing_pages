#!/usr/bin/env python3
"""Build campaign pages with the selected design and assigned booking calendar.

Review samples retain both designs. Run: python3 build.py
"""
import csv
import html
import json
import re
import shutil
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).parent
TEMPLATES = sorted(ROOT.glob("template*.html"))
DATA = ROOT / "data" / "builders.csv"
REVIEW_DATA = ROOT / "data" / "review-builders.csv"
BOOKINGS = ROOT / "data" / "booking-contacts.json"
ASSETS = ROOT / "assets"
DIST = ROOT / "dist"
REPORT = ROOT / "reports" / "builder-pages.csv"

TOKEN = re.compile(r"\{\{\s*(\w+)\s*\}\}")
ASSET = re.compile(r'((?:href|src)=")(\.\./assets/[^"?]+\.(?:css|js))(")')
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def load_contacts(path: Path) -> dict:
    contacts = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(contacts, dict) or not contacts:
        raise ValueError(f"{path.name}: no booking contacts configured")
    for key, contact in contacts.items():
        if not isinstance(contact, dict) or not contact.get("name"):
            raise ValueError(f"{path.name}: missing name for {key!r}")
        parsed = urlsplit(contact.get("booking_url", ""))
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError(f"{path.name}: invalid booking URL for {key!r}")
    return contacts


def load_builders(path: Path, contacts: dict) -> list:
    required = {"slug", "first_name", "company", "province", "btr_contact"}
    rows = []
    with path.open(newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"{path.name}: missing columns {', '.join(sorted(missing))}")
        for line, source in enumerate(reader, start=2):
            if None in source:
                raise ValueError(f"{path.name}:{line}: extra CSV values; quote names containing commas")
            row = {key: (value or "").strip() for key, value in source.items()}
            if not any(row.values()):
                continue
            empty = [key for key in sorted(required) if not row[key]]
            if empty:
                raise ValueError(f"{path.name}:{line}: empty {', '.join(empty)}")
            if not SLUG.fullmatch(row["slug"]):
                raise ValueError(f"{path.name}:{line}: invalid slug {row['slug']!r}")
            rep = row["btr_contact"].lower()
            if rep not in contacts:
                raise ValueError(f"{path.name}:{line}: unknown BTR contact {rep!r}; no fallback calendar")
            row["btr_contact"] = rep
            row["first_drop"] = row.get("first_drop", "no").lower() or "no"
            if row["first_drop"] not in {"yes", "no"}:
                raise ValueError(f"{path.name}:{line}: first_drop must be yes or no")
            row["booking_url"] = contacts[rep]["booking_url"]
            row["booking_contact_name"] = contacts[rep]["name"]
            rows.append(row)
    return rows


def bust(markup: str) -> str:
    """Stamp local CSS/JS links with file mtimes to avoid stale review assets."""
    def sub(match):
        path = ROOT / match.group(2).replace("../", "", 1)
        version = int(path.stat().st_mtime) if path.exists() else 0
        return f"{match.group(1)}{match.group(2)}?v={version}{match.group(3)}"
    return ASSET.sub(sub, markup)


def render(template: str, row: dict) -> str:
    def sub(match):
        key = match.group(1)
        if key not in row:
            raise KeyError(f"template uses {{{{{key}}}}} but builder data has no such field")
        return html.escape(row[key], quote=True)
    return bust(TOKEN.sub(sub, template))


def variant_suffix(path: Path) -> str:
    """template.html -> '' | template-b.html -> '-b'"""
    return "" if path.stem == "template" else path.stem.replace("template", "", 1)


def plan_pages(campaign: list, review: list, templates: list) -> list:
    primary = next((tpl for tpl in templates if tpl.name == "template.html"), None)
    if primary is None:
        raise ValueError("template.html is required for the selected unfinished-beams design")
    pages = [(row["slug"], primary, row) for row in campaign]
    pages.extend(
        (f"{row['slug']}{variant_suffix(tpl)}", tpl, row)
        for row in review for tpl in templates
    )
    seen = {"assets"}
    for slug, _, _ in pages:
        if slug in seen:
            raise ValueError(f"duplicate or reserved page path: {slug}")
        seen.add(slug)
    return pages


def write_report(rows: list) -> None:
    REPORT.parent.mkdir(exist_ok=True)
    fields = ["company", "contact_name", "first_name", "province", "btr_contact",
              "booking_contact_name", "first_drop", "page_path", "booking_url"]
    with REPORT.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({**row, "page_path": f"{row['slug']}/"})


def main() -> None:
    contacts = load_contacts(BOOKINGS)
    rows = load_builders(DATA, contacts)
    if not rows:
        raise SystemExit("builders.csv has no rows")
    review = load_builders(REVIEW_DATA, contacts)
    plan = plan_pages(rows, review, TEMPLATES)
    sources = {tpl: tpl.read_text(encoding="utf-8") for tpl in TEMPLATES}
    # Validate and render everything before replacing the existing review build.
    pages = [(slug, render(sources[tpl], row), row) for slug, tpl, row in plan]

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    # Source PNGs and Dropbox sync artefacts do not ship to the website.
    shutil.copytree(
        ASSETS, DIST / "assets",
        ignore=shutil.ignore_patterns("*.png", "*.sb-*", ".DS_Store", "* (1)*", "*.tmp"),
    )
    for path in (DIST / "assets").rglob("*"):
        if path.is_file() and path.stat().st_size == 0:
            path.unlink()
    for slug, markup, row in pages:
        output = DIST / slug
        output.mkdir()
        (output / "index.html").write_text(markup, encoding="utf-8")
        print(f"  {slug}/   {row['company']} ({row['province']}) -> {row['booking_contact_name']}")
    shutil.copyfile(ROOT / "review-index.html", DIST / "index.html")
    write_report(rows)

    total = sum(path.stat().st_size for path in DIST.rglob("*") if path.is_file())
    print(f"\n{len(rows)} campaign pages + {len(pages) - len(rows)} review pages; {total/1024:.0f} KB on disk")
    print(f"Calendar assignments and page paths: {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
