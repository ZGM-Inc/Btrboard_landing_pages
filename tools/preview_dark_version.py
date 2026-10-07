"""Create a local comparison page from the saved dark version after a normal build."""
import csv
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKUP = ROOT / "backups" / "2026-10-06-dark-before-brand-trial"
DIST = ROOT / "dist"


def main():
    if not (DIST / "assets").is_dir():
        raise SystemExit("Run python3 build.py first.")
    manifest = json.loads((BACKUP / "manifest.json").read_text())
    for name, digest in manifest.items():
        if hashlib.sha256((BACKUP / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f"The saved original has changed: {name}")

    spec = importlib.util.spec_from_file_location("btr_build", ROOT / "build.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    with (ROOT / "data" / "builders.csv").open(newline="", encoding="utf-8") as file:
        row = next((row for row in csv.DictReader(file) if row.get("slug")), None)
    if row is None:
        raise SystemExit("builders.csv has no rows")

    css_name = "btr-dark-before-brand-trial.css"
    shutil.copy2(BACKUP / "assets/css/btr.css", DIST / "assets/css" / css_name)
    template = (BACKUP / "template.html").read_text(encoding="utf-8")
    template = template.replace("../assets/css/btr.css", "../assets/css/" + css_name)
    preview = DIST / "compare-dark"
    preview.mkdir(exist_ok=True)
    (preview / "index.html").write_text(builder.render(template, row), encoding="utf-8")
    print(f"Original dark version for {row['company']}: http://127.0.0.1:8788/compare-dark/")


if __name__ == "__main__":
    main()
