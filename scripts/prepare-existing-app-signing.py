"""Prepare a password-protected local copy for Play's existing-key import.
Does not alter the website keystore or send keys/passwords anywhere.
"""
from pathlib import Path
import subprocess,secrets,os,hashlib
r=Path(__file__).resolve().parents[1];java=next((r/'work/android-tools/jdk').glob('jdk-*'))/'bin';private=r/'work/play-signing';private.mkdir(exist_ok=True);key=private/'existing-app-signing.jks';password=private/'existing-app-store-password.txt';env=os.environ.copy();env['KINNECT_OLD_PASS']='android'
if not key.exists():
 password.write_text(secrets.token_urlsafe(40),encoding='utf8');env['KINNECT_EXISTING_PASS']=password.read_text();subprocess.run([str(java/'keytool.exe'),'-importkeystore','-srckeystore',str(r/'android/debug.keystore'),'-srcstorepass:env','KINNECT_OLD_PASS','-srckeypass:env','KINNECT_OLD_PASS','-srcalias','androiddebugkey','-destkeystore',str(key),'-deststoretype','JKS','-deststorepass:env','KINNECT_EXISTING_PASS','-destkeypass:env','KINNECT_EXISTING_PASS','-destalias','kinnect-existing','-noprompt'],env=env,check=True,capture_output=True)
env['KINNECT_EXISTING_PASS']=password.read_text();certificate=subprocess.run([str(java/'keytool.exe'),'-exportcert','-keystore',str(key),'-storepass:env','KINNECT_EXISTING_PASS','-alias','kinnect-existing'],env=env,check=True,capture_output=True).stdout
expected='d8809c1e21f00ccf96984b37123d3d916d2e103bfa1dc2032043f47bb3b9988d'
if hashlib.sha256(certificate).hexdigest()!=expected:raise RuntimeError('Existing signing certificate mismatch')
print('Protected local signing copy prepared; original website key unchanged; public certificate fingerprint verified.')
