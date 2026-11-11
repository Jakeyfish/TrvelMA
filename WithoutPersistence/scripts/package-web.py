#!/usr/bin/env python3
"""Package only production static files for Cloudflare Pages direct upload.
No repository, docs, tests, QA fixtures, sessions or private keys enter the ZIP.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,tempfile,zipfile
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--archive',type=Path,required=True);args=parser.parse_args()
root=Path(__file__).resolve().parents[1]/'web'
base=Path(tempfile.mkdtemp(prefix='trvelma-cloudflare-release-'));dist=base/'dist';dist.mkdir()
files=['index.html','app.js','parity.mjs','localization.mjs','styles.css','workspace.css','privacy.html','support.html','assets/airport-crosswalk.json']
files += [str(path.relative_to(root)) for path in sorted((root/'assets/icons').glob('*.png')) if path.stem.replace('-', '').isalnum()]
files.append('assets/icons/manifest.json')
manifest={}
for name in files:
 source=root/name;data=source.read_bytes()
 if b'PRIVATE KEY-----' in data or b'sb_secret_' in data:raise SystemExit('Refusing private credentials in static release')
 target=dist/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 manifest[name]=hashlib.sha256(data).hexdigest()
headers='''/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
  Cache-Control: no-cache
  Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://lbdfqzeiweqbsklklcqr.supabase.co; connect-src 'self' data: blob: https://lbdfqzeiweqbsklklcqr.supabase.co; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
'''
(dist/'_headers').write_text(headers);manifest['_headers']=hashlib.sha256(headers.encode()).hexdigest()
args.archive.parent.mkdir(parents=True,exist_ok=True)
if args.archive.exists():raise SystemExit('Archive already exists; choose a new output path')
with zipfile.ZipFile(args.archive,'w',zipfile.ZIP_DEFLATED) as z:
 for name in manifest:z.write(dist/name,name)
info={'dist':str(dist),'archive':str(args.archive),'files_sha256':manifest,'archive_sha256':hashlib.sha256(args.archive.read_bytes()).hexdigest(),'contains_real_orders':False,'contains_auth_sessions':False,'contains_private_keys':False,'public_frontend_contains_existing_supabase_publishable_key':True,'site_name_candidate':'trvelma','name_availability_checked':False,'deployed':False}
(base/'release-manifest.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(info,ensure_ascii=False,indent=2))
