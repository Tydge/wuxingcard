#!/usr/bin/env python3
"""Run quick rules by default; select groups or --suite full for release regression."""
import argparse
from datetime import datetime, timezone
import json
import re
import subprocess
import time
from pathlib import Path
from build_support import ROOT, source_manifest, check_manifest
from test_catalog import GROUPS, PROFILES, GRAPHICAL, select_tests, test_arguments


def run_checks(godot, profile, scripts, output_path, keep_going=False, timeout=None):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([godot, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
    snapshot = source_manifest()
    checked = check_manifest(snapshot)
    results = []
    for script in scripts:
        graphical = Path(script).stem in GRAPHICAL
        arguments = [godot] + ([] if graphical else ['--headless']) + ['--path', str(ROOT), '--script', script]
        user_arguments = test_arguments(script, profile)
        if user_arguments:
            arguments += ['--', *user_arguments]
        limit = timeout if timeout is not None else (120 if profile == 'full' else 60 if graphical else 45)
        started = time.monotonic()
        try:
            completed = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, timeout=limit)
            output = completed.stdout + completed.stderr
            code = completed.returncode
            if re.search(r'(^|\n)(SCRIPT ERROR|ERROR):', output):
                code = code or 1
        except subprocess.TimeoutExpired as error:
            partial = error.stdout or b''
            errors = error.stderr or b''
            output = (partial.decode(errors='replace') if isinstance(partial, bytes) else partial) + (errors.decode(errors='replace') if isinstance(errors, bytes) else errors) + '\n' + str(error)
            code = 124
        duration = round(time.monotonic() - started, 3)
        log = output_path.parent / (Path(script).stem + '.log')
        log.write_text(output)
        results.append({'script': script, 'exit_code': code, 'log': log.name,
                        'duration_seconds': duration, 'timeout_seconds': limit,
                        'arguments': user_arguments})
        summaries = [line for line in output.splitlines() if 'failures' in line or 'ERROR:' in line]
        print(('PASS' if code == 0 else 'FAIL') + f' {script} ({duration:.1f}s)' + (' — ' + summaries[-1] if summaries else ''), flush=True)
        if code and not keep_going:
            print('Stopped after failure. Fix or inspect this test; do not rerun unrelated scopes.', flush=True)
            break
    unchanged = check_manifest()['fingerprint'] == checked['fingerprint']
    report = {'schema_version': 2, 'checked_at': datetime.now(timezone.utc).isoformat(),
              'profile': profile, 'source_sha256': snapshot['fingerprint'],
              'check_sha256': checked['fingerprint'], 'source_unchanged': unchanged,
              'engine': subprocess.check_output([godot, '--version'], text=True).strip(),
              'suite': scripts, 'complete': len(results) == len(scripts), 'results': results}
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if not unchanged:
        print('Runtime or test source changed during the checks; this report is invalid.', flush=True)
    print(f"{sum(r['exit_code'] == 0 for r in results)}/{len(scripts)} passed; report: {output_path}", flush=True)
    return 1 if not unchanged or any(r['exit_code'] != 0 for r in results) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument('--suite', choices=PROFILES, help='Default: quick (four headless rule tests)')
    selection.add_argument('--group', action='append', choices=GROUPS, help='Repeat to combine affected areas')
    selection.add_argument('--test', action='append', help='Repeat registered test names to run only affected cases')
    parser.add_argument('--list', action='store_true', help='Print selection without importing or starting Godot')
    parser.add_argument('--keep-going', action='store_true', help='Collect all failures instead of stopping at the first')
    parser.add_argument('--timeout', type=float, help='Per-test seconds; does not retry automatically')
    parser.add_argument('--godot', default='/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--output', type=Path, help='Default: work/checks/<profile>/latest.json')
    args = parser.parse_args()
    if args.timeout is not None and args.timeout <= 0:
        parser.error('--timeout must be positive')
    try:
        profile, scripts = select_tests(args.suite, args.group, args.test)
    except ValueError as error:
        parser.error(str(error))
    print(f'Profile: {profile}; {len(scripts)} tests', flush=True)
    for script in scripts:
        print('  ' + script + (' [GUI]' if Path(script).stem in GRAPHICAL else ' [headless]')
              + (' ' + ' '.join(test_arguments(script, profile)) if test_arguments(script, profile) else ''), flush=True)
    if args.list:
        return 0
    return run_checks(args.godot, profile, scripts,
                      args.output or ROOT / 'work/checks' / profile / 'latest.json',
                      args.keep_going, args.timeout)


if __name__ == '__main__':
    raise SystemExit(main())
