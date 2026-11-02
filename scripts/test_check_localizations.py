#!/usr/bin/env python3
"""Exercise the guardrail's failure paths as well as valid translations."""
from pathlib import Path
import tempfile
import unittest
from check_localizations import check_source, compare_catalogs, read_catalog, LANGUAGES


class LocalizationGuardTests(unittest.TestCase):
    def test_missing_language_key_fails(self):
        catalogs = {language: {"图片 {0}": "Images {0}"} for language in LANGUAGES}
        catalogs["ja"] = {}
        self.assertTrue(any("missing key" in error for error in compare_catalogs(catalogs)))

    def test_interpolation_is_reorderable_but_cannot_disappear(self):
        catalogs = {language: {"{0} / {1}": "{1} / {0}"} for language in LANGUAGES}
        self.assertEqual(compare_catalogs(catalogs), [])
        catalogs["ja"]["{0} / {1}"] = "{0} / {0}"
        self.assertTrue(any("interpolation mismatch" in error for error in compare_catalogs(catalogs)))

    def test_filename_format_must_be_preserved(self):
        catalogs = {language: {"粘贴-%03d.png": "Pasted-%03d.png"} for language in LANGUAGES}
        catalogs["en"]["粘贴-%03d.png"] = "Pasted-%s.png"
        self.assertTrue(any("printf format mismatch" in error for error in compare_catalogs(catalogs)))

    def test_catalog_rejects_duplicates_empty_values_and_malformed_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.strings"
            path.write_text('"a" = "A";\n"a" = "";\nnot a string;')
            _, errors = read_catalog(path)
            for expected in ("duplicate", "empty", "invalid catalog syntax"):
                self.assertTrue(any(expected in error for error in errors))

    def test_source_requires_registration_and_localization_in_either_language(self):
        for source in ['button.title = "Export"', 'ActionButton("导出")', 'setAccessibilityLabel("Export")',
                       'NSMenuItem(title: "Export", action: nil, keyEquivalent: "")', 'L10n.tr("New string")']:
            self.assertTrue(check_source("example.swift", source, {}), source)
        source = '// "中文注释"\n/* "another comment" */\nActionButton(L10n.tr("导出"))'
        self.assertEqual(check_source("example.swift", source, {"导出": "Export"}), [])

    def test_catalog_preserves_urls_and_quoted_comment_markers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.strings"
            path.write_text('// comment\n"link" = "https://example.com/*path*/";')
            values, errors = read_catalog(path)
            self.assertEqual(errors, [])
            self.assertEqual(values["link"], "https://example.com/*path*/")

    def test_interpolation_lexer_handles_nested_swift_expressions(self):
        source = r'L10n.tr("输出：\(String(format: "%.2f", value))")'
        self.assertEqual(check_source("example.swift", source, {"输出：{0}": "Output: {0}"}), [])


if __name__ == "__main__":
    unittest.main()
