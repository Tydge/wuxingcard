"""Fast Python checks for selection, report integrity and release cache; no Godot."""
import copy
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_support
import check_project
from test_catalog import FULL_SUITE, GRAPHICAL, GROUPS, PROFILES, select_tests, test_arguments


def full_report():
    return {'schema_version': 2, 'profile': 'full', 'complete': True,
            'source_unchanged': True, 'check_sha256': 'runtime', 'engine': 'engine',
            'suite': list(FULL_SUITE),
            'results': [{'script': script, 'exit_code': 0, 'arguments': test_arguments(script, 'full')}
                        for script in FULL_SUITE]}


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        output = redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)

    def test_default_scope_is_small_and_headless(self):
        profile, scripts = select_tests()
        self.assertEqual(profile, 'quick')
        self.assertEqual(len(scripts), 4)
        self.assertFalse(any(Path(s).stem in GRAPHICAL for s in scripts))

    def test_registered_files_and_group_union(self):
        self.assertGreaterEqual(len(FULL_SUITE), 31)
        self.assertEqual(len(set(FULL_SUITE)), len(FULL_SUITE))
        self.assertEqual(set(name for names in GROUPS.values() for name in names) -
                         {Path(s).stem for s in FULL_SUITE}, set())
        for script in FULL_SUITE:
            self.assertTrue((build_support.ROOT / script[6:]).is_file(), script)
        _, scripts = select_tests(groups=['cards', 'artifacts'])
        self.assertEqual(len(scripts), len(set(scripts)))
        self.assertEqual(select_tests(tests=['artifact_ui_test', 'res://tests/artifact_ui_test.gd'])[1],
                         ['res://tests/artifact_ui_test.gd'])
        with self.assertRaises(ValueError):
            select_tests(tests=['test_card_expansion_ui'])

    def test_quick_parameters_preserve_full_samples_and_touch(self):
        script = 'res://tests/upgrade_test.gd'
        self.assertEqual(test_arguments(script, 'targeted'), ['--quick'])
        self.assertEqual(test_arguments(script, 'full'), [])
        self.assertEqual(test_arguments('res://tests/endless_touch_test.gd', 'full'), ['--touch-ui'])

    def test_prose_does_not_invalidate_runtime_but_code_and_text_assets_do(self):
        files = [{'path': p, 'sha256': 'a'} for p in
                 ['README.md', 'docs/testing.md', 'AGENTS.md', 'ui/battle_ui.gd',
                  'data/cards.json', 'assets/rules.txt', 'assets/fonts/Noto-LICENSE.txt',
                  'project.godot', 'tools/test_catalog.py']]
        original = build_support.check_manifest({'files': files})['fingerprint']
        for index in [0, 1, 2, 6]:
            changed = copy.deepcopy(files); changed[index]['sha256'] = 'b'
            self.assertEqual(original, build_support.check_manifest({'files': changed})['fingerprint'])
        for index in [3, 4, 5, 7, 8]:
            changed = copy.deepcopy(files); changed[index]['sha256'] = 'b'
            self.assertNotEqual(original, build_support.check_manifest({'files': changed})['fingerprint'])

    def test_release_rejects_partial_failing_and_duplicate_results(self):
        for malformed in [None, [], {"results": None}, {"results": [None]}]:
            self.assertFalse(build_support.validate_checks(malformed, "runtime", "engine"))
        self.assertTrue(build_support.validate_checks(full_report(), 'runtime', 'engine'))
        mutations = [('profile', 'quick'), ('complete', False), ('source_unchanged', False),
                     ('check_sha256', 'old'), ('schema_version', 1), ('engine', 'old')]
        for key, value in mutations:
            report = full_report(); report[key] = value
            self.assertFalse(build_support.validate_checks(report, 'runtime', 'engine'))
        for mutation in ['missing', 'duplicate', 'failed', 'quick']:
            report = full_report()
            if mutation == 'missing': report['results'].pop()
            elif mutation == 'duplicate': report['results'][-1] = report['results'][0]
            elif mutation == 'failed': report['results'][0]['exit_code'] = 1
            else: report['results'][0]['arguments'] = ['--quick']
            self.assertFalse(build_support.validate_checks(report, 'runtime', 'engine'))

    def test_release_reuses_cache_and_explicit_bad_report_does_not_run_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); path = root / 'work/checks/full/latest.json'
            path.parent.mkdir(parents=True); path.write_text(json.dumps(full_report()))
            with patch.object(build_support, 'ROOT', root), \
                 patch.object(build_support, 'source_manifest', return_value={'fingerprint': 'new-docs', 'files': []}), \
                 patch.object(build_support, 'check_manifest', return_value={'fingerprint': 'runtime'}), \
                 patch.object(build_support.subprocess, 'check_output', return_value='engine'), \
                 patch.object(build_support.subprocess, 'run') as run:
                snapshot, report = build_support.ensure_checks('godot')
                self.assertEqual(snapshot['fingerprint'], 'new-docs')
                self.assertEqual(report['profile'], 'full'); run.assert_not_called()
                report['profile'] = 'targeted'; path.write_text(json.dumps(report))
                with self.assertRaises(RuntimeError): build_support.ensure_checks('godot', path)
                run.assert_not_called()

    def test_explicit_targeted_release_preserves_scope_and_failure_gate(self):
        names = ['wuxing_spirits_cards_test', 'wuxing_spirits_ui_test', 'wuxing_spirits_touch_test', 'upgrade_test']
        profile, scripts = select_tests(tests=names)
        report = full_report()
        report.update(profile=profile, suite=scripts, results=[{'script': script, 'exit_code': 0, 'arguments': test_arguments(script, profile)} for script in scripts])
        self.assertTrue(build_support.validate_checks(report, 'runtime', 'engine', names))
        self.assertFalse(build_support.validate_checks(report, 'runtime', 'engine'))
        self.assertFalse(build_support.validate_checks(report, 'runtime', 'engine', names[:-1]))
        for key, value in [('complete', False), ('source_unchanged', False), ('check_sha256', 'old')]:
            bad = copy.deepcopy(report); bad[key] = value
            self.assertFalse(build_support.validate_checks(bad, 'runtime', 'engine', names))
        bad = copy.deepcopy(report); bad['results'][0]['exit_code'] = 1
        self.assertFalse(build_support.validate_checks(bad, 'runtime', 'engine', names))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'targeted.json'; path.write_text(json.dumps(report))
            with patch.object(build_support, 'source_manifest', return_value={'fingerprint':'source','files':[]}), patch.object(build_support, 'check_manifest', return_value={'fingerprint':'runtime'}), patch.object(build_support.subprocess, 'check_output', return_value='engine'), patch.object(build_support.subprocess, 'run') as run:
                self.assertEqual(build_support.ensure_checks('godot', path, names)[1]['profile'], 'targeted')
                with self.assertRaises(RuntimeError): build_support.ensure_checks('godot', None, names)
                run.assert_not_called()

    def test_missing_cache_requests_full_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'work/checks/full/latest.json'
            def create_report(arguments, **kwargs):
                self.assertIn('--suite', arguments)
                self.assertEqual(arguments[arguments.index('--suite') + 1], 'full')
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(full_report()))
                return subprocess.CompletedProcess(arguments, 0)
            with patch.object(build_support, 'ROOT', root), \
                 patch.object(build_support, 'source_manifest', return_value={'fingerprint': 'source', 'files': []}), \
                 patch.object(build_support, 'check_manifest', return_value={'fingerprint': 'runtime'}), \
                 patch.object(build_support.subprocess, 'check_output', return_value='engine'), \
                 patch.object(build_support.subprocess, 'run', side_effect=create_report) as run:
                build_support.ensure_checks('godot')
                run.assert_called_once()

    def test_runner_stops_after_first_failure_and_records_unexecuted_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'latest.json'
            scripts = PROFILES['quick']
            with patch.object(check_project, 'source_manifest', return_value={'fingerprint': 'source', 'files': []}), \
                 patch.object(check_project, 'check_manifest', return_value={'fingerprint': 'runtime'}), \
                 patch.object(check_project.subprocess, 'check_output', return_value='engine'), \
                 patch.object(check_project.subprocess, 'run', side_effect=[
                     subprocess.CompletedProcess([], 0),
                     subprocess.CompletedProcess([], 0, 'ERROR: real assertion failure\n', '')]) as run:
                self.assertEqual(check_project.run_checks('godot', 'quick', scripts, path), 1)
                self.assertEqual(run.call_count, 2)
            report = json.loads(path.read_text())
            self.assertFalse(report['complete']); self.assertEqual(len(report['results']), 1)
            self.assertEqual(report['results'][0]['exit_code'], 1)
            self.assertEqual(report['results'][0]['timeout_seconds'], 45)
            self.assertIn('duration_seconds', report['results'][0])

    def test_runner_timeout_keep_going_and_source_change_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'latest.json'
            scripts = PROFILES['quick'][:2]
            with patch.object(check_project, 'source_manifest', return_value={'fingerprint': 'source', 'files': []}), \
                 patch.object(check_project, 'check_manifest', side_effect=[{'fingerprint': 'before'}, {'fingerprint': 'after'}]), \
                 patch.object(check_project.subprocess, 'check_output', return_value='engine'), \
                 patch.object(check_project.subprocess, 'run', side_effect=[
                     subprocess.CompletedProcess([], 0), subprocess.TimeoutExpired('godot', 45, b'partial output'),
                     subprocess.CompletedProcess([], 0, '0 failures', '')]):
                self.assertEqual(check_project.run_checks('godot', 'quick', scripts, path, keep_going=True), 1)
            report = json.loads(path.read_text())
            self.assertTrue(report['complete']); self.assertFalse(report['source_unchanged'])
            self.assertEqual(report['results'][0]['exit_code'], 124)
            self.assertEqual(report['results'][1]['exit_code'], 0)
            self.assertIn('partial output', (path.parent / report['results'][0]['log']).read_text())

    def test_runner_audio_is_silent_by_default_with_explicit_opt_in(self):
        for enabled in [False, True]:
            with self.subTest(enabled=enabled), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'latest.json'
                with patch.object(check_project, 'source_manifest', return_value={'fingerprint': 'source', 'files': []}), \
                     patch.object(check_project, 'check_manifest', return_value={'fingerprint': 'runtime'}), \
                     patch.object(check_project.subprocess, 'check_output', return_value='engine'), \
                     patch.object(check_project.subprocess, 'run', side_effect=[
                         subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0, '0 failures', '')]) as run:
                    self.assertEqual(check_project.run_checks('godot', 'targeted', ['res://tests/artifact_ui_test.gd'], path, enable_audio=enabled), 0)
                command = run.call_args.args[0]
                self.assertEqual('--audio-driver' in command, not enabled)
                if not enabled:
                    self.assertEqual(command[command.index('--audio-driver') + 1], 'Dummy')
                self.assertEqual(run.call_args.kwargs['env']['WUXING_TEST_AUDIO'], '1' if enabled else '0')
                self.assertEqual(json.loads(path.read_text())['audio_enabled'], enabled)


if __name__ == '__main__':
    unittest.main()
