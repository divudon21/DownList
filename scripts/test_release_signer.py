import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from check_release_signer import latest_signer


class SigningCheckTests(unittest.TestCase):
    def release(self, code, signer, **kwargs):
        meta = {'packageName': 'com.dowlist.com', 'versionCode': code, 'signerSha256': signer}
        return {'body': '<!-- downlist-update:' + json.dumps(meta) + ' -->', **kwargs}

    def test_latest_build_including_beta_and_draft_exclusion(self):
        releases = [self.release(5, 'a' * 64), self.release(8, 'b' * 64, prerelease=True), self.release(9, 'c' * 64, draft=True)]
        self.assertEqual(latest_signer(releases), 'b' * 64)

    def test_invalid_metadata_is_ignored(self):
        self.assertIsNone(latest_signer([{}, self.release(4, 'bad'), {'body': '<!-- downlist-update:{bad} -->'}]))

    def test_mismatch_requires_explicit_migration(self):
        script = Path(__file__).with_name('check_release_signer.py')
        with tempfile.TemporaryDirectory() as directory:
            releases = Path(directory) / 'releases.json'
            releases.write_text(json.dumps([self.release(10, 'a' * 64)]))
            base = [sys.executable, str(script), str(releases)]
            self.assertEqual(subprocess.run(base + ['a' * 64], capture_output=True).returncode, 0)
            self.assertNotEqual(subprocess.run(base + ['b' * 64], capture_output=True).returncode, 0)
            self.assertEqual(subprocess.run(base + ['b' * 64, '--allow-migration'], capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
