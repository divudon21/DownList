"""Check the launcher files that CI preserves during Android bootstrap."""
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'


def png_dimensions(path):
    with path.open('rb') as source:
        header = source.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError(f'Not a PNG: {path}')
    return struct.unpack('>II', header[16:24])


class LauncherIconTests(unittest.TestCase):
    def test_icons_exist_at_all_android_densities(self):
        for density, legacy, adaptive in [('mdpi', 48, 108), ('hdpi', 72, 162), ('xhdpi', 96, 216), ('xxhdpi', 144, 324), ('xxxhdpi', 192, 432)]:
            for name, size in [('ic_launcher', legacy), ('ic_launcher_round', legacy), ('ic_launcher_foreground', adaptive), ('ic_launcher_background', adaptive), ('ic_launcher_monochrome', adaptive)]:
                with self.subTest(density=density, name=name):
                    self.assertEqual(png_dimensions(RES / f'mipmap-{density}' / f'{name}.png'), (size, size))

    def test_adaptive_and_themed_icon_reference_the_new_assets(self):
        namespace = '{http://schemas.android.com/apk/res/android}'
        for name in ['ic_launcher.xml', 'ic_launcher_round.xml']:
            adaptive = ET.parse(RES / 'mipmap-anydpi-v26' / name).getroot()
            self.assertEqual(adaptive.find('monochrome').get(namespace + 'drawable'), '@drawable/ic_launcher_monochrome')
        bitmap = ET.parse(RES / 'drawable/ic_launcher_monochrome.xml').getroot()
        self.assertEqual(bitmap.get(namespace + 'src'), '@mipmap/ic_launcher_monochrome')
        width, height = png_dimensions(ROOT / 'assets/images/downlist_logo.png')
        self.assertEqual(width, height)
        self.assertGreaterEqual(width, 512)


if __name__ == '__main__':
    unittest.main()
