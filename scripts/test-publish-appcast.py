import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('feed', Path(__file__).with_name('publish-appcast.py'))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


def appcast(version):
    return (f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f'<channel><item><sparkle:version>{version}</sparkle:version></item></channel></rss>').encode()


class PublishTests(unittest.TestCase):
    def test_empty_feed_has_no_release(self):
        self.assertEqual(feed.newest_version(b'<rss><channel/></rss>'), 0)

    def test_older_release_does_not_replace_feed(self):
        existing = feed.json.dumps(dict(sha='original', content=feed.base64.b64encode(appcast(1002)).decode()))
        with patch.object(feed.subprocess, 'check_output', return_value=existing), \
                patch('builtins.open', unittest.mock.mock_open(read_data=appcast(1001))), \
                patch.object(feed.subprocess, 'run') as update:
            feed.publish('feed.xml')
            update.assert_not_called()

    def test_newer_release_updates_using_existing_revision(self):
        existing = feed.json.dumps(dict(sha='original', content=feed.base64.b64encode(appcast(1001)).decode()))
        with patch.object(feed.subprocess, 'check_output', return_value=existing), \
                patch('builtins.open', unittest.mock.mock_open(read_data=appcast(1002))), \
                patch.object(feed.subprocess, 'run') as update:
            feed.publish('feed.xml')
            payload = feed.json.loads(update.call_args.kwargs['input'])
            self.assertEqual(payload['sha'], 'original')
            self.assertEqual(feed.base64.b64decode(payload['content']), appcast(1002))

    def test_malformed_version_rejected(self):
        with self.assertRaises(ValueError):
            feed.newest_version(appcast('not-a-version'))


if __name__ == '__main__':
    unittest.main()
