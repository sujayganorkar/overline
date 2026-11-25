"""Collect native PDF engine notices from the submodule and locked Cargo sources."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tomllib


ROOT = Path(__file__).resolve().parent.parent
PDFCRAFT = ROOT / "third_party/pdfcraft"
OUTPUT = ROOT / "assets/licenses/pdf-engine.json"


def collect():
    # Store shared license texts once, preserving every component's attribution.
    notices = {}

    def add(component, path):
        notices.setdefault(path.read_text(encoding="utf-8"), set()).add(component)

    manifest = tomllib.loads((PDFCRAFT / "LICENSES.toml").read_text())
    for document in manifest["document"]:
        path = PDFCRAFT / document["source"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != document["sha256"]:
            raise ValueError(f"PdfCraft license manifest checksum mismatch: {path}")
        add("PdfCraft", path)

    for path in sorted((PDFCRAFT / "licenses/pdf-backend").rglob("*")):
        if path.is_file():
            add("Hayro PDF renderer", path)
    for name in ("lopdf", "vello_common", "vello_cpu"):
        for path in sorted((PDFCRAFT / "vendor" / name).glob("LICENSE*")):
            add(name, path)

    # The engine pins different craft-libs revisions for individual crates.
    # Preserve each revision's notices, including any distinct copyright texts.
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--locked", "--format-version", "1",
         "--filter-platform", "aarch64-linux-android"], cwd=ROOT
    ))
    checkouts = {}
    for package in metadata["packages"]:
        source = package["source"] or ""
        if source.startswith("git+https://github.com/storytold/craft-libs?"):
            path = Path(package["manifest_path"])
            checkout = next(parent for parent in path.parents if (parent / ".git").exists())
            checkouts[source.rsplit("#", 1)[1]] = checkout
    if not checkouts:
        raise ValueError("Expected craft-libs in the locked dependency graph")
    for _, checkout in sorted(checkouts.items()):
        for name in ("NOTICE", "LICENSE-MIT", "LICENSE-APACHE"):
            add("craft-libs", checkout / name)
        for component in ("pdf-backend", "pdf-writer", "prc-rs", "jpeg-encoder-0.6.1"):
            for path in sorted((checkout / "licenses" / component).rglob("*")):
                if path.is_file() and path.suffix != ".json":
                    add("craft-libs", path)

    return [{"packages": sorted(packages), "text": notice} for notice, packages in notices.items()]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check the packaged notices")
    args = parser.parse_args()
    generated = json.dumps(collect(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != generated:
            raise SystemExit("Refresh the engine notices with python3 tools/native-notices.py")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(generated, encoding="utf-8")
