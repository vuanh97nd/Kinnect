from pathlib import Path
import urllib.request,base64
r=Path(__file__).resolve().parents[1];parts=[]
items=[('WebRTC — BSD 3-Clause','https://webrtc.googlesource.com/src/+/refs/heads/main/LICENSE?format=TEXT',True),('webrtc-sdk Android distribution — MIT','https://raw.githubusercontent.com/webrtc-sdk/android/main/LICENSE',False),('OkHttp, Okio, Kotlin standard library and JetBrains annotations — Apache 2.0','https://www.apache.org/licenses/LICENSE-2.0.txt',False),('Be Vietnam Pro font — SIL Open Font License 1.1','https://raw.githubusercontent.com/google/fonts/main/ofl/bevietnampro/OFL.txt',False),('BoringSSL included by WebRTC','https://boringssl.googlesource.com/boringssl/+/refs/heads/main/LICENSE?format=TEXT',True)]
for title,url,encoded in items:
 data=urllib.request.urlopen(url,timeout=30).read();text=(base64.b64decode(data)if encoded else data).decode('utf8');parts.append(title+'\nSource: '+url+'\n\n'+text)
text='Kinnect — Third-party software notices\n\nPlay build: WebRTC SDK 144.7559.09; OkHttp 4.12.0; Okio JVM 3.6.0; Kotlin 1.9.10; JetBrains annotations 13.0.\nWebsite APKs built with the legacy toolchain use OkHttp 3.12.13 and Okio 1.17.2 under the same Apache 2.0 license.\n\n'+'\n\n'+'\n\n'.join(parts)
folder=r/'android/app/src/main/assets';folder.mkdir(exist_ok=True);(folder/'THIRD_PARTY_NOTICES.txt').write_text(text,encoding='utf8');(r/'public/third-party-notices.txt').write_text(text,encoding='utf8');print('Third-party license texts bundled with app and public notice')
