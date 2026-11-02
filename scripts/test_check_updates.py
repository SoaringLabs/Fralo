"""Update availability must be evidence-based; failed checks must stay visible."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import check_updates as checks


class FakeClient:
    def __init__(self, responses):
        self.responses = responses

    def get(self, url, **kwargs):
        value = self.responses[url]
        if isinstance(value, Exception):
            raise value
        return value


class UpdateCheckTests(unittest.TestCase):
    def test_versions_compare_numerically_and_ignore_trailing_zeroes(self):
        self.assertEqual(checks.comparison("2.9.9", "v2.10.0"), "update")
        self.assertEqual(checks.comparison("6.4", "6.4.0"), "current")
        self.assertEqual(checks.comparison("7", "6.4"), "ahead")
        for value in ("6.5-beta", "6.5rc1", "6.5.dev1", "main", ""):
            self.assertFalse(checks.is_stable(value))

    def test_pypi_skips_prereleases_yanked_and_empty_releases(self):
        client = FakeClient({"https://pypi.org/pypi/example/json": {"releases": {
            "1.9": [{"yanked": False}], "1.10": [{"requires_python": ">=3.10"}],
            "2.0rc1": [{}], "2.0": [{"yanked": True}], "3.0": []}}})
        row = checks.check_python(client, "example", "1.9")
        self.assertEqual(row["latest"], "1.10")
        self.assertEqual(row["status"], "update")
        self.assertIn(">=3.10", row["note"])

    def test_pypi_post_releases_are_stable_updates(self):
        client = FakeClient({"https://pypi.org/pypi/example/json": {"releases": {
            "1.10": [{}], "1.10.post1": [{}], "1.11.dev1": [{}]}}})
        row = checks.check_python(client, "example", "1.10")
        self.assertEqual(row["latest"], "1.10.post1")
        self.assertEqual(row["status"], "update")
        self.assertGreater(checks.python_version("1!1.0"), checks.python_version("99.0"))

    def test_timeout_bad_json_and_rate_limit_are_explicit_errors(self):
        url = "https://api.github.com/repos/owner/repo/releases/latest"
        for failure in (TimeoutError(), HTTPError(url, 403, "Forbidden", {}, None)):
            with patch.object(checks, "urlopen", side_effect=failure):
                row = checks.checked("test", lambda: checks.Client(1).get(url))
            self.assertEqual(row["status"], "error")
        with patch.object(checks, "urlopen") as open_url:
            open_url.return_value.__enter__.return_value.read.return_value = b"not json"
            row = checks.checked("test", lambda: checks.Client(1).get(url))
        self.assertEqual(row["status"], "error")

    def test_github_rejects_preview_even_if_latest_endpoint_returns_it(self):
        for tag, prerelease in (("2.0", True), ("2.0-rc1", False)):
            client = FakeClient({"https://api.github.com/repos/owner/repo/releases/latest":
                                 dict(tag_name=tag, prerelease=prerelease, html_url="https://example.test")})
            with self.assertRaises(ValueError):
                checks.github_latest(client, "owner/repo")

    def test_action_uses_actual_commit_relationship(self):
        for upstream, expected in (("identical", "current"), ("behind", "update"),
                                   ("ahead", "ahead"), ("diverged", "review")):
            client = FakeClient({
                "https://api.github.com/repos/owner/action/releases/latest":
                    dict(tag_name="v2.0", html_url="https://example.test/v2.0"),
                "https://api.github.com/repos/owner/action/compare/v2.0...abc123?per_page=1":
                    dict(status=upstream)})
            self.assertEqual(checks.check_action(client, "owner/action", "abc123", ["ci.yml:5"])["status"], expected)

    def test_apple_ignores_beta_rc_and_future_publication(self):
        client = FakeClient({checks.APPLE_RELEASES: """<rss><channel>
            <item><title>Xcode 99 beta (abc)</title></item>
            <item><title>Xcode 98 RC (abc)</title></item>
            <item><title>Xcode 97 (abc)</title><pubDate>Tue, 01 Jan 2099 00:00:00 GMT</pubDate></item>
            <item><title>Xcode 26.3 (abc)</title><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate><link>https://example.test/26.3</link></item>
            <item><title>Xcode 26.2 (def)</title><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item>
            </channel></rss>"""})
        self.assertEqual(checks.apple_latest(client), ("26.3", "https://example.test/26.3"))

    def test_sdk_matches_stable_xcode_instead_of_newer_beta_table_row(self):
        client = FakeClient({checks.XCODE_SUPPORT: """<table>
            <tr><td>Xcode 27 beta</td><td>macOS 26</td><td>macOS 27</td></tr>
            <tr><td>Xcode 26.3</td><td>macOS 15</td><td>iOS 26.2<br>macOS 26.2</td></tr>
            </table>"""})
        self.assertEqual(checks.apple_sdk(client, "26.3"), "26.2")
        with self.assertRaises(ValueError):
            checks.apple_sdk(client, "25")

    def test_swift_compiler_is_compared_separately_from_language_mode(self):
        client = FakeClient({checks.SWIFT_RELEASES: [
            dict(name="6.4.0", tag="swift-6.4.0-RELEASE", date="2024-01-01"),
            dict(name="6.4.1", tag="swift-6.4.1-RELEASE", date="2024-02-01"),
            dict(name="7.0", tag="swift-7.0-DEVELOPMENT-SNAPSHOT", date="2024-03-01"),
            dict(name="8.0", tag="swift-8.0-RELEASE", date="2099-01-01")]})
        with patch.object(checks, "command", return_value="Apple Swift version 6.4 (swiftlang-build)"):
            row = checks.check_swift(client)
        self.assertEqual(row["latest"], "6.4.1")
        self.assertEqual(row["status"], "update")

    def fixture(self, root):
        (root / "scripts").mkdir()
        (root / ".github/workflows").mkdir(parents=True)
        (root / "Package.swift").write_text('''// swift-tools-version: 5.10
            platforms: [.macOS(.v14)],
            dependencies: [.package(url: "https://github.com/owner/pkg", exact: "1.0")]
        ''')
        (root / "Package.resolved").write_text(json.dumps({"pins": [
            dict(identity="pkg", location="https://github.com/owner/pkg.git", state=dict(version="1.0"))]}))
        (root / "scripts/requirements-dmg.txt").write_text("# build only\nexample==1.0\n")
        (root / ".github/workflows/ci.yml").write_text('''steps:
            - uses: "owner/action@abc123" # v999 (untrusted comment)
            - uses: ./local/action
            - run: sudo xcode-select -s /Applications/Xcode_26.3.app/Contents/Developer
        ''')

    def test_inventory_reads_project_pins_and_ci_without_executing_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            context, pins, requirements, actions, ci = checks.inventory(root)
        self.assertEqual(context["swift_tools_version"], "5.10")
        self.assertIn("默认 Swift 5", context["swift_language_mode"])
        self.assertEqual(context["minimum_macos"], "14")
        self.assertEqual(pins[0]["state"]["version"], "1.0")
        self.assertEqual(requirements, [("example", "1.0")])
        self.assertEqual(list(actions), [("owner/action", "abc123")])
        self.assertEqual(list(ci), ["26.3"])

    def test_mismatched_lockfile_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            path = root / "Package.resolved"
            path.write_text(path.read_text().replace('"1.0"', '"0.9"'))
            with self.assertRaisesRegex(ValueError, "不一致"):
                checks.inventory(root)

    def test_partial_network_failure_keeps_other_results_and_incomplete_status(self):
        inventory = ({}, [dict(identity="pkg")], [], {}, {})
        with patch.object(checks, "inventory", return_value=inventory), \
             patch.object(checks, "check_package", return_value=dict(name="pkg", status="update")), \
             patch.object(checks, "check_swift", side_effect=ValueError("network unavailable")), \
             patch.object(checks, "check_xcode", return_value=[dict(name="Xcode", status="current")]):
            report = checks.report(Path("."), None)
        self.assertFalse(report["complete"])
        self.assertEqual(report["summary"]["update"], 1)
        self.assertEqual(report["summary"]["error"], 1)
        self.assertEqual(len(report["checks"]), 3)

    def test_exit_code_is_nonzero_for_incomplete_report_but_not_available_updates(self):
        for complete, expected in ((True, 0), (False, 2)):
            output = io.StringIO()
            with patch.object(checks, "report", return_value=dict(complete=complete)), redirect_stdout(output):
                self.assertEqual(checks.main(["--json"]), expected)
            self.assertEqual(json.loads(output.getvalue())["complete"], complete)

    def test_inventory_errors_are_valid_json_and_nonzero(self):
        output = io.StringIO()
        with patch.object(checks, "inventory", side_effect=ValueError("bad lockfile")), redirect_stdout(output):
            self.assertEqual(checks.main(["--json"]), 2)
        self.assertEqual(json.loads(output.getvalue()), dict(complete=False, error="bad lockfile"))

    def test_github_urls_handle_git_suffix(self):
        for suffix in ("", ".git", "/"):
            self.assertEqual(checks.github_repo("https://github.com/owner/pkg" + suffix), "owner/pkg")
        with self.assertRaises(ValueError):
            checks.github_repo("https://example.test/owner/pkg")


if __name__ == "__main__":
    unittest.main()
