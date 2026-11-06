"""Release preparation must reject missing translations, stale files and stale review."""
import copy
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from release_notes import (HEADINGS, LANGUAGES, check_all, check_release, content_digest,
                           generated_files, render_notes, validate_source)


def example_source(version="9.9.9"):
    return {
        "version": version,
        "summary": dict(zip(LANGUAGES, ("Export improvements.", "导出改进。", "匯出改進。", "書き出しの改善。"))),
        "changes": [
            {"id": "export-retry", "type": "fixed", "text": dict(zip(LANGUAGES, (
                "Retry failed exports without reimporting.", "导出失败后可直接重试。", "匯出失敗後可直接重試。", "失敗した書き出しを再試行できます。")))},
            {"id": "clear-errors", "type": "changed", "text": dict(zip(LANGUAGES, (
                "Clearer errors for names containing `<` & `>`.", "文件名包含 `<` & `>` 时显示明确错误。",
                "檔名包含 `<` & `>` 時顯示明確錯誤。", "名前に `<` & `>` が含まれる場合のエラーを改善しました。")))}
        ],
        "reviewed_sha256": None,
    }


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.source = example_source()

    def write_release(self, reviewed=True):
        if reviewed:
            self.source["reviewed_sha256"] = content_digest(self.source)
        (self.directory / f"v{self.source['version']}.json").write_text(json.dumps(self.source), encoding="utf-8")
        for name, text in generated_files(self.source).items():
            (self.directory / name).write_text(text, encoding="utf-8")

    def test_one_change_list_generates_four_matching_languages_and_github_body(self):
        self.write_release()
        notes = check_release(self.directory, "9.9.9")
        self.assertEqual(tuple(notes), LANGUAGES)
        for language, text in notes.items():
            self.assertIn("# Fralo 9.9.9", text)
            for change in self.source["changes"]:
                self.assertEqual(text.count(change["text"][language]), 1)
        body = (self.directory / "v9.9.9.md").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^## (.+)$", body, re.M), ["English", "简体中文"])
        for language in LANGUAGES:
            if language in ("en", "zh-Hans"):
                self.assertIn(self.source["summary"][language], body)
                for change in self.source["changes"]:
                    self.assertIn(change["text"][language], body)
            else:
                self.assertNotIn(self.source["summary"][language], body)
                for change in self.source["changes"]:
                    self.assertNotIn(change["text"][language], body)
        self.assertEqual(check_all(self.directory, "9.9.9"), 1)

    def test_github_body_includes_versioned_branding_before_changelog(self):
        body = generated_files(self.source)["v9.9.9.md"]
        self.assertTrue(body.startswith('<div align="center">\n'))
        self.assertIn('src="https://raw.githubusercontent.com/SoaringLabs/Fralo/v9.9.9/docs/assets/icon.png"', body)
        self.assertIn('width="128" height="128" alt="Fralo app icon"', body)
        self.assertIn("# Fralo 9.9.9", body)
        self.assertIn("Batch screenshot mockups for macOS.", body)
        self.assertIn("[Website](https://fralo.app)", body)
        self.assertIn("</div>\n\n---\n\n## English", body)

    def test_missing_empty_placeholder_and_extra_translations_are_rejected(self):
        for location in ("summary", "change"):
            for language in LANGUAGES:
                for value in (None, "", " \n ", "TODO", "待翻译", "要翻訳"):
                    with self.subTest(location=location, language=language, value=value):
                        source = copy.deepcopy(self.source)
                        translations = source["summary"] if location == "summary" else source["changes"][0]["text"]
                        if value is None:
                            del translations[language]
                        else:
                            translations[language] = value
                        with self.assertRaises(ValueError):
                            validate_source(source, "9.9.9")
        self.source["summary"]["fr"] = "An unexpected translation"
        with self.assertRaises(ValueError):
            validate_source(self.source, "9.9.9")

    def test_version_duplicate_ids_and_invalid_types_are_rejected(self):
        with self.assertRaises(ValueError):
            validate_source(self.source, "9.9.8")
        for field, value in (("id", "export-retry"), ("id", "../escape"), ("type", "unknown")):
            source = copy.deepcopy(self.source)
            source["changes"][1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_source(source, "9.9.9")

    def test_each_missing_or_edited_output_blocks_release(self):
        for name in generated_files(self.source):
            for altered in (None, "Handwritten content\n"):
                with self.subTest(name=name, altered=altered):
                    self.write_release()
                    path = self.directory / name
                    if altered is None:
                        path.unlink()
                    else:
                        path.write_text(altered)
                    with self.assertRaisesRegex(ValueError, "Missing or stale"):
                        check_release(self.directory, "9.9.9")

    def test_content_edits_invalidate_review_even_after_rendering(self):
        self.write_release(reviewed=False)
        with self.assertRaisesRegex(ValueError, "need review"):
            check_release(self.directory, "9.9.9")
        self.write_release()
        self.source["changes"][0]["text"]["ja"] += " 更新。"
        self.write_release(reviewed=False)
        with self.assertRaisesRegex(ValueError, "need review"):
            check_release(self.directory, "9.9.9")

    def test_template_edits_require_review_of_the_new_rendered_text(self):
        self.write_release()
        headings = list(HEADINGS["fixed"])
        headings[-1] = "修正された不具合"
        with patch.dict(HEADINGS, {"fixed": tuple(headings)}):
            # Regenerating after a template change must not reuse the old proofreading.
            self.write_release(reviewed=False)
            with self.assertRaisesRegex(ValueError, "need review"):
                check_release(self.directory, "9.9.9")

    def test_only_published_legacy_releases_are_exempt(self):
        for version in ("0.1.0", "0.1.1", "0.2.0"):
            (self.directory / f"v{version}.md").write_text("Historical notes\n")
        self.assertEqual(check_all(self.directory, "0.2.0"), 0)
        with self.assertRaises(FileNotFoundError):
            check_all(self.directory, "0.2.1")
        (self.directory / "v0.2.1.md").write_text("A new single-language release\n")
        with self.assertRaises(FileNotFoundError):
            check_all(self.directory, "0.2.0")

    def test_orphan_translations_and_unsupported_languages_do_not_bypass_ci(self):
        (self.directory / "v0.2.0.zh-Hans.md").write_text("A new translation\n")
        with self.assertRaises(FileNotFoundError):
            check_all(self.directory, "0.2.0")
        (self.directory / "v9.9.9.fr.md").write_text("Unexpected locale\n")
        with self.assertRaises(ValueError):
            check_all(self.directory, "0.2.0")

    def test_cli_requires_complete_rendered_and_explicitly_reviewed_notes(self):
        script = Path(__file__).with_name("release_notes.py")
        def cli(command, success):
            result = subprocess.run([sys.executable, "-B", str(script), command, "9.9.9", "--directory", str(self.directory)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        cli("new", True)
        cli("new", False)  # Never overwrites an existing source.
        cli("render", False)  # Empty scaffold cannot be published.
        (self.directory / "v9.9.9.json").write_text(json.dumps(self.source))
        cli("mark-reviewed", False)  # Proofreading requires generated output first.
        cli("render", True)
        cli("check", False)
        cli("mark-reviewed", True)
        cli("check", True)
        source = json.loads((self.directory / "v9.9.9.json").read_text())
        source["summary"]["en"] += " Another correction."
        (self.directory / "v9.9.9.json").write_text(json.dumps(source))
        cli("render", True)
        cli("check", False)


if __name__ == "__main__":
    unittest.main()
