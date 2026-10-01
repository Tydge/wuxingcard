"""Shared provenance and checked-source gate for desktop and Android builds."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITE = [f"res://tests/{name}.gd" for name in [
    "smoke_test", "card_expansion_test", "deck_store_test", "artifact_test",
    "flat_damage_test", "new_card_wave_test", "card_balance_test", "summon_expansion_test",
    "summon_presentation_test", "settlement_regression_test", "artifact_ui_test",
    "qi_cycle_test", "qi_hold_ui_test", "qi_hold_touch_test", "opening_flow_test", "opening_deal_test", "energy_help_ui_test", "upgrade_test", "upgrade_ui_test",
    "endless_run_test", "endless_recovery_test", "endless_ui_test", "endless_touch_test",
]] + ["res://tools/test_card_art.gd", "res://tools/test_summon_art.gd",
      "res://tools/test_card_keywords.gd", "res://tools/test_drag.gd",
      "res://tools/test_summon_drag.gd", "res://tools/test_deck_workshop.gd",
      "res://tools/verify_touch_ui.gd", "res://tools/test_touch_interactions.gd"]


def source_manifest():
    files = []
    for directory in ["assets", "audio", "battle", "data", "docs", "licenses", "tests", "tools", "ui"]:
        files.extend(p for p in (ROOT / directory).rglob("*") if p.is_file()
                     and "__pycache__" not in p.parts and p.name != ".DS_Store")
    files.extend(p for p in ROOT.iterdir() if p.is_file() and p.name != ".DS_Store")
    entries = [{"path": p.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
               for p in sorted(files)]
    fingerprint = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    return {"fingerprint": fingerprint, "files": entries}


def provenance(snapshot):
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()
    return {"revision": git("rev-parse", "HEAD"),
            "working_tree_changes": git("status", "--porcelain", "--untracked-files=all"),
            "source_sha256": snapshot["fingerprint"],
            "version": json.loads((ROOT / "data/version.json").read_text())["version"]}


def ensure_checks(godot, report_path=None):
    snapshot = source_manifest()
    if report_path:
        report = json.loads(Path(report_path).read_text())
        engine = subprocess.check_output([godot, "--version"], text=True).strip()
        if (report.get("source_sha256") != snapshot["fingerprint"]
                or report.get("engine") != engine
                or report.get("suite") != SUITE
                or len(report.get("results", [])) != len(SUITE)
                or any(item.get("exit_code") != 0 for item in report["results"])):
            raise RuntimeError("Checks report does not match the complete current source and engine; run check_project.py again.")
        return snapshot, report
    path = ROOT / "work/checks/latest.json"
    subprocess.run([sys.executable, str(ROOT / "tools/check_project.py"), "--godot", godot,
                    "--output", str(path)], check=True)
    return ensure_checks(godot, path)
