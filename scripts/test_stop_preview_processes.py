"""Process cleanup must match known repository worktrees and the exact preview kind."""
from pathlib import Path
import importlib.util
import signal
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "preview_processes", Path(__file__).with_name("stop-preview-processes.py"))
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewProcessTests(unittest.TestCase):
    def test_launcher_collects_old_previews_across_repository_worktrees(self):
        root = Path('/workspace/Fralo')
        old = Path('/worktrees/previous/Fralo')
        suffix = '.build/workbench-preview/session-123/Fralo Workbench Preview.app/Contents/MacOS/FraloApp'
        paths = {1: str(root / suffix), 2: str(old / suffix),
                 3: '/Applications/Fralo.app/Contents/MacOS/FraloApp',
                 4: str(Path('/unrelated/Fralo') / suffix)}
        captured = {}
        def output(args, **kwargs):
            if args[0] == 'git': return f'worktree {root}\0HEAD abc\0\0worktree {old}\0HEAD def\0\0'
            return '1\n2\n3\n4\n'
        with patch.object(preview, 'ROOT', root), \
             patch.object(preview.subprocess, 'check_output', side_effect=output), \
             patch.object(preview, 'executable_reader', return_value=paths.get), \
             patch.object(preview, 'stop_previews', side_effect=lambda targets, read: captured.update(targets)), \
             patch.object(preview.sys, 'argv', ['stop-preview-processes.py', 'workbench']):
            preview.main()
        self.assertEqual(captured, {1: paths[1], 2: paths[2]}, 'Old same-repository worktree previews must also exit')

    def test_exact_workspace_and_kind(self):
        root = Path("/workspace/Fralo")
        path = root / ".build/workbench-preview/session-123/Fralo Workbench Preview.app/Contents/MacOS/FraloApp"
        self.assertTrue(preview.matches_preview(str(path), root, "workbench"))
        for candidate in [str(path).replace("/workspace/", "/other/"),
                          str(path).replace("session-123", "arbitrary"),
                          str(path).replace("FraloApp", "fralo"),
                          "/Applications/Fralo.app/Contents/MacOS/FraloApp"]:
            self.assertFalse(preview.matches_preview(candidate, root, "workbench"))
        self.assertFalse(preview.matches_preview(str(path), root, "design-lab"))

    def test_escalates_unresponsive_and_rechecks_reused_pid(self):
        paths = {1: "/old", 2: "/different"}
        sent = []
        now = [0.0]

        def send(pid, sig):
            sent.append((pid, sig))
            if sig == signal.SIGKILL:
                paths.pop(pid)

        def sleep(seconds):
            now[0] += seconds

        preview.stop_previews({1: "/old", 2: "/old"}, paths.get,
                              send, lambda: now[0], sleep)
        self.assertEqual(sent, [(1, signal.SIGTERM), (1, signal.SIGKILL)])

    def test_exited_process_needs_no_kill(self):
        sent = []
        paths = {1: "/old"}

        def send(pid, sig):
            sent.append(sig)
            paths.pop(pid)

        preview.stop_previews({1: "/old"}, paths.get, send)
        self.assertEqual(sent, [signal.SIGTERM])

    def test_failure_prevents_launch(self):
        now = [0.0]

        def sleep(seconds):
            now[0] += seconds

        with self.assertRaises(RuntimeError):
            preview.stop_previews({1: "/old"}, lambda pid: "/old",
                                  lambda pid, sig: None, lambda: now[0], sleep)


if __name__ == "__main__":
    unittest.main()
