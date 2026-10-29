"""Build Kinnect's original soft-contour native icon family on one 24-unit grid."""
from pathlib import Path
import json,copy,re,xml.etree.ElementTree as E
from android_vector_paths import normalize_svg_path
R=Path(__file__).resolve().parents[1];D=R/'android/app/src/main/res/drawable';A='{http://schemas.android.com/apk/res/android}';E.register_namespace('android',A[1:-1])
# Independently drawn contours. Branded login marks and the approved K are excluded.
CORE={
'house':['M3.5 10.5L10 4.8Q12 3 14 4.8L20.5 10.5V19Q20.5 21 18.5 21H15V14H9V21H5.5Q3.5 21 3.5 19Z'],
'compass':['M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12Z','M15.8 8.2L13.5 13.5L8.2 15.8L10.5 10.5Z'],
'clapperboard':['M3.5 9H20.5V18.5Q20.5 21 18 21H6Q3.5 21 3.5 18.5Z','M3.5 9L2.7 5.3L19.6 2.8L20.5 6.5Z','M8 4.5L10 8M14 3.7L16 7.2','M10 12.5L15 15L10 17.5Z'],
'radio':['M9.5 8.5Q6 12 9.5 15.5M14.5 8.5Q18 12 14.5 15.5','M6 5Q-.2 12 6 19M18 5Q24.2 12 18 19','M12 11.5V12.5'],
'message_square':['M5.8 3.5H18.2Q21 3.5 21 6.3V15Q21 17.8 18.2 17.8H9L4 21V17Q3 16 3 14V6.3Q3 3.5 5.8 3.5Z','M7.5 8.5H16.5M7.5 12.5H13.5'],
'message_circle':['M21 11.5Q21 19.5 12 19.5Q9.5 19.5 7.3 18.4L3.5 20L4.4 15.7Q3 14 3 11.5Q3 3.5 12 3.5Q21 3.5 21 11.5Z','M8 11.5H8.1M12 11.5H12.1M16 11.5H16.1'],
'bell':['M6 9Q6 3.5 12 3.5Q18 3.5 18 9V13.5L20 17H4L6 13.5Z','M9.5 20Q12 22 14.5 20'],
'user_round':['M16 7.5A4 4 0 1 1 8 7.5A4 4 0 1 1 16 7.5Z','M4.5 21V18Q4.5 13.5 12 13.5Q19.5 13.5 19.5 18V21'],
'users_round':['M14 7A3.5 3.5 0 1 1 7 7A3.5 3.5 0 1 1 14 7Z','M3 20V17Q3 13 10.5 13Q18 13 18 17V20','M17 4Q21 4.5 21 8Q21 11 18 11M20 14Q23 15 22 20'],
'settings':['M9 3H15L15.8 5.5L18 6.8L20.5 6.2L23 11L21 13L20.8 15.5L22 17.5L18 21L15.5 19.8L13 21H8.5L8 18.5L5.8 17.2L3.5 17.8L1 13L3 11L3.2 8.5L2 6.5L6 3L8.5 4.2Z','M16 12A4 4 0 1 1 8 12A4 4 0 1 1 16 12Z'],
'shield_check':['M12 2.8L20.5 6V12Q20.5 18 12 21.5Q3.5 18 3.5 12V6Z','M8 11.7L10.8 14.5L16 9.3'],
'lock_keyhole':['M7 9V7Q7 2.5 12 2.5Q17 2.5 17 7V9','M6 9H18Q20 9 20 11V19Q20 21 18 21H6Q4 21 4 19V11Q4 9 6 9Z','M12 14V16.5'],
'shopping_bag':['M4 8H20V18.5Q20 21 17.5 21H6.5Q4 21 4 18.5Z','M4 8L6.5 3H17.5L20 8M8 8V10Q8 14 12 14Q16 14 16 10V8'],
'wallet':['M20.5 7V4.5H6Q3 4.5 3 7.5V17.5Q3 20.5 6 20.5H21V9H6Q3 9 3 7.5','M21 12H15.5Q14 12 14 13.5V16Q14 17.5 15.5 17.5H21M17 14.8H17.1'],
'camera':['M4.8 6H7L8.7 3.5H15.3L17 6H19.2Q21.5 6 21.5 8.5V18Q21.5 20.5 19 20.5H5Q2.5 20.5 2.5 18V8.5Q2.5 6 4.8 6Z','M16 13A4 4 0 1 1 8 13A4 4 0 1 1 16 13Z'],
'video':['M5 5H14Q17 5 17 8V16Q17 19 14 19H5Q2 19 2 16V8Q2 5 5 5Z','M17 9L22 6V18L17 15Z'],
'mic':['M15.5 6V11Q15.5 14.5 12 14.5Q8.5 14.5 8.5 11V6Q8.5 2.5 12 2.5Q15.5 2.5 15.5 6Z','M5 11Q5 18 12 18Q19 18 19 11M12 18V22M8 22H16'],
'volume_2':['M10 5L5.5 9H2.5V15H5.5L10 19Z','M14 8Q18 12 14 16M17 4.5Q24 12 17 19.5'],
'switch_camera':['M4 8Q9 0 17 4L21 8M21 3V8H16','M20 16Q15 24 7 20L3 16M3 21V16H8'],
'image':['M6 3.5H18Q21 3.5 21 6.5V17.5Q21 20.5 18 20.5H6Q3 20.5 3 17.5V6.5Q3 3.5 6 3.5Z','M3.5 17L9 11.5L13.5 16L16.5 13L21 17.5','M16.5 7.5H16.6'],
'heart':['M12 21L4.5 14Q-1 8.5 4 4.5Q8 1.5 12 6Q16 1.5 20 4.5Q25 8.5 19.5 14Z'],
'gift':['M3 8.5H21V12.5H3ZM5 12.5V21H19V12.5M12 8.5V21','M12 8.5H7Q3.5 8.5 4.5 5.2Q6 1.8 9 5L12 8.5ZM12 8.5H17Q20.5 8.5 19.5 5.2Q18 1.8 15 5Z'],
'search':['M18 10.5A7.5 7.5 0 1 1 3 10.5A7.5 7.5 0 1 1 18 10.5Z','M16 16L21 21'],
'send':['M3 3.5L21 12L3 20.5L6 12ZM6 12H16'],
'send_horizontal':['M3 3.5L21 12L3 20.5L6 12ZM6 12H16'],
'arrow_left':['M20 12H4M10 5L3 12L10 19'],
'arrow_right':['M4 12H20M14 5L21 12L14 19'],
'chevron_left':['M15 5L8 12L15 19'],
'chevron_right':['M9 5L16 12L9 19'],
'chevron_down':['M5 9L12 16L19 9'],
'x':['M6 6L18 18M18 6L6 18'],
'plus':['M12 4V20M4 12H20'],
'check':['M4.5 12L9.5 17L20 6.5'],
'ellipsis':['M5 12H5.1M12 12H12.1M19 12H19.1'],
'menu':['M4 6H20M4 12H20M4 18H20'],
'sliders_horizontal':['M3 6H7M11 6H21M3 12H13M17 12H21M3 18H5M9 18H21','M7 3.5V8.5M15 9.5V14.5M7 15.5V20.5'],
'sparkles':['M12 3L14.5 9.5L21 12L14.5 14.5L12 21L9.5 14.5L3 12L9.5 9.5Z','M20 2V6M18 4H22'],
'play':['M8 4L20 12L8 20Z'],
'pause':['M7 4V20M17 4V20'],
'trash_2':['M3 6H21M9 6V3H15V6M5 6L6 21H18L19 6M10 10V17M14 10V17'],
'eye':['M2.5 12Q12 -1 21.5 12Q12 25 2.5 12Z','M15 12A3 3 0 1 1 9 12A3 3 0 1 1 15 12Z'],
'info':['M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12Z','M12 10.5V17M12 7H12.1'],
'circle_help':['M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12Z','M9 8Q9.5 5 12.5 6Q17 7.5 13 11L12 13M12 17H12.1'],
}
def vector(paths):
 v=E.Element('vector',{A+'width':'24dp',A+'height':'24dp',A+'viewportWidth':'24',A+'viewportHeight':'24'})
 g=E.SubElement(v,'group',{A+'scaleX':'.92',A+'scaleY':'.92',A+'translateX':'.96',A+'translateY':'.96'})
 for d in paths:E.SubElement(g,'path',{A+'pathData':normalize_svg_path(d),A+'fillColor':'#00000000',A+'strokeColor':'#FFFFFFFF',A+'strokeWidth':'1.9',A+'strokeLineCap':'round',A+'strokeLineJoin':'round'})
 return v
