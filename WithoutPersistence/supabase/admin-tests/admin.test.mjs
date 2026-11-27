import {lookupAutomaticFlight} from '../functions/flight-auto-refresh/lookup.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.env.PGLITE_MODULE||new URL('./node_modules/@electric-sql/pglite/dist/index.js',import.meta.url).pathname));
const migration=await readFile(new URL('../migrations/202611110001_admin_backoffice.sql',import.meta.url),'utf8');
const grantMigration=await readFile(new URL('../migrations/202610210001_account_entitlements.sql',import.meta.url),'utf8');
const ledgerMigration=await readFile(new URL('../migrations/202611040001_storekit_verified_ledger.sql',import.meta.url),'utf8');
const deviceMigration=await readFile(new URL('../migrations/202610220003_account_device_registry.sql',import.meta.url),'utf8');
const ids={admin:'10000000-0000-4000-8000-000000000001',ordinary:'10000000-0000-4000-8000-000000000002',other:'10000000-0000-4000-8000-000000000003',session:'20000000-0000-4000-8000-000000000001',device:'30000000-0000-4000-8000-000000000001',request:'40000000-0000-4000-8000-000000000001'};
let db;
async function claims(user=ids.admin,aal='aal2',recent=true){await db.query(`select set_config('request.jwt.claims',$1,false)`,[JSON.stringify({sub:user,aal,session_id:ids.session,amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)-(recent?0:3600)}]})]);}
async function denied(sql,args=[],pattern=/ADMIN_/){await assert.rejects(()=>db.query(sql,args),pattern);}
await test('admin backend isolation and atomic mutation regression',async t=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,created_at timestamptz default now());
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select (current_setting('request.jwt.claims',true)::jsonb->>'sub')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
 create table public.account_trial_grants(owner_id uuid);

 `);
 await db.exec(grantMigration);await db.exec(deviceMigration);await db.exec(ledgerMigration);await db.exec(migration);
 for(const [id,email] of [[ids.admin,'admin@example.invalid'],[ids.ordinary,'ordinary@example.invalid'],[ids.other,'other@example.invalid']])await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);
 await db.query('insert into auth.sessions values($1,$2,null)',[ids.session,ids.admin]);
 await db.query('insert into admin_private.principals(user_id) values($1)',[ids.admin]);
 await db.query(`insert into admin_private.bindings values($1,'trvelma-production','write')`,[ids.admin]);
 await db.query(`select public.set_account_entitlement($1,'cloud','active',null,4)`,[ids.ordinary]);
 await db.query(`insert into public.account_devices(owner_id,device_id,last_seen_at) values($1,$2,'2026-11-01T00:00:00Z')`,[ids.ordinary,ids.device]);
 await t.test('no JWT and aal1 cannot access management',async()=>{await db.query(`select set_config('request.jwt.claims','{}',false)`);await denied('select public.admin_context()');await claims(ids.admin,'aal1');await denied('select public.admin_context()',[],/MFA_REQUIRED/);});
 await t.test('ordinary user cannot escalate through supplied app id',async()=>{await db.query('insert into auth.sessions values($1,$2,null)',['20000000-0000-4000-8000-000000000002',ids.ordinary]);await claims(ids.ordinary);await denied(`select public.admin_users('trvelma-production')`);});
 await t.test('authorized context and bounded account list contain no password or business data',async()=>{await claims();const c=(await db.query('select public.admin_context() as value')).rows[0].value;assert.equal(c.applications.length,1);const data=(await db.query(`select public.admin_users('trvelma-production','ordinary',0) as value`)).rows[0].value;assert.equal(data.total,1);assert.equal(data.users[0].email,'ordinary@example.invalid');assert.equal(JSON.stringify(data).includes('password'),false);assert.equal(JSON.stringify(data).includes('phone'),false);});
 await t.test('second synthetic application is denied and cannot alias this database',async()=>{await db.exec(`insert into admin_private.applications values('synthetic','Synthetic','test','unconfigured',true)`);await db.query(`insert into admin_private.bindings values($1,'synthetic','write')`,[ids.admin]);await denied(`select public.admin_users('synthetic')`,[],/APP_FORBIDDEN/);await assert.rejects(()=>db.exec(`insert into admin_private.applications values('alias','Alias','production','local',true)`),/unique/);});
 await t.test('null application cannot bypass scoped authorization',async()=>{await denied('select public.admin_users(null)',[],/APP_FORBIDDEN/);await denied('select public.admin_audit(null)',[],/APP_FORBIDDEN/);});
 await t.test('revoked administrator and expired auth session fail',async()=>{await db.query('update admin_private.principals set enabled=false where user_id=$1',[ids.admin]);await denied('select public.admin_context()',[],/FORBIDDEN/);await db.query('update admin_private.principals set enabled=true where user_id=$1',[ids.admin]);await db.exec("update auth.sessions set not_after=now()-interval '1 minute'");await denied('select public.admin_context()',[],/SESSION_INVALID/);await db.exec('update auth.sessions set not_after=null');});
 await t.test('ordinary database role cannot read private tables or invoke unchecked helper',async()=>{await db.exec('set role authenticated');await assert.rejects(()=>db.exec('select * from admin_private.principals'),/permission denied/);await assert.rejects(()=>db.exec("select admin_private.authorize()"),/permission denied/);await db.exec('reset role');});
 const releaseArgs=['trvelma-production',ids.ordinary,ids.device,'2026-11-01T00:00:00Z',ids.request,'隔离验收释放'];
 const releaseSQL='select public.admin_release_device($1,$2,$3,$4,$5,$6) as value';
 await t.test('old MFA and read-only administrator cannot write',async()=>{await claims(ids.admin,'aal2',false);await denied(releaseSQL,releaseArgs,/RECENT_MFA/);await claims();await db.query("update admin_private.bindings set permission='read' where user_id=$1",[ids.admin]);await denied(releaseSQL,releaseArgs,/APP_FORBIDDEN/);await db.query("update admin_private.bindings set permission='write' where user_id=$1",[ids.admin]);});
 await t.test('stale last_seen causes no release or success audit',async()=>{const bad=[...releaseArgs];bad[3]='2026-10-01T00:00:00Z';await denied(releaseSQL,bad,/DEVICE_CHANGED/);assert.equal((await db.query('select revoked_at from public.account_devices')).rows[0].revoked_at,null);});
 await t.test('release is atomic, idempotent and account scoped',async()=>{const first=(await db.query(releaseSQL,releaseArgs)).rows[0].value;const second=(await db.query(releaseSQL,releaseArgs)).rows[0].value;assert.deepEqual(first,second);assert.equal(first.owner_id,ids.ordinary);assert.ok(first.revoked_at);assert.equal((await db.query("select count(*)::int as n from admin_private.audit where action='release_device'")).rows[0].n,1);const changed=[...releaseArgs];changed[1]=ids.other;await denied(releaseSQL,changed,/REQUEST_CONFLICT/);});
 await t.test('authorization writes use expected version and preserve purchase table',async()=>{const old=(await db.query('select * from public.account_entitlements where owner_id=$1',[ids.ordinary])).rows[0];const args=['trvelma-production',ids.ordinary,old.updated_at,'cloud','active','2035-01-01T00:00:00Z',5,'40000000-0000-4000-8000-000000000002','隔离验收授权'];const sql='select public.admin_set_entitlement($1,$2,$3,$4,$5,$6,$7,$8,$9) as value';const first=(await db.query(sql,args)).rows[0].value;assert.equal(first.max_devices,5);assert.deepEqual((await db.query(sql,args)).rows[0].value,first);args[7]='40000000-0000-4000-8000-000000000003';await denied(sql,args,/ENTITLEMENT_CHANGED/);assert.equal((await db.query('select count(*)::int as n from public.storekit_transactions')).rows[0].n,0);});
 await t.test('delayed verified Apple event preserves later manual grant',async()=>{const event={owner_id:ids.ordinary,environment:'Sandbox',transaction_id:'qa-t1',original_transaction_id:'qa-o1',product_id:'com.yunshengtech.travelmanager.cloud.monthly',purchased_at:'2026-11-01T00:00:00Z',expires_at:'2027-01-01T00:00:00Z',signed_at:'2026-11-11T00:00:00Z',revoked_at:null,upgraded:false,grace_expires_at:null};await db.query('select public.apply_verified_storekit_event($1)',[JSON.stringify(event)]);const grant=(await db.query('select * from public.account_entitlements where owner_id=$1',[ids.ordinary])).rows[0];assert.equal(grant.max_devices,5);assert.equal(new Date(grant.expires_at).getUTCFullYear(),2035);});
 await t.test('audit insertion failure rolls back the actual entitlement mutation',async()=>{const before=(await db.query('select * from public.account_entitlements where owner_id=$1',[ids.ordinary])).rows[0];await db.exec(`create function admin_private.reject_audit() returns trigger language plpgsql as $$begin raise exception 'AUDIT_WRITE_FAILED';end$$;create trigger fail_audit before insert on admin_private.audit for each row execute function admin_private.reject_audit();`);await denied('select public.admin_set_entitlement($1,$2,$3,$4,$5,$6,$7,$8,$9)',['trvelma-production',ids.ordinary,before.updated_at,'cloud','revoked',null,5,'40000000-0000-4000-8000-000000000004','隔离失败回滚'],/AUDIT_WRITE_FAILED/);assert.deepEqual((await db.query('select * from public.account_entitlements where owner_id=$1',[ids.ordinary])).rows[0],before);await db.exec('drop trigger fail_audit on admin_private.audit;drop function admin_private.reject_audit()');});
 await t.test('expired active grant is reported effectively expired',async()=>{await db.query("update public.account_entitlements set status='active',expires_at=now()-interval '1 day' where owner_id=$1",[ids.ordinary]);const data=(await db.query("select public.admin_users('trvelma-production','ordinary') as value")).rows[0].value;assert.equal(data.users[0].effective_status,'expired');});
 await t.test('admin pricing applies to both refresh paths and preserves in-flight reservations', async () => {
  const app = 'trvelma-production';
  const owner = ids.ordinary;
  const balance = async () => (await db.query(
   'select coalesce(sum(amount),0)::int as amount from public.flight_bean_entries where owner_id=$1', [owner]
  )).rows[0].amount;
  const reserve = async hold => (await db.query(
   'select public.reserve_flight_bean($1,$2) as held', [owner,hold]
  )).rows[0].held;
  const settle = async (hold, charge) => db.query('select public.finish_flight_bean($1,$2,$3)', [owner,hold,charge]);
  for (const file of ['202611260001_flight_beans.sql','202611270001_shared_flight_bean_wallet.sql']) {
   await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
   if (file === '202611260001_flight_beans.sql') {
    await db.query("insert into public.flight_bean_entries(owner_id,event_key,kind,amount) values($1,'qa:shared-wallet','subscription',10)",[owner]);
    assert.equal(await reserve(ids.device),true);
   }
  }
  await settle(ids.device,true);
  assert.equal(await balance(),9,'pre-migration reservation settles at its original price');
  const getSQL = 'select public.admin_flight_bean_policy($1) as value';
  const setSQL = 'select public.admin_set_flight_bean_policy($1,$2,$3,$4,$5) as value';
  await claims();
  const original = (await db.query(getSQL,[app])).rows[0].value;
  assert.equal(original.cost,2);
  const args = [app,3,original.updated_at,crypto.randomUUID(),'调整测试费率'];
  await claims(ids.ordinary);
  await denied(setSQL,args);
  await claims(ids.admin,'aal2',false);
  await denied(setSQL,args,/RECENT_MFA/);
  await claims();
  await denied(setSQL,[app,0,...args.slice(2)],/INVALID_FLIGHT_BEAN_COST/);

  const manualHold = crypto.randomUUID();
  assert.equal(await reserve(manualHold),true);
  const saved = (await db.query(setSQL,args)).rows[0].value;
  assert.equal(saved.cost,3);
  assert.deepEqual((await db.query(setSQL,args)).rows[0].value,saved);
  await denied(setSQL,[...args.slice(0,3),crypto.randomUUID(),args[4]],/POLICY_CHANGED_REFRESH/);
  assert.equal((await db.query("select count(*)::int as count from admin_private.audit where action='set_flight_bean_policy'")).rows[0].count,1);

  const rpc = async (name, params) => {
   if (name === 'reserve_flight_bean') return {data:await reserve(params.p_hold)};
   if (name === 'finish_flight_bean') return {data:(await settle(params.p_hold,params.p_charge)).rows[0].finish_flight_bean};
   assert.ok(['consume_variflight_quota_for','admit_flight_auto_attempt'].includes(name));
   return {data:true};
  };
  const query = async () => Response.json([{flightNumber:'JX2',departureAirportCode:'TPE',arrivalAirportCode:'LAX',status:'landed'}]);
  const auto = (provider=query, departure=false) => lookupAutomaticFlight({
   rpc, query:provider, charge:true, departure,
   job:{owner_id:owner,lease_id:crypto.randomUUID(),flight_number:'JX2',departure:'TPE',arrival:'LAX'}
  });
  assert.equal((await auto()).state,'landed');
  assert.equal(await balance(),6);
  assert.equal(await auto(async () => new Response(null,{status:503}),true),null);
  assert.equal(await balance(),6);
  await settle(manualHold,true);
  await settle(manualHold,true);
  assert.equal(await balance(),4,'manual hold settles once at the previous price');
  const lastHold = crypto.randomUUID();
  assert.equal(await reserve(lastHold),true);
  assert.equal(await auto(() => assert.fail('remaining available balance cannot pay for the provider')),null);
  await settle(lastHold,false);
  assert.equal((await auto(query,true)).state,'landed');
  assert.equal(await balance(),1);
 });
 await t.test('emergency disable preserves audit and revokes authenticated RPC execution',async()=>{const before=(await db.query('select count(*)::int as n from admin_private.audit')).rows[0].n;await db.exec(await readFile(new URL('../verification/20261111_admin_disable.sql',import.meta.url),'utf8'));await db.exec('set role authenticated');await assert.rejects(()=>db.exec('select public.admin_context()'),/permission denied/);await db.exec('reset role');assert.equal((await db.query('select count(*)::int as n from admin_private.audit')).rows[0].n,before);});
 await db.close();
});
