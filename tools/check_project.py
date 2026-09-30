#!/usr/bin/env python3
"""Run the complete deterministic rules/UI regression suite before a build."""
import argparse
from datetime import datetime, timezone
import json
import re
import subprocess
from pathlib import Path
from build_support import ROOT, SUITE, source_manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--output', type=Path, default=ROOT / 'work/checks/latest.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
    snapshot = source_manifest()
    results = []
    for script in SUITE:
        # UI integration checks use a real renderer; the dummy headless texture
        # backend cannot reliably load every imported background/animation.
        graphical = Path(script).stem in ['artifact_ui_test', 'opening_deal_test', 'energy_help_ui_test',
                                        'test_card_keywords', 'test_drag', 'test_summon_drag', 'test_deck_workshop']
        arguments = [args.godot] + ([] if graphical else ['--headless']) + ['--path', str(ROOT), '--script', script]
        if script.endswith('verify_touch_ui.gd'): arguments += ['--', '--touch-ui']
        try:
            completed = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, timeout=120)
            output = completed.stdout + completed.stderr
            code = completed.returncode
            if re.search(r'(^|\n)(SCRIPT ERROR|ERROR):', output): code = code or 1
        except subprocess.TimeoutExpired as error:
            partial = error.stdout or b''
            errors = error.stderr or b''
            output = (partial.decode(errors='replace') if isinstance(partial, bytes) else partial) + (errors.decode(errors='replace') if isinstance(errors, bytes) else errors) + '\n' + str(error)
            code = 124
        log = args.output.parent / (Path(script).stem + '.log')
        log.write_text(output)
        results.append({'script': script, 'exit_code': code, 'log': log.name})
        summaries = [line for line in output.splitlines() if 'failures' in line or 'ERROR:' in line]
        print(('PASS' if code == 0 else 'FAIL') + ' ' + script + (' — ' + summaries[-1] if summaries else ''), flush=True)
    if source_manifest()['fingerprint'] != snapshot['fingerprint']:
        raise RuntimeError('Project source changed during the checks; rerun the complete suite.')
    report = {'checked_at': datetime.now(timezone.utc).isoformat(), 'source_sha256': snapshot['fingerprint'],
              'engine': subprocess.check_output([args.godot, '--version'], text=True).strip(),
              'suite': SUITE, 'results': results}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(1 if any(r['exit_code'] != 0 for r in results) else 0)


if __name__ == '__main__':
    main()