CORE.update({
 'file_text':['M6 3H14L20 9V19Q20 21 18 21H6Q4 21 4 19V5Q4 3 6 3Z','M14 3V9H20M8 13H16M8 17H14'],
 'share_2':['M20 5A3 3 0 1 1 14 5A3 3 0 1 1 20 5Z','M10 12A3 3 0 1 1 4 12A3 3 0 1 1 10 12Z','M20 19A3 3 0 1 1 14 19A3 3 0 1 1 20 19Z','M9.5 10.5L14.5 6.5M9.5 13.5L14.5 17.5'],
 'user_round_x':['M14 6.5A3.5 3.5 0 1 1 7 6.5A3.5 3.5 0 1 1 14 6.5Z','M3.5 21V17Q3.5 13 10.5 13Q13.5 13 15 14M16 16L22 22M22 16L16 22']
})
# Rounded eight-tooth gear, with a shared optical centre rather than an irregular polygon.
import math
points=[]
for tooth in range(8):
 for offset,radius in [(-.28,7.4),(-.13,9.2),(.13,9.2),(.28,7.4)]:
  angle=tooth*math.pi/4+offset;points.append((12+radius*math.cos(angle),12+radius*math.sin(angle)))
gear=[]
for i,point in enumerate(points):
 prev=points[i-1];nxt=points[(i+1)%len(points)];before=(point[0]*.7+prev[0]*.3,point[1]*.7+prev[1]*.3);after=(point[0]*.7+nxt[0]*.3,point[1]*.7+nxt[1]*.3)
 gear.append(('M' if i==0 else 'L')+f'{before[0]:.3f} {before[1]:.3f} Q{point[0]:.3f} {point[1]:.3f} {after[0]:.3f} {after[1]:.3f}')
