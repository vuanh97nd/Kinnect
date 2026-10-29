"""Publish an already-reviewed cloud handoff using the existing GitHub Git login.
Does not print or store credentials. Does not build or replace the signed APK.
"""
import argparse, hashlib, json, os, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--apk',required=True,type=Path);p.add_argument('--source-zip',required=True,type=Path);args=p.parse_args()
branch='handoff/kinnect-1.0.4-cloud';repo='vuanh97nd/Kinnect';tag='v1.0.4'
env=os.environ.copy();env['GIT_TERMINAL_PROMPT']='0'
def run(*cmd,stdin=None):
 out=subprocess.run(list(map(str,cmd)),cwd=root,env=env,input=stdin,text=True,capture_output=True)
 if out.returncode:raise RuntimeError((out.stderr or out.stdout or 'Command failed').strip())
 return out.stdout.strip()
if not env.get('GH_TOKEN') and not env.get('GITHUB_TOKEN'):
 reply=run('git','-c','credential.interactive=false','credential','fill',stdin='protocol=https\nhost=github.com\n\n')
 fields=dict(line.split('=',1) for line in reply.splitlines() if '=' in line)
 if not fields.get('password'):raise RuntimeError('GitHub sign-in is required')
 env['GH_TOKEN']=fields['password']
metadata=json.loads((root/'docs/cloud-handoff/artifact.json').read_text(encoding='utf8'))
if hashlib.sha256(args.apk.read_bytes()).hexdigest()!=metadata['sha256']:raise RuntimeError('APK does not match the reviewed build')
sha=run('git','rev-parse',branch)
run('git','-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','https://github.com/'+repo+'.git',branch+':'+branch)
latest=json.loads(run('gh','api','repos/'+repo+'/releases/latest'))
if latest.get('tag_name') not in ['v1.0.3','v1.0.4']:raise RuntimeError('Latest release has changed; review before publishing this older handoff')
if latest.get('tag_name')==tag:raise RuntimeError('v1.0.4 already exists; verify its assets instead of replacing them')
checksum=args.apk.with_suffix('.apk.sha256')
run('gh','release','create',tag,'--repo',repo,'--draft','--target',sha,'--title','Kinnect 1.0.4 — Căn chữ và bàn giao đám mây','--notes-file',root/'docs/releases/v1.0.4.md',args.apk,checksum,args.source_zip)
release=json.loads(run('gh','api','repos/'+repo+'/releases/tags/'+tag));asset=next(a for a in release['assets'] if a['name']==args.apk.name)
if asset.get('digest')!='sha256:'+metadata['sha256']:raise RuntimeError('Uploaded APK checksum mismatch; release remains a draft')
run('gh','release','edit',tag,'--repo',repo,'--draft=false','--latest')
print(run('gh','release','view',tag,'--repo',repo,'--json','url','--jq','.url'))
