"""Publish a verified signed APK and source bundle using the existing GitHub login."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--apk',required=True,type=Path);p.add_argument('--source-zip',required=True,type=Path);p.add_argument('--branch',required=True);args=p.parse_args()
metadata=json.loads((root/'docs/cloud-handoff/artifact.json').read_text(encoding='utf8'));version=metadata['version'];tag='v'+version;repo='vuanh97nd/Kinnect'
if args.apk.name!=metadata['filename'] or hashlib.sha256(args.apk.read_bytes()).hexdigest()!=metadata['sha256']:raise RuntimeError('APK differs from verified artifact')
env=os.environ.copy();env['GIT_TERMINAL_PROMPT']='0'
def run(*cmd,stdin=None):
 if cmd[0]=='git':cmd=('git','-c','safe.directory='+str(root),*cmd[1:])
 out=subprocess.run(list(map(str,cmd)),cwd=root,env=env,input=stdin,text=True,capture_output=True,timeout=180)
 if out.returncode:raise RuntimeError((out.stderr or out.stdout or 'Command failed').strip())
 return out.stdout.strip()
if not env.get('GH_TOKEN') and not env.get('GITHUB_TOKEN'):
 fields=dict(line.split('=',1) for line in run('git','-c','credential.interactive=false','credential','fill',stdin='protocol=https\nhost=github.com\n\n').splitlines() if '=' in line)
 if not fields.get('password'):raise RuntimeError('GitHub login required')
 env['GH_TOKEN']=fields['password']
sha=run('git','rev-parse',args.branch)
latest=json.loads(run('gh','api','repos/'+repo+'/releases/latest'))
def semver(value):return tuple(map(int,value.removeprefix('v').split('.')))
if semver(latest['tag_name'])>=semver(tag):raise RuntimeError('Release is already published or a newer version exists; do not replace it')
run('git','-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','https://github.com/'+repo+'.git',args.branch+':'+args.branch)
releases=json.loads(run('gh','api','repos/'+repo+'/releases?per_page=100'))
release=next((item for item in releases if item['tag_name']==tag),None)
if release:
 if not release.get('draft'):raise RuntimeError('Existing published release must not be replaced')
 asset=next(a for a in release['assets'] if a['name']==args.apk.name)
 if asset.get('digest')!='sha256:'+metadata['sha256']:raise RuntimeError('Existing draft APK differs; do not replace it')
 run('gh','release','edit',tag,'--repo',repo,'--target',sha,'--notes-file',root/('docs/releases/'+tag+'.md'))
 run('gh','release','upload',tag,'--repo',repo,'--clobber',args.source_zip)
else:
 run('gh','release','create',tag,'--repo',repo,'--draft','--target',sha,'--title','Kinnect '+version+' — Hồ sơ và AI trực tiếp','--notes-file',root/('docs/releases/'+tag+'.md'),args.apk,args.apk.with_suffix('.apk.sha256'),args.source_zip)
 releases=json.loads(run('gh','api','repos/'+repo+'/releases?per_page=100'))
 release=next(item for item in releases if item['tag_name']==tag)
release=json.loads(run('gh','api','repos/'+repo+'/releases/'+str(release['id'])));asset=next(a for a in release['assets'] if a['name']==args.apk.name)
if asset.get('digest')!='sha256:'+metadata['sha256']:raise RuntimeError('Uploaded checksum mismatch; release remains draft')
run('gh','release','edit',tag,'--repo',repo,'--draft=false','--latest')
print(run('gh','release','view',tag,'--repo',repo,'--json','url','--jq','.url'))
