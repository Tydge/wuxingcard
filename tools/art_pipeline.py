#!/usr/bin/env python3
"""Create art jobs from game data and ingest approved images into Godot.

Usage:
  python3 tools/art_pipeline.py manifest
  python3 tools/art_pipeline.py ingest card fire_strike /path/to/image.png
  python3 tools/art_pipeline.py ingest character ember /path/to/image.png
  python3 tools/art_pipeline.py ingest background arena /path/to/image.png
  python3 tools/art_pipeline.py ingest fx arcane_ring /path/to/image.png
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
STYLE = (
    "High quality dark eastern fantasy digital painting, consistent with a "
    "circular stone arena suspended among mountains. Strong readable focal "
    "subject, controlled contrast, no letters, words, numbers, logo, card frame, or UI."
)


def load(name):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def jobs():
    output = []
    for card in load("cards.json"):
        output.append({
            "kind": "card", "id": card["id"],
            "prompt": (
                f"Landscape 4:3 pure card illustration, ideally 1024x768 pixels: "
                f"{card['art_prompt']}. Keep the subject inside the central 80% "
                f"with no important details near the crop edges. "
                f"Dominant element: {card['element']}. {STYLE}"
            ),
            "output": f"assets/cards/generated/{card['id']}.webp",
        })
    for actor in load("characters.json"):
        output.append({
            "kind": "character", "id": actor["id"],
            "prompt": (
                f"Single transparent-background knees-up character illustration: "
                f"{actor['visual_prompt']}. {STYLE} No scenery."
            ),
            "output": f"assets/characters/{actor['id']}.webp",
        })
    for area in load("areas.json"):
        output.append({
            "kind": "background", "id": area["id"],
            "prompt": f"Wide 16:9 empty battlefield: {area['visual_prompt']}. {STYLE} No people.",
            "output": f"assets/backgrounds/{area['id']}.webp",
        })
    for effect in load("fx.json"):
        output.append({
            "kind": "fx", "id": effect["id"],
            "prompt": effect["art_prompt"],
            "output": f"assets/fx/{effect['id']}.webp",
        })
    return output


def image_info(path):
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        capture_output=True, text=True, check=True,
    )
    info = {}
    for line in result.stdout.splitlines():
        if ": " in line:
            key, value = line.strip().split(": ", 1)
            info[key] = value
    return int(info["pixelWidth"]), int(info["pixelHeight"]), info.get("hasAlpha") == "yes"


def ingest(kind, item_id, source):
    job = next((j for j in jobs() if j["kind"] == kind and j["id"] == item_id), None)
    if job is None:
        raise SystemExit(f"Unknown {kind} ID: {item_id}")
    if not source.is_file():
        raise SystemExit(f"Input not found: {source}")
    width, height, alpha = image_info(source)
    if min(width, height) < 512:
        raise SystemExit("Image rejected: minimum side must be at least 512 px")
    if kind == "card" and not (1.25 <= width / height <= 1.42):
        raise SystemExit("Image rejected: card art needs a 4:3 landscape composition")
    if kind == "background" and width / height < 1.4:
        raise SystemExit("Image rejected: battlefield needs a wide composition")
    if kind == "character" and not alpha:
        raise SystemExit("Image rejected: character needs a transparent background")
    if kind == "fx" and (not alpha or not (0.9 <= width / height <= 1.1)):
        raise SystemExit("Image rejected: FX needs a transparent square image")
    destination = ROOT / job["output"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise SystemExit(f"Destination already exists; save a version first: {destination}")
    if source.suffix.lower() == ".webp":
        shutil.copy2(source, destination)
    else:
        subprocess.run(["cwebp", "-quiet", "-q", "86", "-alpha_q", "95", str(source), "-o", str(destination)], check=True)
    print(destination)
    print("Image size and transparency checks passed. Review composition and text visually before release.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("manifest")
    ingest_parser = sub.add_parser("ingest")
    ingest_parser.add_argument("kind", choices=["card", "character", "background", "fx"])
    ingest_parser.add_argument("id")
    ingest_parser.add_argument("source", type=Path)
    args = parser.parse_args()
    if args.command == "manifest":
        path = ROOT / "work" / "art_manifest.json"
        path.parent.mkdir(exist_ok=True)
        payload = {"style": STYLE, "jobs": jobs()}
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(path)
        print(f"{len(payload['jobs'])} jobs generated from game data")
    else:
        ingest(args.kind, args.id, args.source)


if __name__ == "__main__":
    main()
