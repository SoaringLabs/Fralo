"""Release metadata must not silently advertise a stale or unsigned update."""
import copy
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock
import plistlib
import json
import xml.etree.ElementTree as ET
from prepare_update import SPARKLE, XML_LANG, embed_release_notes, main, validate_release, validate_appcast
from release_notes import LANGUAGES, content_digest, generated_files, render_notes
from test_release_notes import example_source


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.identity = {"build": "2", "version": "0.1.1", "updateFeed": "https://example.test/appcast.xml",
                         "updatePublicKey": "test-public-key"}
        self.info = {"CFBundleIdentifier": "app.fralo.desktop", "CFBundleVersion": "2",
                     "CFBundleShortVersionString": "0.1.1", "SUFeedURL": self.identity["updateFeed"],
                     "SUPublicEDKey": self.identity["updatePublicKey"]}
        self.notes = render_notes(example_source("0.1.1"))

    def test_archive_identity_and_build_must_match_the_release(self):
        validate_release(self.info, self.identity, previous_build=1)
        for key in self.info:
            with self.subTest(key=key):
                stale = copy.deepcopy(self.info)
                stale[key] = "unexpected"
                with self.assertRaises(ValueError):
                    validate_release(stale, self.identity, previous_build=1)
        with self.assertRaises(ValueError):
            validate_release(self.info, self.identity, previous_build=2)
        with self.assertRaises(ValueError):
            validate_release(self.info, self.identity, previous_build=3)

    def test_feed_cannot_point_to_another_file_or_omit_signing(self):
        url = "https://example.test/Fralo.dmg"
        feed = f'''<rss xmlns:sparkle="{SPARKLE}"><channel><item>
          <sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
          <enclosure url="{url}" length="123" sparkle:edSignature="test-signature"/>
        </item></channel></rss>'''
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "appcast.xml"
            path.write_text(feed)
            embed_release_notes(path, self.notes)
            self.assertEqual(validate_appcast(path, self.info, url, 123, self.notes), "test-signature")
            for invalid in (feed.replace('length="123"', 'length="124"'),
                            feed.replace(url, "https://example.test/other.dmg"),
                            feed.replace(' sparkle:edSignature="test-signature"', ''),
                            feed.replace('<sparkle:version>2', '<sparkle:version>1'),
                            feed.replace('<sparkle:shortVersionString>0.1.1', '<sparkle:shortVersionString>0.1.0')):
                path.write_text(invalid)
                embed_release_notes(path, self.notes)
                with self.assertRaises(ValueError):
                    validate_appcast(path, self.info, url, 123, self.notes)

    def test_feed_requires_exact_reviewed_content_for_each_language(self):
        feed = f'''<rss xmlns:sparkle="{SPARKLE}"><channel><item>
          <sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <description>Old single-language notes</description>
          <sparkle:releaseNotesLink>https://example.test/old.md</sparkle:releaseNotesLink>
          <enclosure url="https://example.test/update.dmg" length="123" sparkle:edSignature="archive-signature"/>
        </item></channel></rss>'''
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "appcast.xml"
            def validate():
                return validate_appcast(path, self.info, "https://example.test/update.dmg", 123, self.notes)
            path.write_text(feed)
            with self.assertRaises(ValueError):
                validate()
            embed_release_notes(path, self.notes)
            pristine = path.read_bytes()
            self.assertEqual(validate(), "archive-signature")
            self.assertEqual([node.get(XML_LANG) for node in ET.parse(path).findall("./channel/item/description")], list(LANGUAGES))
            self.assertEqual(ET.parse(path).findtext(f"./channel/item/{{{SPARKLE}}}minimumSystemVersion"), "14.0")
            for mutation in ("missing", "duplicate", "unknown", "wrong-text", "wrong-format", "external"):
                path.write_bytes(pristine)
                tree = ET.parse(path); item = tree.find("./channel/item"); node = item.findall("description")[-1]
                if mutation == "missing": item.remove(node)
                elif mutation == "duplicate": node.set(XML_LANG, "en")
                elif mutation == "unknown": node.set(XML_LANG, "fr")
                elif mutation == "wrong-text": node.text = "Stale translated content"
                elif mutation == "wrong-format": node.set(f"{{{SPARKLE}}}format", "html")
                else: ET.SubElement(item, f"{{{SPARKLE}}}releaseNotesLink").text = "https://example.test/override.md"
                tree.write(path)
                with self.subTest(mutation=mutation), self.assertRaises(ValueError): validate()

    def test_release_preparation_gates_notes_before_keys_and_signs_final_feed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root / "Fralo.dmg"; archive.write_bytes(b"test archive")
            output = root / "appcast.xml"
            app = root / "volume/Fralo.app/Contents"; app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps(self.info))
            argv = ["prepare_update.py", "--archive", str(archive), "--previous-build", "1", "--notes-dir", str(root), "--output", str(output)]
            with patch("sys.argv", argv), patch("prepare_update.release_identity", return_value=self.identity), patch("prepare_update.run") as run:
                with redirect_stderr(StringIO()), self.assertRaises(SystemExit): main()
                run.assert_not_called()
            old_argv = ["prepare_update.py", "--archive", str(archive), "--previous-build", "1", "--notes", str(root / "v0.1.1.md")]
            with patch("sys.argv", old_argv), patch("prepare_update.run") as run:
                message = StringIO()
                with redirect_stderr(message), self.assertRaises(SystemExit): main()
                self.assertIn("unrecognized arguments: --notes", message.getvalue())
                run.assert_not_called()
            source = example_source("0.1.1"); source["reviewed_sha256"] = content_digest(source)
            (root / "v0.1.1.json").write_text(json.dumps(source))
            for name, text in generated_files(source).items(): (root / name).write_text(text)
            calls = []
            def run(*args):
                calls.append(args)
                if "generate_keys" in args[0]: return b"test-public-key"
                if args[:2] == ("hdiutil", "attach"):
                    return plistlib.dumps({"system-entities": [{"mount-point": str(root / "volume")}]})
                if "sign_update" in args[0] and args[-1].endswith("appcast.xml"):
                    # Sign/verify must see the final translations, not the English-only intermediate feed.
                    nodes = ET.parse(args[-1]).findall("./channel/item/description")
                    self.assertEqual([node.get(XML_LANG) for node in nodes], list(LANGUAGES))
                return b""
            def subprocess_run(args, **kwargs):
                if "generate_appcast" in args[0]:
                    path = Path(args[args.index("-o") + 1])
                    path.write_text(f'''<rss xmlns:sparkle="{SPARKLE}"><channel><item>
                      <sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
                      <enclosure url="https://github.com/SoaringLabs/Fralo/releases/download/v0.1.1/Fralo.dmg" length="12" sparkle:edSignature="test-signature"/>
                    </item></channel></rss>''')
                return Mock(stderr="Authority=Developer ID Application: Test")
            with patch("sys.argv", argv), patch("prepare_update.release_identity", return_value=self.identity), \
                 patch("prepare_update.run", side_effect=run), patch("prepare_update.subprocess.run", side_effect=subprocess_run), \
                 redirect_stdout(StringIO()):
                main()
            self.assertEqual(len(ET.parse(output).findall("./channel/item/description")), 4)
            sign_feed = [args for args in calls if "sign_update" in args[0] and "--verify" not in args and args[-1].endswith("appcast.xml")]
            verify_feed = [args for args in calls if "sign_update" in args[0] and "--verify" in args and args[-1].endswith("appcast.xml")]
            self.assertEqual(len(sign_feed), 1)
            self.assertEqual(len(verify_feed), 1)


if __name__ == "__main__":
    unittest.main()
