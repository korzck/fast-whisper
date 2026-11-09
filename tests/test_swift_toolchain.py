"""Regression tests for toolchain selection, without needing multiple Xcode installs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class SwiftToolchainTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fast-whisper toolchain ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / 'project'
        shutil.copytree(PROJECT / 'scripts', self.project / 'scripts')
        self.commands = self.root / 'commands'
        self.commands.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.selected = self.root / 'Selected Developer'
        self.install_tools(self.selected)
        self.env = dict(os.environ, PATH=f'{self.commands}:/usr/bin:/bin:/usr/sbin:/sbin',
                        HOME=str(self.home), MOCK_SELECTED=str(self.selected))
        for name in ('DEVELOPER_DIR', 'SDKROOT', 'TOOLCHAINS'):
            self.env.pop(name, None)
        self.executable(self.commands / 'xcode-select', 'import os\nprint(os.environ["MOCK_SELECTED"])')
        self.executable(self.commands / 'swiftc', 'raise SystemExit("Unexpected PATH compiler")')
        self.executable(self.commands / 'xcrun', '''import os, sys
from pathlib import Path
dev = Path(os.environ['DEVELOPER_DIR'])
platform = dev / 'Platforms/MacOSX.platform'
if '--find' in sys.argv:
    print(dev / 'Toolchains/Test.xctoolchain/usr/bin/swiftc')
elif '--show-sdk-path' in sys.argv:
    print(platform / 'Developer/SDKs/MacOSX.sdk')
elif '--show-sdk-platform-path' in sys.argv:
    print(platform)
elif '--show-sdk-version' in sys.argv:
    print('27.0')
else:
    raise SystemExit(1)
''')

    def executable(self, path, source):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'#!{sys.executable}\n{source}\n')
        path.chmod(0o755)

    def install_tools(self, developer, plugins=True):
        compiler = developer / 'Toolchains/Test.xctoolchain/usr/bin/swiftc'
        self.executable(compiler, '''import json, os, sys
if '--version' in sys.argv:
    print('Apple Swift version ' + os.environ.get('MOCK_VERSION', '6.4'))
elif os.environ.get('MOCK_FAIL_ALL') or os.environ['DEVELOPER_DIR'] == os.environ.get('MOCK_FAIL_DEVELOPER'):
    print("external macro implementation type not found: incompatible SDK", file=sys.stderr)
    raise SystemExit(1)
else:
    print(json.dumps(sys.argv[1:]))
''')
        self.executable(compiler.parent / 'swift-plugin-server', 'pass')
        platform = developer / 'Platforms/MacOSX.platform'
        (platform / 'Developer/SDKs/MacOSX.sdk').mkdir(parents=True)
        if plugins:
            directory = platform / 'Developer/usr/lib/swift/host/plugins'
            directory.mkdir(parents=True)
            (directory / 'libSwiftUIMacros.dylib').touch()

    def check(self, *args):
        return subprocess.run(['/bin/bash', 'scripts/check_swift.sh', *args],
                              cwd=self.project, env=self.env, capture_output=True,
                              text=True, timeout=10)

    def test_platform_macro_path_and_compiler_from_same_install(self):
        process = self.check()
        self.assertEqual(process.returncode, 0, process.stderr)
        log = (self.project / 'build/swift-toolchain.log').read_text()
        argv = json.loads(next(line for line in log.splitlines() if line.startswith('[')))
        plugin = argv[argv.index('-external-plugin-path') + 1]
        self.assertIn('MacOSX.platform/Developer/usr/lib/swift/host/plugins#', plugin)
        self.assertIn('Test.xctoolchain/usr/bin/swift-plugin-server', plugin)
        self.assertIn(str(self.selected), process.stdout)
        self.assertIn('-typecheck', argv)

    def test_older_tools_work_without_extra_plugin_directories(self):
        shutil.rmtree(self.selected)
        self.install_tools(self.selected, plugins=False)
        process = self.check()
        self.assertEqual(process.returncode, 0, process.stderr)

    def test_automatic_fallback_to_installed_xcode(self):
        fallback = self.home / 'Applications/Xcode Test.app/Contents/Developer'
        self.install_tools(fallback)
        self.env['MOCK_FAIL_DEVELOPER'] = str(self.selected)
        process = self.check()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn(f'Using compatible Xcode: {fallback}', process.stdout)

    def test_explicit_developer_directory_is_not_silently_overridden(self):
        self.install_tools(self.home / 'Applications/Xcode Test.app/Contents/Developer')
        self.env.update(DEVELOPER_DIR=str(self.selected), MOCK_FAIL_ALL='1')
        process = self.check()
        self.assertNotEqual(process.returncode, 0)
        self.assertIn('SwiftUI toolchain preflight failed', process.stderr)
        self.assertIn('external macro implementation', process.stderr)
        self.assertNotIn('Using compatible Xcode', process.stdout)

    def test_stamp_stable_until_toolchain_version_changes(self):
        process = self.check('--stamp')
        self.assertEqual(process.returncode, 0, process.stderr)
        stamp = self.project / 'build/swift-toolchain.stamp'
        initial_time, initial_value = stamp.stat().st_mtime_ns, stamp.read_text()
        self.assertEqual(self.check('--stamp').returncode, 0)
        self.assertEqual(stamp.stat().st_mtime_ns, initial_time)
        self.env['MOCK_VERSION'] = '6.5'
        self.assertEqual(self.check('--stamp').returncode, 0)
        self.assertNotEqual(stamp.read_text(), initial_value)

    def test_app_and_probe_do_not_require_state_macro(self):
        import re
        for path in [*PROJECT.glob('Sources/**/*.swift'), PROJECT / 'scripts/probes/SwiftUIState.swift']:
            self.assertIsNone(re.search(r'@State\b', path.read_text()), str(path))
