#!/usr/bin/env python3
"""Package standalone admin assets; no sessions, fixtures or server secrets."""
from pathlib import Path
import argparse,tempfile,json,hashlib,zipfile
p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]/'admin';dist=Path(tempfile.mkdtemp(prefix='trvelma-admin-release-'))/'dist';dist.mkdir()
files=['index.html','admin.css','admin.js','core.mjs','mfa.mjs'];manifest={}
for name in files:
 data=(root/name).read_bytes()
 if any(x in data for x in [b'sb_secret_',b'PRIVATE KEY-----',b'QA-NOT-A-REAL-TOKEN']):raise SystemExit('Unsafe release content')
 (dist/name).write_bytes(data);manifest[name]=hashlib.sha256(data).hexdigest()
headers="""/*
  Cache-Control: no-store
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: no-referrer
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src https://lbdfqzeiweqbsklklcqr.supabase.co; img-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'
"""
(dist/'_headers').write_text(headers);manifest['_headers']=hashlib.sha256(headers.encode()).hexdigest()
a.archive.parent.mkdir(parents=True,exist_ok=True)
if a.archive.exists():raise SystemExit('Archive already exists')
with zipfile.ZipFile(a.archive,'w',zipfile.ZIP_DEFLATED) as z:
 for name in manifest:z.write(dist/name,name)
print(json.dumps({'dist':str(dist),'archive':str(a.archive),'sha256':manifest,'archive_sha256':hashlib.sha256(a.archive.read_bytes()).hexdigest(),'backend_enabled':False,'admin_principal_created':False},ensure_ascii=False,indent=2))
