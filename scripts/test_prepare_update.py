"""Release metadata must not silently advertise a stale or unsigned update."""
import copy
from pathlib import Path
import tempfile
import unittest
from prepare_update import SPARKLE, validate_release, validate_appcast


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.identity = {"build": "2", "version": "0.1.1", "updateFeed": "https://example.test/appcast.xml",
                         "updatePublicKey": "test-public-key"}
        self.info = {"CFBundleIdentifier": "app.fralo.desktop", "CFBundleVersion": "2",
                     "CFBundleShortVersionString": "0.1.1", "SUFeedURL": self.identity["updateFeed"],
                     "SUPublicEDKey": self.identity["updatePublicKey"]}

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
            self.assertEqual(validate_appcast(path, self.info, url, 123), "test-signature")
            for invalid in (feed.replace('length="123"', 'length="124"'),
                            feed.replace(url, "https://example.test/other.dmg"),
                            feed.replace(' sparkle:edSignature="test-signature"', ''),
                            feed.replace('<sparkle:version>2', '<sparkle:version>1'),
                            feed.replace('<sparkle:shortVersionString>0.1.1', '<sparkle:shortVersionString>0.1.0')):
                path.write_text(invalid)
                with self.assertRaises(ValueError):
                    validate_appcast(path, self.info, url, 123)


if __name__ == "__main__":
    unittest.main()
