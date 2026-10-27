"""Export Kinnect web design tokens and SVG icons to native Android resources.

Input is static design source only. The Android app does not embed HTML/JS or a WebView.
"""
from pathlib import Path
import argparse, hashlib, json, re, xml.etree.ElementTree as ET
from android_vector_paths import normalize_svg_path

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--css', type=Path, default=ROOT / 'public/v2.css')
parser.add_argument('--icons', type=Path, default=ROOT / 'public/v2-icons.js')
args = parser.parse_args()
css = args.css.read_text(encoding='utf-8-sig')
icons = args.icons.read_text(encoding='utf-8-sig')
colors = dict((name, (light, dark)) for name, light, dark in re.findall(r'--k-([a-z-]+):light-dark\((#[0-9a-fA-F]+),(#[0-9a-fA-F]+)\)', css))
required = ['purple', 'purple-ink', 'soft', 'bg', 'card', 'ink', 'muted', 'line', 'wash', 'danger', 'success', 'online']
assert all(name in colors for name in required), 'Web design tokens are incomplete'
def argb(value):
    h = value[1:]
    if len(h) == 3: h = ''.join(c*2 for c in h)
    assert len(h) == 6
    return '0xff' + h.lower()
java = ['package app.kinnect.live;', '', '/** Generated from the approved web CSS. Native Android resources only. */', 'final class WebDesign {']
for name in required:
    java.append('  static final int[] ' + name.upper().replace('-', '_') + ' = { ' + ', '.join(argb(v) for v in colors[name]) + ' };')
java += ['  static final int BODY = 14, LABEL = 13, META = 12, TITLE = 21, SECTION = 16;', '  static final int CONTROL = 44, CARD_RADIUS = 18, HEADER = 56;', '}']
(ROOT/'android/app/src/main/java/app/kinnect/live/WebDesign.java').write_text('\n'.join(java)+'\n', encoding='utf-8')
items = dict(re.findall(r"[\"']?([a-z0-9-]+)[\"']?\s*:\s*'([^']+)'", icons))
items.update(dict(re.findall(r'window\.KN_ICONS\["([a-z0-9-]+)"\]\s*=\s*\x27([^\x27]+)\x27', icons)))
ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ns)
a = lambda name: '{'+ns+'}'+name
for name, svg in sorted(items.items()):
    root = ET.Element('vector', {a('width'):'24dp', a('height'):'24dp', a('viewportWidth'):'24', a('viewportHeight'):'24'})
    for element in ET.fromstring('<svg>'+svg+'</svg>'):
        at = element.attrib
        if element.tag == 'path': d = at['d']
        elif element.tag == 'circle':
            x,y,r = (float(at.get(k,0)) for k in ['cx','cy','r'])
            d = f'M{x-r},{y}a{r},{r} 0 1,0 {2*r},0a{r},{r} 0 1,0 {-2*r},0'
        elif element.tag == 'rect':
            x,y,w,h = (float(at.get(k,0)) for k in ['x','y','width','height'])
            r = min(float(at.get('rx',0)),w/2,h/2)
            d = f'M{x+r},{y}H{x+w-r}Q{x+w},{y} {x+w},{y+r}V{y+h-r}Q{x+w},{y+h} {x+w-r},{y+h}H{x+r}Q{x},{y+h} {x},{y+h-r}V{y+r}Q{x},{y} {x+r},{y}Z'
        else: raise ValueError('Unsupported SVG element: '+element.tag)
        d = normalize_svg_path(d)
        ET.SubElement(root,'path',{a('pathData'):d,a('fillColor'):'#00000000',a('strokeColor'):'#FF000000',a('strokeWidth'):'1.7',a('strokeLineCap'):'round',a('strokeLineJoin'):'round'})
    path = ROOT/'android/app/src/main/res/drawable'/('ic_web_'+name.replace('-','_')+'.xml')
    path.write_text(ET.tostring(root,encoding='unicode')+'\n',encoding='utf-8')
metadata = {'reference':'https://app.kinnect.io.vn/','reviewed':'2026-10-27','css_sha256':hashlib.sha256(args.css.read_bytes()).hexdigest(),'icons_sha256':hashlib.sha256(args.icons.read_bytes()).hexdigest(),'colors':colors,'native_icons':len(items),'implementation':'Android Views; no WebView'}
output=ROOT/'android/design/web-reference.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Exported',len(required),'theme tokens and',len(items),'native vector icons.')
