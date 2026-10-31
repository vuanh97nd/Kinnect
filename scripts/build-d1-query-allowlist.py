from pathlib import Path
import re,json
root=Path(__file__).resolve().parent.parent
queries=[]
for name in ('lib/cloud-chat-repository.js','cloud-api/chat-routes.js','cloud-api/native-chat.js','cloud-api/notification-routes.js'):
    source=(root/name).read_text(encoding='utf-8')
    for match in re.finditer(r"(['\"`])\s*((?:SELECT|INSERT|UPDATE|DELETE)\s[\s\S]*?)\1",source):
        sql=' '.join(match[2].split())
        if 'kinnect_core.' in sql: continue
        if '${' in sql: raise ValueError('Dynamic SQL prohibited')
        if sql not in queries: queries.append(sql)
(root/'cloud-api/d1-queries.js').write_text('// Generated fixed SQL allowlist; no arbitrary SQL accepted.\nexport const D1_QUERIES='+json.dumps(queries,ensure_ascii=False,indent=1)+';\n',encoding='utf-8')
print(f'Fixed D1 queries: {len(queries)}')
