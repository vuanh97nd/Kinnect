"""Validate the native design export and enforce the no-WebView requirement."""
from pathlib import Path
import argparse, json, re, unittest, xml.etree.ElementTree as ET, zipfile
ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--apk', type=Path)
args = parser.parse_args()

class NativeDesignTest(unittest.TestCase):
    def test_theme_matches_reviewed_web(self):
        reference = json.loads((ROOT/'android/design/web-reference.json').read_text(encoding='utf-8'))
        source = (ROOT/'android/app/src/main/java/app/kinnect/live/WebDesign.java').read_text()
        for name, colors in reference['colors'].items():
            declaration = re.search(r'int\[\] '+name.upper().replace('-', '_')+r' = \{ ([^}]+) \}', source)
            self.assertIsNotNone(declaration, name)
            expected = []
            for value in colors:
                hex_value = value[1:]
                if len(hex_value) == 3: hex_value = ''.join(c*2 for c in hex_value)
                expected.append('0xff'+hex_value.lower())
            self.assertEqual(declaration.group(1).split(', '), expected)

    def test_all_native_web_vectors_compile_shape_contract(self):
        reference = json.loads((ROOT/'android/design/web-reference.json').read_text(encoding='utf-8'))
        icons = list((ROOT/'android/app/src/main/res/drawable').glob('ic_web_*.xml'))
        self.assertEqual(len(icons), reference['native_icons'])
        ns = '{http://schemas.android.com/apk/res/android}'
        for icon in icons:
            root = ET.parse(icon).getroot()
            self.assertEqual(root.get(ns+'viewportWidth'), '24')
            self.assertGreater(len(root.findall('path')), 0, icon.name)
            for path in root.findall('path'):
                self.assertTrue(path.get(ns+'pathData'), icon.name)
                self.assertEqual(path.get(ns+'strokeWidth'), '1.7')

    def test_every_literal_icon_resolves(self):
        resources = ROOT/'android/app/src/main/res/drawable'
        directory = ROOT/'android/app/src/main/java/app/kinnect/live'
        aliases = dict(re.findall(r'case "([^"]+)": web = "([^"]+)";', (directory/'WebIcons.java').read_text()))
        for file in directory.glob('*.java'):
            for name in re.findall(r'(?:icon|accountRow|messageTool|softIconButton)\("([^"]+)"', file.read_text(encoding='utf-8')):
                web_name = aliases.get(name, name).replace('-', '_')
                self.assertTrue((resources/('ic_web_'+web_name+'.xml')).exists() or (resources/('ic_'+name+'.xml')).exists(), file.name+': '+name)

    def test_application_has_no_web_container(self):
        for source in (ROOT/'android/app/src/main/java').rglob('*.java'):
            text = source.read_text(encoding='utf-8')
            self.assertNotRegex(text, r'import\s+android\.webkit\.')
            self.assertNotRegex(text, r'new\s+(?:WebView|TrustedWebActivity|CustomTabsIntent)\b')
        if args.apk:
            with zipfile.ZipFile(args.apk) as archive:
                self.assertFalse(any(name.endswith(('.html','.js')) for name in archive.namelist()))
                for name in archive.namelist():
                    if name.endswith('.dex'):
                        self.assertNotIn(b'Landroid/webkit/WebView;', archive.read(name))

if __name__ == '__main__':
    unittest.main(argv=['test-native-design'], verbosity=2)
