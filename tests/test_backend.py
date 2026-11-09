"""Fast boundary tests: no model downloads, GPU, microphone or third-party imports."""
import contextlib
import io
import json
import subprocess
import sys
import unittest
from pathlib import Path

from backend.guard import clean_output, guard
from backend.models import ROOT, WHISPER_PATH
from backend.server import serve

PROJECT = Path(__file__).resolve().parents[1]


class FakeASR:
    def load(self, glossary, language, engine):
        self.language = language

    def transcribe(self, path, language):
        if path == 'missing.wav':
            raise FileNotFoundError(path)
        return f'{language}: {path}'


class FakeLLM:
    def correct(self, text, context, language):
        return text.capitalize()


class BackendTests(unittest.TestCase):
    def exchange(self, kind, messages, engine):
        output = io.StringIO()
        source = io.StringIO('\n'.join(json.dumps(m) for m in messages))
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            serve(kind, source, engine)
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_model_paths_resolve_from_project_not_working_directory(self):
        self.assertEqual(ROOT, PROJECT)
        self.assertEqual(WHISPER_PATH.parent, PROJECT / 'models' / 'coreml')

    def test_guard_accepts_punctuation_and_rejects_model_answer(self):
        self.assertTrue(guard('открой терминал', 'Открой терминал.')[0])
        self.assertFalse(guard('открой терминал', 'Конечно! Вот исправленный текст:')[0])
        self.assertFalse(guard('открой терминал', '')[0])
        self.assertFalse(guard('открой терминал', 'Сегодня совсем другая погода.')[0])
        self.assertEqual(clean_output('<think>reason</think><text>Привет.</text>'), 'Привет.')

    def test_asr_load_and_request_ids(self):
        result = self.exchange('asr', [
            {'id': 0, 'cmd': 'load', 'language': 'ru'},
            {'id': 42, 'cmd': 'transcribe', 'path': 'clip.wav', 'language': 'ru'},
            {'cmd': 'quit'},
        ], FakeASR())
        self.assertEqual(result[0]['event'], 'started')
        self.assertEqual(result[1]['event'], 'ready')
        self.assertEqual(result[2]['id'], 42)
        self.assertEqual(result[2]['text'], 'ru: clip.wav')
        self.assertTrue(result[2]['ok'])
        self.assertIsInstance(result[2]['ms'], int)

    def test_error_does_not_stop_next_request(self):
        result = self.exchange('asr', [
            {'id': 1, 'cmd': 'transcribe', 'path': 'missing.wav'},
            {'id': 2, 'cmd': 'transcribe', 'path': 'valid.wav'},
        ], FakeASR())
        self.assertFalse(result[1]['ok'])
        self.assertEqual(result[1]['id'], 1)
        self.assertTrue(result[2]['ok'])

    def test_llm_and_wrong_worker_command(self):
        result = self.exchange('llm', [
            {'id': 1, 'cmd': 'correct', 'text': 'hello'},
            {'id': 2, 'cmd': 'transcribe', 'path': 'clip.wav'},
        ], FakeLLM())
        self.assertEqual(result[1]['text'], 'Hello')
        self.assertFalse(result[2]['ok'])

    def test_nonobject_message_and_unknown_command(self):
        result = self.exchange('asr', [[], {'id': 3, 'cmd': 'unknown'}], FakeASR())
        self.assertFalse(result[1]['ok'])
        self.assertEqual(result[2]['id'], 3)
        self.assertFalse(result[2]['ok'])

    def test_both_launchers_preserve_json_stdout(self):
        for launcher in (['backend.py'], ['-m', 'backend']):
            for kind in ('asr', 'llm'):
                with self.subTest(launcher=launcher, kind=kind):
                    process = subprocess.run(
                        [sys.executable, *launcher, kind], cwd=PROJECT,
                        input='malformed json\n{"cmd":"quit"}\n',
                        capture_output=True, text=True, timeout=10, check=True)
                    messages = [json.loads(line) for line in process.stdout.splitlines()]
                    self.assertEqual(len(messages), 1)
                    self.assertEqual(messages[0]['event'], 'started')


if __name__ == '__main__':
    unittest.main()