CORE['settings']=[' '.join(gear)+'Z','M15.5 12A3.5 3.5 0 1 1 8.5 12A3.5 3.5 0 1 1 15.5 12Z']
catalog=[]
for source in sorted(D.glob('ic_*.xml')):
 if source.stem.startswith(('ic_flow_','ic_brand_')):continue
 root=E.parse(source).getroot()
 if root.tag!='vector':continue
 suffix=source.stem[3:];key=suffix.removeprefix('web_');custom=CORE.get(key) if not suffix.startswith(('editor_','call_')) else None
 if custom:root=vector(custom)
 else:
  root=copy.deepcopy(root)
  while len(root)==1 and root[0].tag=='group' and root[0].get(A+'scaleX')=='.92' and root[0].get(A+'translateX')=='.96':
   children=list(root[0]);root[:]=children
  # Same optical inset and weight, keeping specialised editor metaphors intact.
  children=list(root);root[:]=[]
  group=E.SubElement(root,'group',{A+'scaleX':'.92',A+'scaleY':'.92',A+'translateX':'.96',A+'translateY':'.96'})
  for child in children:group.append(child)
  for path in root.iter('path'):
   if path.get(A+'strokeWidth'):
    path.set(A+'strokeWidth','1.9');path.set(A+'strokeLineCap','round');path.set(A+'strokeLineJoin','round')
   if path.get(A+'pathData'):path.set(A+'pathData',normalize_svg_path(path.get(A+'pathData')))
 output=D/('ic_flow_'+suffix+'.xml');E.ElementTree(root).write(output,encoding='utf-8',xml_declaration=False)
 catalog.append({'resource':output.stem,'source':source.stem,'redrawn':bool(custom),'category':'editor' if suffix.startswith('editor_') else 'call' if suffix.startswith('call_') else 'interface'})
for key,paths in CORE.items():
 name='ic_flow_web_'+key
 if not any(x['resource']==name for x in catalog):
  E.ElementTree(vector(paths)).write(D/(name+'.xml'),encoding='utf-8');catalog.append({'resource':name,'source':None,'redrawn':True,'category':'interface'})
# System notifications cannot load a runtime wrapper, so use the same new vector there.
for name in ['bell','message_circle','video']:
 flow=D/('ic_flow_web_'+name+'.xml')
 if flow.exists():(D/('ic_web_'+name+'.xml')).write_bytes(flow.read_bytes())
target=R/'android/design/icon-family.json';target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps({'style':'Kinnect Flow — original ColorOS-inspired soft contours','grid':24,'stroke':1.9,'opticalInset':.96,'brandAssetsUnchanged':True,'icons':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({'icons':len(catalog),'redrawn':sum(x['redrawn'] for x in catalog),'catalog':str(target)}))

assets=R/'android/app/src/main/assets';assets.mkdir(exist_ok=True)
(assets/'native-icon-family.json').write_bytes(target.read_bytes())
usage=R/'android/design/icon-usage.json'
references=[]
pattern=r'(?:WebIcons\.(?:load|resolve)\([^,]+,\s*|icon\(|sideButton\(|softIconButton\(|roundAction\(|groupRow\([^,]+,\s*|settingsIcon\()"([^"\n]+)"'
for source in (R/'android/app/src/main/java/app/kinnect/live').glob('*.java'):
 text=source.read_text(encoding='utf8')
 for match in re.finditer(pattern,text):references.append({'file':source.name,'line':text[:match.start()].count('\n')+1,'name':match.group(1)})
usage.write_text(json.dumps({'references':references,'legacyRasters':[p.name for p in D.glob('ic_approved_*.png')],'brandAssetsUnchanged':True},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
(assets/'native-icon-usage.json').write_bytes(usage.read_bytes())
