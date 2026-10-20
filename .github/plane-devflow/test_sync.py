"""Offline regression checks against this repository's vendored sync bundle."""
import base64
import copy
import json
import os
import subprocess
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch
from urllib.parse import parse_qs, urlsplit

import action_runner as runner
import plane_sync as sync

ROOT = Path(__file__).resolve().parents[2]


class MemoryPlane:
    def __init__(self, config, group="started"):
        self.item = {
            "id": "10000000-0000-4000-8000-000000000099",
            "project_id": config["plane"]["project_id"],
            "state_id": config["states"].get("in_progress", "10000000-0000-4000-8000-000000000098"),
            "state": {"group": group}, "labels": [],
        }
        self.updates = []
        self.comments = {}

    def work_item(self, task):
        return copy.deepcopy(self.item)

    def update_state(self, item, state_id):
        self.updates.append(state_id)
        self.item["state_id"] = state_id

    def upsert_comment(self, item, external_id, comment_html):
        self.comments[external_id] = comment_html


class VendoredSyncTests(unittest.TestCase):
    def setUp(self):
        self.config = sync.validate_config(json.loads((ROOT / ".plane-devflow.json").read_text()))
        network = patch("urllib.request.OpenerDirector.open", side_effect=AssertionError("Live HTTP is forbidden in this test suite"))
        network.start()
        self.addCleanup(network.stop)

    def event(self, **changes):
        cfg = self.config
        repo = cfg["github"]["repository"]
        task = cfg["plane"]["project_identifier"] + "-999999901"
        pr = {
            "number": 999999901, "html_url": f"https://github.com/{repo}/pull/999999901",
            "title": "Offline synchronization fixture", "state": "open", "draft": False,
            "merged": False, "body": "<!-- plane-devflow " + json.dumps(sync.binding(cfg, task)) + " -->",
            "base": {"ref": cfg["github"]["base_branch"], "sha": "a" * 40, "repo": {"full_name": repo}},
            "head": {"sha": "b" * 40},
        }
        pr.update(changes)
        return {"action": "opened", "repository": {"full_name": repo, "default_branch": cfg["github"]["base_branch"]}, "pull_request": pr}

    def test_repository_retains_actions_and_manual_completion(self):
        self.assertEqual(sync.sync_provider(self.config), "actions")
        self.assertEqual(self.config["completion"]["policy"], "manual")

    def test_configuration_rejects_embedded_credentials(self):
        cfg = copy.deepcopy(self.config)
        cfg["plane"]["api_key"] = "synthetic-secret-sentinel"
        with self.assertRaises(sync.WorkflowError):
            sync.validate_config(cfg)

    def test_private_artifacts_remain_ignored(self):
        for path in [".plane-devflow.local/probe", ".plane-for-codex.local/probe", ".github/plane-devflow/__pycache__/probe.pyc"]:
            result = subprocess.run(["git", "check-ignore", "--quiet", path], cwd=ROOT)
            self.assertEqual(result.returncode, 0, path)

    def test_unbound_migration_pr_skips_without_constructing_a_client(self):
        event = self.event(title="Migrate Plane integration", body="No business task is bound.")
        with patch.object(runner, "github_snapshot", return_value=event), patch.object(runner, "fetch_config", return_value=self.config), patch.object(runner, "PlaneClient") as client:
            result = runner.run_action(event, self.config["github"]["repository"], "test-token", None)
        self.assertEqual(result, {"status": "skipped", "reason": "no_primary_task"})
        client.assert_not_called()

    def test_other_repository_is_rejected_before_network(self):
        with patch.object(runner, "github_snapshot") as network:
            with self.assertRaises(sync.WorkflowError):
                runner.run_action(self.event(), "example/wrong-repository", "test-token", "test-key")
        network.assert_not_called()

    def test_other_project_binding_is_rejected(self):
        record = sync.binding(self.config, self.config["plane"]["project_identifier"] + "-999999901")
        record["project_id"] = "20000000-0000-4000-8000-000000000001"
        with self.assertRaises(sync.WorkflowError):
            sync.sync_event(self.event(body="<!-- plane-devflow " + json.dumps(record) + " -->"), self.config, dry_run=True)

    def test_trusted_config_uses_explicit_base_commit_not_pr_head(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            "type": "file", "encoding": "base64", "content": base64.b64encode(json.dumps(self.config).encode()).decode()
        }).encode()
        opener = MagicMock()
        opener.open.return_value = response
        with patch.dict(os.environ, {"PLANE_CONFIG_SHA": "c" * 40}), patch.object(runner, "build_opener", return_value=opener):
            self.assertEqual(runner.fetch_config(self.event(), "test-token"), self.config)
        url = opener.open.call_args.args[0].full_url
        self.assertEqual(parse_qs(urlsplit(url).query), {"ref": ["c" * 40]})
        self.assertTrue(urlsplit(url).path.endswith("/.plane-devflow.json"))
        self.assertNotIn("test-token", url)

    def test_latest_closed_pr_state_prevents_stale_review_transition(self):
        current = self.event(state="closed", merged=False)
        client = MemoryPlane(self.config)
        with patch.object(runner, "github_snapshot", return_value=current), patch.object(runner, "fetch_config", return_value=self.config), patch.object(runner, "PlaneClient", return_value=client):
            result = runner.run_action(self.event(), self.config["github"]["repository"], "test-token", "test-key")
        self.assertEqual(result["phase"], "closed")
        self.assertEqual(client.updates, [])

    def test_merge_keeps_manual_acceptance_separate_from_done(self):
        client = MemoryPlane(self.config)
        result = sync.sync_event(self.event(merged=True, state="closed"), self.config, client)
        self.assertTrue(result["manual_acceptance"])
        self.assertNotIn(self.config["states"].get("done"), client.updates)
        if sync.state_sync_enabled(self.config):
            self.assertEqual(client.updates, [self.config["states"]["in_review"]])
        else:
            self.assertEqual(client.updates, [])

    def test_disabled_state_sync_never_updates_a_task_state(self):
        cfg = copy.deepcopy(self.config)
        cfg.update(version=2, states={}, status_sync={"enabled": False})
        client = MemoryPlane(cfg)
        result = sync.sync_event(self.event(merged=True, state="closed"), cfg, client)
        self.assertFalse(result["state_changed"])
        self.assertEqual(client.updates, [])
        self.assertEqual(len(client.comments), 1)

    def test_terminal_tasks_do_not_regress(self):
        for group in ["completed", "cancelled"]:
            with self.subTest(group=group):
                client = MemoryPlane(self.config, group)
                sync.sync_event(self.event(draft=True), self.config, client)
                self.assertEqual(client.updates, [])

    def test_repeated_event_upserts_one_lifecycle_comment(self):
        client = MemoryPlane(self.config)
        sync.sync_event(self.event(), self.config, client)
        sync.sync_event(self.event(), self.config, client)
        self.assertEqual(len(client.comments), 1)

    def test_legacy_bracketed_title_still_identifies_the_same_task(self):
        task = self.config["plane"]["project_identifier"] + "-999999901"
        old_body = "<!-- plane-for-codex " + json.dumps(sync.binding(self.config, task)) + " -->"
        self.assertEqual(sync.pr_task(self.event(title=f"[{task}] Existing task", body=old_body)["pull_request"], self.config), task)

    def test_dry_run_performs_no_plane_calls(self):
        client = MagicMock()
        result = sync.sync_event(self.event(), self.config, client, dry_run=True)
        self.assertEqual(result["status"], "planned")
        self.assertEqual(client.mock_calls, [])

    def test_connection_check_only_reads_the_existing_project(self):
        event = self.event()
        event["ref"] = "refs/heads/" + self.config["github"]["base_branch"]
        client = MagicMock()
        client.workspace_path.return_value = "/fixture/"
        client.request.side_effect = [{"id": self.config["plane"]["project_id"], "archived_at": None}, [{"id": state} for state in self.config["states"].values()]]
        with patch.dict(os.environ, {"PLANE_CONFIG_SHA": "c" * 40}), patch.object(runner, "fetch_config", return_value=self.config), patch.object(runner, "PlaneClient", return_value=client):
            result = runner.check_connection(event, self.config["github"]["repository"], "test-token", "test-key")
        self.assertFalse(result["writes_performed"])
        self.assertTrue(all(call.args[0] == "GET" for call in client.request.call_args_list))

    def test_privileged_workflow_checks_out_only_trusted_base(self):
        text = (ROOT / ".github/workflows/plane-devflow.yml").read_text()
        self.assertIn("pull_request_target:", text)
        self.assertIn("ref: ${{ github.sha }}", text)
        self.assertIn("persist-credentials: false", text)
        self.assertNotIn("github.event.pull_request.head", text)
        self.assertNotIn("${{ github.head_ref }}", text)
        self.assertIn("run: python3 .github/plane-devflow/action_runner.py", text)


if __name__ == "__main__":
    unittest.main()
