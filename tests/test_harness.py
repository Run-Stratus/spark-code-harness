"""Local acceptance tests. No production credential or network is required."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HarnessTests(unittest.TestCase):
    def checker(self, mode, value, *args):
        return subprocess.run(
            ['/usr/bin/osascript', '-l', 'JavaScript', str(ROOT / 'scripts/check-json.js'), mode, *args],
            input=value if isinstance(value, str) else json.dumps(value),
            capture_output=True, text=True,
        )

    def test_model_inventory_rejects_missing_routes(self):
        expected = ['model-a', 'model-b', 'model-c']
        self.assertNotEqual(self.checker('models', {'data': [{'id': 'model-a'}]}, *expected).returncode, 0)
        result = self.checker('models', {'data': [{'id': x} for x in expected]}, *expected)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.checker('models', {'data': [{'id': 'model-a'}]}).returncode, 0)

    def test_stream_reasoning_accepts_router_field_and_requires_correct_answer(self):
        def stream(reason, answer):
            return '\n'.join('data: ' + json.dumps({'choices': [{'delta': delta}]}) for delta in [
                {'reasoning': reason}, {'content': answer}]) + '\ndata: [DONE]\n'
        self.assertEqual(self.checker('reasoning', stream('fixture reasoning', '323'), 'require').returncode, 0)
        self.assertNotEqual(self.checker('reasoning', stream('', '323'), 'require').returncode, 0)
        self.assertEqual(self.checker('reasoning', stream('', '323')).returncode, 0)
        self.assertNotEqual(self.checker('reasoning', stream('fixture reasoning', '187')).returncode, 0)

    def test_vision_requires_the_observed_color_order(self):
        def response(text):
            return {'choices': [{'message': {'content': text}}]}
        self.assertEqual(self.checker('vision', response('Red Blue')).returncode, 0)
        self.assertNotEqual(self.checker('vision', response('Blue Red')).returncode, 0)

    def test_opencode_error_cannot_pass_with_ok_text(self):
        good = json.dumps({'type': 'text', 'part': {'text': 'OK'}})
        bad = good + '\n' + json.dumps({'type': 'error', 'error': {'message': 'fixture error'}})
        self.assertEqual(self.checker('opencode', good).returncode, 0)
        self.assertNotEqual(self.checker('opencode', bad).returncode, 0)

    def test_setup_is_repeatable_preserves_profile_and_works_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix='spark harness test ') as folder:
            base = Path(folder)
            profile = base / 'shell profile'
            profile.write_text('export USER_SETTING=preserved\n')
            binary = base / 'fake-opencode'
            binary.write_text('#!/bin/sh\nprintf "1.19.4\\n"\n')
            binary.chmod(0o755)
            env = {**os.environ, 'SPARK_INSTALL_DIR': str(base / 'installed harness'),
                   'SPARK_SHELL_RC': str(profile), 'SPARK_OPENCODE_BIN': str(binary),
                   'SPARK_ENDPOINT_FILE': str(base / 'no-endpoint.env')}
            env.pop('SPARK_BASE_URL', None)
            env.pop('SPARK_API_KEY', None)
            cmd = ['zsh', str(ROOT / 'setup.command'), '--skip-install', '--skip-token', '--skip-doctor']
            for _ in range(2):
                result = subprocess.run(cmd, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(profile.read_text().startswith('export USER_SETTING=preserved\n'))
            self.assertEqual(profile.read_text().count('# >>> spark-code >>>'), 1)
            shell = subprocess.run(['zsh', '-c', 'source "$1"; command -v spark-code', 'test', str(profile)],
                                   env=env, text=True, capture_output=True)
            self.assertEqual(Path(shell.stdout.strip()).resolve(), (base / 'installed harness/bin/spark-code').resolve())
            self.assertTrue(os.access(base / 'installed harness/bin/spark-code', os.X_OK))

    def test_setup_does_not_replace_unrelated_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            sentinel = base / 'personal-file'
            sentinel.write_text('keep')
            result = subprocess.run(['zsh', str(ROOT / 'setup.command'), '--skip-install', '--skip-token', '--skip-doctor'],
                                    env={**os.environ, 'SPARK_INSTALL_DIR': str(base),
                                         'SPARK_ENDPOINT_FILE': str(base / 'no-endpoint.env')},
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), 'keep')

    def test_api_authentication_and_private_error_redaction(self):
        calls = []
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                calls.append(self.headers.get('Authorization'))
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'Never echo a server response containing fixture-private-data')
            def log_message(self, *args):
                pass
        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = {**os.environ, 'SPARK_BASE_URL': f'http://127.0.0.1:{server.server_port}/v1'}
            script = 'source "$1/scripts/common.zsh"; SPARK_API_KEY=fixture-test-token; api_request models'
            result = subprocess.run(['zsh', '-c', script, 'test', str(ROOT)], env=env, capture_output=True, text=True)
            self.assertEqual(calls, ['Bearer fixture-test-token'])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('HTTP 401', result.stderr)
            self.assertNotIn('fixture-private-data', result.stdout + result.stderr)
            self.assertNotIn('fixture-test-token', result.stdout + result.stderr)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_gateway_address_is_required_and_has_no_default(self):
        with tempfile.TemporaryDirectory() as folder:
            env = {**os.environ, 'SPARK_ENDPOINT_FILE': str(Path(folder) / 'none.env')}
            env.pop('SPARK_BASE_URL', None)
            script = 'source "$1/scripts/common.zsh"; SPARK_API_KEY=fixture-test-token; api_request models'
            result = subprocess.run(['zsh', '-c', script, 'test', str(ROOT)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('SPARK_BASE_URL is not set', result.stderr)

    def test_endpoint_file_supplies_settings_and_environment_wins(self):
        with tempfile.TemporaryDirectory() as folder:
            endpoint = Path(folder) / 'endpoint.env'
            endpoint.write_text('SPARK_BASE_URL=http://gateway.example/v1\nSPARK_MODEL_CODER=file-coder\n'
                                'SPARK_API_KEY=must-be-ignored\nUNRELATED=ignored\n')
            env = {**os.environ, 'SPARK_ENDPOINT_FILE': str(endpoint), 'SPARK_MODEL_CODER': 'env-coder'}
            for name in ('SPARK_BASE_URL', 'SPARK_API_KEY', 'UNRELATED'):
                env.pop(name, None)
            script = 'source "$1/scripts/common.zsh"; print -r -- "$SPARK_BASE_URL|$SPARK_MODEL_CODER|${SPARK_API_KEY:-unset}|${UNRELATED:-unset}"'
            result = subprocess.run(['zsh', '-c', script, 'test', str(ROOT)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'http://gateway.example/v1|env-coder|unset|unset')

    def test_project_directory_overrides_stale_pwd(self):
        with tempfile.TemporaryDirectory(prefix='spark project ') as folder:
            base = Path(folder)
            binary = base / 'opencode'
            binary.write_text('#!/bin/sh\nprintf "1.19.4\\n"\n')
            binary.chmod(0o755)
            env = {**os.environ, 'SPARK_HARNESS_HOME': str(ROOT),
                   'SPARK_OPENCODE_BIN': str(binary), 'PWD': '/incorrect/stale/project'}
            script = 'source "$1/scripts/common.zsh"; prepare_opencode; print -r -- "$PWD"'
            result = subprocess.run(['zsh', '-c', script, 'test', str(ROOT)], env=env,
                                    cwd=base, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()).resolve(), base.resolve())


if __name__ == '__main__':
    unittest.main()
