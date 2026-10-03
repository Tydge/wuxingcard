"""Shared provenance and checked-source gate for desktop and Android builds."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from test_catalog import FULL_SUITE as SUITE, test_arguments

ROOT = Path(__file__).resolve().parents[1]


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


def check_manifest(snapshot=None):
    """Hash executable content and verification tools, independently of prose/licensing."""
    snapshot = snapshot or source_manifest()
    directories = {"assets", "audio", "battle", "data", "tests", "tools", "ui"}
    entries = [entry for entry in snapshot["files"]
               if (Path(entry["path"]).parts[0] in directories
                   or entry["path"] in {"project.godot", "export_presets.cfg"})
               and Path(entry["path"]).suffix != ".md"
               and "licenses" not in Path(entry["path"]).parts
               and not Path(entry["path"]).name.endswith("-LICENSE.txt")]
    fingerprint = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    return {"fingerprint": fingerprint, "files": entries}


def validate_checks(report, fingerprint, engine, required_tests=None):
    """Full by default; an explicitly requested named scope stays honestly targeted."""
    suite = [script for script in SUITE if Path(script).stem in set(required_tests or [])] if required_tests else SUITE
    profile = "targeted" if required_tests else "full"
    if required_tests and len(suite) != len(set(required_tests)):
        return False
    if not isinstance(report, dict):
        return False
    results = report.get("results", [])
    if not isinstance(results, list) or not all(isinstance(item, dict) for item in results):
        return False
    return (report.get("schema_version") == 2
            and report.get("profile") == profile
            and report.get("complete") is True
            and report.get("source_unchanged") is True
            and report.get("check_sha256") == fingerprint
            and report.get("engine") == engine
            and report.get("suite") == suite
            and [item.get("script") for item in results] == suite
            and all(item.get("exit_code") == 0
                    and item.get("arguments") == test_arguments(item["script"], profile)
                    for item in results))


def ensure_checks(godot, report_path=None, required_tests=None):
    if required_tests and not report_path:
        raise RuntimeError("A targeted release requires an explicit checks report and named scope.")
    snapshot = source_manifest()
    fingerprint = check_manifest(snapshot)["fingerprint"]
    engine = subprocess.check_output([godot, "--version"], text=True).strip()
    path = Path(report_path) if report_path else ROOT / "work/checks/full/latest.json"
    if path.is_file():
        try:
            report = json.loads(path.read_text())
        except (ValueError, OSError):
            report = {}
        if validate_checks(report, fingerprint, engine, required_tests):
            print(f"Reusing {report['profile']} regression ({len(report['results'])} tests): {path}", flush=True)
            return snapshot, report
    if report_path:
        raise RuntimeError("A passing report matching the requested scope, runtime, tests and engine is required.")
    subprocess.run([sys.executable, str(ROOT / "tools/check_project.py"), "--suite", "full",
                    "--godot", godot, "--output", str(path)], check=True)
    return ensure_checks(godot, path)
