"""Validate and package the reviewed UI translation catalog; no network translation."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
source=root/'android/i18n/en.json'
catalog=json.loads(source.read_text(encoding='utf8'))
assert len(catalog)>1300
for original,translation in catalog.items():
    assert original and translation.strip(),repr(original)
    assert re.findall(r'%(?:\d+\$)?[\d.]*[sdf]',original)==re.findall(r'%(?:\d+\$)?[\d.]*[sdf]',translation),repr(original)
    assert set(re.findall(r'https?://[^\s]+',original))==set(re.findall(r'https?://[^\s]+',translation)),repr(original)
target=root/'android/app/src/main/assets/i18n-en.json'
target.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(f'Validated and packaged {len(catalog)} English UI translations')
