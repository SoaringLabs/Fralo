"""Exercise the installer in a temporary HOME/bin with isolated macOS/network adapters.

The production script keeps absolute system-tool paths. Tests redirect only those
OS boundaries; the installer, generated launcher, filesystem operations and shell
command lookup run normally. No real app, command directory or shell profile changes.
"""
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/install.sh"
TOOLS = ("/usr/bin/uname", "/usr/bin/sw_vers", "/usr/bin/codesign",
         "/usr/sbin/spctl", "/usr/bin/curl", "/usr/bin/hdiutil",
         "/usr/bin/ditto", "/usr/bin/plutil", "/usr/bin/sudo")
ADAPTER = r'''
import hashlib, json, os, pathlib, plistlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TOOL_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'uname':
    print('Darwin' if args == ['-s'] else 'arm64')
elif name == 'sw_vers':
    print('14.0')
elif name in ('codesign', 'spctl'):
    if name == 'codesign' and os.environ.get('RACE_LAUNCHER'):
        dest = pathlib.Path(os.environ['INSTALL_BIN'], 'fralo')
        if not os.path.lexists(dest):
            kind = os.environ['RACE_LAUNCHER']
            if kind == 'directory':
                dest.mkdir()
            elif kind == 'symlink':
                target = dest.parent / 'unrelated'
                target.mkdir(exist_ok=True)
                dest.symlink_to(target, target_is_directory=True)
            else:
                dest.write_text('arrived during installation')
    sys.exit(1 if os.environ.get('REJECT_TOOL') == name else 0)
elif name == 'plutil':
    key = args[args.index('-extract') + 1]
    if args[-1] == '-':
        print(json.load(sys.stdin)[key])
    else:
        with open(args[-1], 'rb') as f:
            print(plistlib.load(f)[key])
elif name == 'curl':
    if os.environ.get('REJECT_DOWNLOAD'):
        sys.exit(22)
    url = args[-1]
    if url.endswith('/latest'):
        print(json.dumps({'tag_name': 'v0.3.1'}))
    else:
        out = pathlib.Path(args[args.index('-o') + 1])
        data = b'official-test-dmg'
        if url.endswith('SHA256SUMS.txt'):
            checksum = '0' * 64 if os.environ.get('BAD_CHECKSUM') else hashlib.sha256(data).hexdigest()
            data = (checksum + '  Fralo-0.3.1-arm64.dmg\n').encode()
        out.write_bytes(data)
elif name == 'hdiutil':
    if args[0] == 'attach':
        mount = pathlib.Path(args[args.index('-mountpoint') + 1])
        shutil.copytree(os.environ['FIXTURE_APP'], mount / 'Fralo.app', symlinks=True)
elif name == 'ditto':
    shutil.copytree(args[0], args[1], symlinks=True)
elif name == 'sudo':
    if os.environ.get('DENY_SUDO'):
        sys.exit(1)
    if args != ['-v']:
        # Simulate elevation only inside the test-owned command directory.
        pathlib.Path(os.environ['INSTALL_BIN']).chmod(0o755)
        sys.exit(subprocess.call(args))
else:
    raise AssertionError(name)
'''
CLI = r'''
import json, os, signal, sys, time
if sys.argv[1:] == ['--version']:
    print('fralo 0.3.1')
elif sys.argv[1:] == ['--wait']:
    signal.signal(signal.SIGINT, lambda *_: sys.exit(130))
    print(os.getpid(), flush=True)
    time.sleep(60)
elif sys.argv[1:2] == ['--exit']:
    sys.exit(int(sys.argv[2]))
else:
    print(json.dumps(sys.argv[1:]))
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fralo-installer-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home with 空格 ' $value"
        self.home.mkdir()
        self.bin = self.root / 'command bin'
        self.bin.mkdir()
        self.app = self.home / 'Applications/Fralo.app'
        self.fixture = self.root / 'fixture/Fralo.app'
        self.make_app(self.fixture)
        self.launcher = self.bin / 'fralo'
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.script = self.root / 'install.sh'
        self.log = self.root / 'tools.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.root),
                        PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin',
                        FIXTURE_APP=str(self.fixture), TOOL_LOG=str(self.log),
                        INSTALL_BIN=str(self.bin))
        for tool in TOOLS:
            self.executable(self.tools / Path(tool).name, ADAPTER)
        text = SCRIPT.read_text().replace('bin_dir=/usr/local/bin',
                                          'bin_dir=' + shlex.quote(str(self.bin)))
        for tool in TOOLS:
            text = text.replace(tool, shlex.quote(str(self.tools / Path(tool).name)))
        self.script.write_text(text)

    def executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f'#!{sys.executable}\n' + body)
        path.chmod(0o755)

    def make_app(self, path):
        self.executable(path / 'Contents/MacOS/fralo', CLI)
        with (path / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleShortVersionString': '0.3.1'}, f)

    def install(self, *args, code=0, env=None):
        # Match the public bootstrap, which executes the downloaded script with -c.
        result = subprocess.run(['/bin/bash', '-c', self.script.read_text(), 'fralo-install', *args], env=env or self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def command(self, *args, code=0):
        result = subprocess.run(['fralo', *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_fresh_install_is_callable_without_changing_profiles(self):
        profile = self.home / '.zshrc'
        profile.write_text('# user settings\n')
        result = self.install()
        self.assertEqual(result.stdout, str(self.app / 'Contents/MacOS/fralo') + '\n')
        self.assertIn('Ready: fralo --help', result.stderr)
        self.assertFalse(self.launcher.is_symlink())
        self.assertEqual(self.command('--version').stdout, 'fralo 0.3.1\n')
        self.assertEqual(profile.read_text(), '# user settings\n')
        self.assertFalse(list(self.bin.glob('.fralo-cli.*')))
        self.assertFalse(list(self.root.glob('fralo-install.*')))
        names = [c[0] for c in self.calls()]
        self.assertIn('curl', names)
        self.assertIn('codesign', names)
        self.assertIn('spctl', names)
        self.assertNotIn('sudo', names)

    def test_existing_app_repairs_command_and_repeat_is_idempotent(self):
        self.make_app(self.app)
        before = (self.app / 'Contents/MacOS/fralo').read_bytes()
        self.install()
        inode = self.launcher.stat().st_ino
        self.install()
        self.assertEqual(self.launcher.stat().st_ino, inode)
        self.assertEqual((self.app / 'Contents/MacOS/fralo').read_bytes(), before)
        self.assertNotIn('curl', [c[0] for c in self.calls()])

    def test_argument_bytes_exit_code_and_exec_signal_delivery(self):
        self.install()
        arguments = ['compose', "input 空格 ' $x.png", '--output', 'two words', '', '*']
        self.assertEqual(json.loads(self.command(*arguments).stdout), arguments)
        self.command('--exit', '37', code=37)
        with subprocess.Popen(['fralo', '--wait'], env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) as proc:
            self.assertEqual(int(proc.stdout.readline()), proc.pid, 'launcher must exec the CLI')
            proc.send_signal(signal.SIGINT)
            proc.communicate(timeout=10)
            self.assertEqual(proc.returncode, 130)

    def test_custom_bin_directory_already_on_path(self):
        other = self.root / 'custom bin'
        env = dict(self.env, PATH=f'{other}:' + self.env['PATH'])
        self.install('--bin-dir', str(other), env=env)
        self.assertTrue((other / 'fralo').is_file())
        self.assertFalse(self.launcher.exists())

    def test_missing_path_fails_before_download_or_app_install(self):
        result = self.install(code=1, env=dict(self.env, PATH='/usr/bin:/bin'))
        self.assertIn('not on PATH', result.stderr)
        self.assertFalse(self.app.exists())
        self.assertFalse(self.launcher.exists())
        self.assertNotIn('curl', [c[0] for c in self.calls()])

    def test_existing_file_and_dangling_symlink_are_not_overwritten(self):
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                if symlink:
                    self.launcher.symlink_to(self.root / 'missing')
                else:
                    self.launcher.write_text('another tool')
                result = self.install(code=1)
                self.assertIn('Refusing to overwrite', result.stderr)
                self.assertFalse(self.app.exists())
                if not symlink:
                    self.assertEqual(self.launcher.read_text(), 'another tool')
                self.launcher.unlink()

    def test_other_command_on_path_is_not_silently_shadowed(self):
        other = self.root / 'other'
        self.executable(other / 'fralo', "print('another command')\n")
        result = self.install(code=1, env=dict(self.env, PATH=f'{other}:' + self.env['PATH']))
        self.assertIn('Another fralo command', result.stderr)
        self.assertFalse(self.launcher.exists())

    def test_signature_gate_and_pinned_version_apply_to_existing_apps(self):
        self.make_app(self.app)
        self.install(code=1, env=dict(self.env, REJECT_TOOL='codesign'))
        self.assertFalse(self.launcher.exists())
        result = self.install('--version', '0.3.2', code=1)
        self.assertIn('Expected Fralo 0.3.2, found 0.3.1', result.stderr)
        self.assertFalse(self.launcher.exists())

    def test_command_created_during_installation_is_preserved(self):
        for kind in ('file', 'directory', 'symlink'):
            with self.subTest(kind=kind):
                result = self.install(code=1, env=dict(self.env, RACE_LAUNCHER=kind))
                self.assertIn('Could not install', result.stderr)
                if kind == 'file':
                    self.assertEqual(self.launcher.read_text(), 'arrived during installation')
                else:
                    self.assertEqual(list(self.launcher.iterdir()), [])
                self.assertTrue(self.app.exists(), 'verified app stays available for recovery')
                self.assertFalse(list(self.bin.glob('.fralo-cli.*')))
                if kind == 'directory':
                    self.launcher.rmdir()
                else:
                    self.launcher.unlink()

    def test_download_checksum_and_gatekeeper_fail_without_publishing(self):
        for failure in ({'REJECT_DOWNLOAD': '1'}, {'BAD_CHECKSUM': '1'}, {'REJECT_TOOL': 'spctl'}):
            with self.subTest(failure=failure):
                self.install(code=1, env=dict(self.env, **failure))
                self.assertFalse(self.launcher.exists())
                self.assertFalse(self.app.exists())
                self.assertFalse(list(self.root.glob('fralo-install.*')))

    @unittest.skipIf(os.geteuid() == 0, 'permission check requires an unprivileged user')
    def test_permission_denial_and_elevated_launcher_publication(self):
        self.bin.chmod(0o555)
        self.addCleanup(self.bin.chmod, 0o755)
        self.install(code=1, env=dict(self.env, DENY_SUDO='1'))
        self.assertFalse(self.app.exists())
        self.assertFalse(self.launcher.exists())
        self.install()
        self.command('--version')
        sudo_calls = [c for c in self.calls() if c[0] == 'sudo']
        self.assertIn(['sudo', '-v'], sudo_calls)
        self.assertTrue(any(c[1:3] == ['/bin/bash', '-c'] for c in sudo_calls))

    def test_same_path_app_update_and_missing_app_error(self):
        self.install()
        binary = self.app / 'Contents/MacOS/fralo'
        binary.write_text(binary.read_text().replace('0.3.1', '0.3.2'))
        self.assertEqual(self.command('--version').stdout, 'fralo 0.3.2\n')
        shutil.rmtree(self.app)
        result = self.command('--version', code=127)
        self.assertIn('Reinstall Fralo', result.stderr)

    def test_uninstall_only_owns_exact_launcher_and_preserves_app(self):
        self.install()
        self.install('--uninstall-cli')
        self.assertFalse(self.launcher.exists())
        self.assertTrue(self.app.exists())
        self.install('--uninstall-cli')
        self.launcher.write_text('unrelated command')
        result = self.install('--uninstall-cli', code=1)
        self.assertIn('Refusing to remove', result.stderr)
        self.assertEqual(self.launcher.read_text(), 'unrelated command')

    def test_invalid_arguments_fail_without_installing(self):
        for args in (('--bin-dir',), ('--bin-dir', 'relative'), ('--bin-dir', '/'),
                     ('--version', 'nightly'), ('--uninstall-cli', '--version', '0.3.1')):
            with self.subTest(args=args):
                self.install(*args, code=1)
                self.assertFalse(self.app.exists())


if __name__ == '__main__':
    unittest.main()
