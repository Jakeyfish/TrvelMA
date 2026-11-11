#!/usr/bin/env python3
"""Render actual admin UI against memory-only fixtures, never production auth/data."""
from pathlib import Path
import shutil,tempfile,http.server,functools,argparse
p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=4280);args=p.parse_args()
source=Path(__file__).resolve().parents[1]/'admin';root=Path(tempfile.mkdtemp(prefix='trvelma-admin-qa-'))
for name in ['index.html','admin.css','admin.js','core.mjs','mfa.mjs']:shutil.copy2(source/name,root/name)
s=(root/'admin.js').read_text();assert s.endswith('login();\n')
s=s[:-len('login();\n')]+'''
window.fetch=async()=>{throw Error('QA 网络已阻断');};
const qaUsers=[
{id:'qa-review',purpose:'review',email:'review@example.invalid',created_at:'2026-11-01T08:00:00Z',edition:'cloud',status:'active',effective_status:'active',expires_at:'2026-11-17T05:43:43Z',max_devices:4,active_devices:0,has_trial_history:true,updated_at:'2026-11-01T08:00:00Z'},
{id:'qa-development',purpose:'development',email:'development@example.invalid',created_at:'2026-11-01T08:00:00Z',edition:'cloud',status:'active',effective_status:'active',expires_at:null,max_devices:4,active_devices:2,updated_at:'2026-11-01T08:00:00Z'},
{id:'qa-expired',email:'expired@example.invalid',created_at:'2026-11-01T08:00:00Z',edition:'cloud',status:'active',effective_status:'expired',expires_at:'2026-11-02T05:43:43Z',max_devices:4,active_devices:0,updated_at:'2026-11-01T08:00:00Z'}];
const qaDevices=[{device_id:'qa-device-ipad',device_type:'iPad',last_seen_at:'2026-11-10T08:00:00Z',registered_at:'2026-11-01T08:00:00Z',revoked_at:null}];const qaAudit=[];
rpc=async(name,args={})=>{
if(name==='admin_context')return {applications:[{id:'qa-only',name:'云盛行程管家 · 合成资料',environment:'isolated',permission:'write'}]};
if(name==='admin_users'){const users=qaUsers.filter(u=>u.email.includes(args.p_search||''));return {total:users.length,users};}
if(name==='admin_user_detail')return {entitlement:qaUsers.find(u=>u.id===args.p_owner),devices:qaDevices,transactions:[{environment:'Sandbox',product_id:'cloud.monthly',purchased_at:'2026-11-01T00:00:00Z',expires_at:'2026-12-01T00:00:00Z'}]};
if(name==='admin_audit')return qaAudit;
if(name==='admin_release_device'){qaDevices[0].revoked_at=new Date().toISOString();qaAudit.push({id:1,occurred_at:new Date().toISOString(),actor:'qa-admin',target:args.p_owner,action:'release_device',reason:args.p_reason});return {};}
if(name==='admin_set_entitlement'){Object.assign(qaUsers.find(u=>u.id===args.p_owner),{edition:args.p_edition,status:args.p_status,max_devices:args.p_devices,expires_at:args.p_expiry});return {};}
throw Error('未配置的 QA 操作');};
user={email:'admin@example.invalid'};token='QA-NOT-A-REAL-TOKEN';await authenticated();
const banner=document.createElement('div');banner.textContent='隔离 QA · 合成资料 · 外网请求已阻断';banner.style.cssText='position:fixed;bottom:0;left:0;background:#fff1b6;padding:7px;z-index:10';document.body.append(banner);
'''
(root/'admin.js').write_text(s)
print(f'QA root: {root}\nURL: http://127.0.0.1:{args.port}',flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1',args.port),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(root))).serve_forever()
