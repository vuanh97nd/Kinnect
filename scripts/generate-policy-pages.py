from pathlib import Path
import json,html
r=Path(__file__).resolve().parents[1];data=json.loads((r/'public/policies.json').read_text(encoding='utf8'))
for key in ['privacy','community','child-safety']:
 policy=data[key];meta={'title':policy['title']+' — Kinnect','description':policy['title']+' của Kinnect do '+data['operator']+' vận hành.','path':'/'+key,'nav':''}
 body='<article class="legal-page"><h1>'+html.escape(policy['title'])+'</h1><p>Cập nhật: 29/10/2026 · Kinnect · Mr Ánh · <a href="mailto:anhvn53@wru.vn">anhvn53@wru.vn</a></p>'
 for i,(heading,text) in enumerate(policy['sections']):body+='<section id="section-'+str(i+1)+'"><h2>'+html.escape(heading)+'</h2><p>'+html.escape(text)+'</p></section>'
 body+='<p><a href="https://app.kinnect.io.vn/delete-account">Yêu cầu xóa tài khoản</a> · <a href="/privacy">Quyền riêng tư</a> · <a href="/community">Quy tắc cộng đồng</a> · <a href="/child-safety">An toàn trẻ em</a></p></article>'
 (r/'website/src/pages'/f'{key}.html').write_text(json.dumps(meta,ensure_ascii=False)+'\n'+body+'\n',encoding='utf8')
# Android renders the same canonical policy text, rather than keeping divergent copies.
source='package app.kinnect.live;\nfinal class PolicyText {\nstatic String title(String key){switch(key){\n'
for key in ['privacy','community','child-safety']:source+='case '+json.dumps(key)+':return '+'I18n.t('+json.dumps(data[key]['title'],ensure_ascii=False)+');\n'
source+='default:return "Kinnect";}}\nstatic String[][] rows(String key){switch(key){\n'
for key in ['privacy','community','child-safety']:
 rows=[]
 for heading,text in data[key]['sections']:rows += [['h2',heading],['p',text]]
 source+='case '+json.dumps(key)+':return new String[][]{'+','.join('{'+','.join(json.dumps(v,ensure_ascii=False) if i==0 else 'I18n.t('+json.dumps(v,ensure_ascii=False)+')' for i,v in enumerate(row))+'}'for row in rows)+'};\n'
source+='default:return new String[][]{};}}\n}\n';(r/'android/app/src/main/java/app/kinnect/live/PolicyText.java').write_text(source,encoding='utf8')
print('Generated canonical privacy, community and child safety pages plus Android policy text')
