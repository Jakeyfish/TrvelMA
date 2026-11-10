import {before,after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite(),owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
const iso=d=>new Date(Date.now()+d*86400000).toISOString();
const event=(more={})=>({owner_id:owner,environment:'Sandbox',transaction_id:'100',original_transaction_id:'90',product_id:'com.yunshengtech.travelmanager.cloud.monthly',purchased_at:iso(-1),expires_at:iso(30),signed_at:iso(0),revoked_at:null,upgraded:false,grace_expires_at:null,...more});
const apply=e=>db.query('select public.apply_verified_storekit_event($1::jsonb) as result',[JSON.stringify(e)]);
const grant=async()=> (await db.query('select * from public.account_entitlements where owner_id=$1',[owner])).rows[0];
before(async()=>{await db.exec("create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql as 'select null::uuid';create role anon;create role authenticated;create role service_role;");for(const f of ['202610210001_account_entitlements.sql','202611040001_storekit_verified_ledger.sql'])await db.exec(await readFile(new URL('../migrations/'+f,import.meta.url),'utf8'));});
beforeEach(async()=>{await db.exec('truncate public.storekit_transactions,public.storekit_subscription_owners,public.storekit_account_state,public.account_entitlements,auth.users cascade');await db.query('insert into auth.users values($1),($2)',[owner,other]);});after(()=>db.close());
test('purchase grants exact expiry and 4 devices',async()=>{const e=event();await apply(e);const g=await grant();assert.equal(g.edition,'cloud');assert.equal(g.status,'active');assert.equal(g.max_devices,4);assert.equal(new Date(g.expires_at).toISOString(),e.expires_at);});
test('duplicate is idempotent',async()=>{const e=event();await apply(e);const first=await grant();await apply(e);assert.equal(new Date((await grant()).updated_at).getTime(),new Date(first.updated_at).getTime());assert.equal((await db.query('select count(*)::int n from public.storekit_transactions')).rows[0].n,1);});
test('subscription chain cannot move account',async()=>{await apply(event());await assert.rejects(apply(event({owner_id:other,transaction_id:'101'})),/TRANSACTION_ACCOUNT_CONFLICT/);});
test('refund and stale replay',async()=>{const e=event({signed_at:iso(-0.02)});await apply(e);await apply({...e,signed_at:iso(-0.01),revoked_at:iso(-0.01)});assert.equal((await grant()).status,'expired');await apply(e);assert.equal((await grant()).status,'expired');});
test('refund restores remaining trial',async()=>{const expiry=iso(5);await db.query("select public.set_account_entitlement($1,'cloud','active',$2,4)",[owner,expiry]);const e=event({signed_at:iso(-0.01)});await apply(e);await apply({...e,signed_at:iso(0),revoked_at:iso(0)});assert.equal(new Date((await grant()).expires_at).toISOString(),expiry);});
test('new renewal survives older period refund',async()=>{const e=event({signed_at:iso(-0.02)});await apply(e);await apply(event({transaction_id:'101',expires_at:iso(60)}));await apply({...e,signed_at:iso(0),revoked_at:iso(0)});assert.ok(new Date((await grant()).expires_at).getTime()>Date.now()+59*86400000);});
test('manual permanent grant preserved',async()=>{await db.query("select public.set_account_entitlement($1,'sync','active',null,6)",[owner]);await apply(event());const g=await grant();assert.equal(g.edition,'sync');assert.equal(g.expires_at,null);assert.equal(g.max_devices,6);});
test('local baseline does not hide cloud and returns after refund',async()=>{await db.query("select public.set_account_entitlement($1,'local','active',null,1)",[owner]);const e=event({signed_at:iso(-0.01)});await apply(e);assert.equal((await grant()).edition,'cloud');await apply({...e,signed_at:iso(0),revoked_at:iso(0)});assert.equal((await grant()).edition,'local');});
test('manual revoke cannot be reactivated',async()=>{await db.query("select public.set_account_entitlement($1,'cloud','revoked',null,4)",[owner]);await assert.rejects(apply(event()),/ACCOUNT_REVOKED/);assert.equal((await grant()).status,'revoked');});
test('sandbox and production do not merge',async()=>{await apply(event());await assert.rejects(apply(event({environment:'Production',transaction_id:'101'})),/ENVIRONMENT_CONFLICT/);});
test('grace has bounded expiry',async()=>{await apply(event({purchased_at:iso(-30),expires_at:iso(-1),grace_expires_at:iso(2),signed_at:iso(-0.01)}));assert.equal((await grant()).status,'grace');await apply(event({purchased_at:iso(-30),expires_at:iso(-1)}));assert.equal((await grant()).status,'expired');});
test('client cannot call granting RPC',async()=>{await db.exec('set role authenticated');try{await assert.rejects(apply(event()),/permission denied/);}finally{await db.exec('reset role');}});
test('account deletion cascades ledger',async()=>{await apply(event());await db.query('delete from auth.users where id=$1',[owner]);assert.equal((await db.query('select count(*)::int n from public.storekit_transactions')).rows[0].n,0);});
test('delayed events after deletion are ignored without recreating account or grants',async()=>{
 const e=event();await apply(e);await db.query('delete from auth.users where id=$1',[owner]);
 for(const next of [e,event({transaction_id:'101'}),event({revoked_at:iso(0)})]){
  assert.deepEqual((await apply(next)).rows[0].result,{recorded:false,ignored:'ACCOUNT_DELETED'});
 }
 for(const table of ['storekit_transactions','storekit_account_state','storekit_subscription_owners','account_entitlements']){
  assert.equal((await db.query(`select count(*)::int n from public.${table} where owner_id=$1`,[owner])).rows[0].n,0);
 }
 assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[owner])).rows[0].n,0);
});
test('refund restores exact local device allowance',async()=>{
 await db.query("select public.set_account_entitlement($1,'local','active',null,1)",[owner]);
 const e=event({signed_at:iso(-0.01)});await apply(e);assert.equal((await grant()).max_devices,4);
 await apply({...e,signed_at:iso(0),revoked_at:iso(0)});
 assert.equal((await grant()).edition,'local');assert.equal((await grant()).max_devices,1);
});
test('later manual grant survives refund of existing subscription',async()=>{
 const e=event({signed_at:iso(-0.01)});await apply(e);
 await db.query("select public.set_account_entitlement($1,'sync','active',null,6)",[owner]);
 await apply({...e,signed_at:iso(0),revoked_at:iso(0)});
 const g=await grant();assert.equal(g.edition,'sync');assert.equal(g.expires_at,null);assert.equal(g.max_devices,6);
});
test('manual grant with identical timestamp is still detected by its content',async()=>{
 const e=event({signed_at:iso(-0.01)});await apply(e);
 await db.query("update public.account_entitlements set edition='sync',max_devices=6,expires_at=null where owner_id=$1",[owner]);
 await apply({...e,signed_at:iso(0),revoked_at:iso(0)});
 const g=await grant();assert.equal(g.edition,'sync');assert.equal(g.expires_at,null);assert.equal(g.max_devices,6);
});
test('missing environment cannot reach the ledger',async()=>{
 await assert.rejects(apply(event({environment:null})),/INVALID_ENVIRONMENT/);
 assert.equal(await grant(),undefined);
});
test('upgraded old period does not outlive replacement subscription',async()=>{
 const old=event({expires_at:iso(90),signed_at:iso(-0.02)});await apply(old);
 await apply({...old,upgraded:true,signed_at:iso(-0.01)});
 await apply(event({transaction_id:'101',product_id:'com.yunshengtech.travelmanager.cloud.yearly',expires_at:iso(30)}));
 const g=await grant();assert.equal(g.status,'active');
 assert.ok(new Date(g.expires_at).getTime()<Date.now()+31*86400000);
});
test('newer verified refund reversal restores period but stale replay cannot',async()=>{
 const e=event({signed_at:iso(-0.03)});await apply(e);
 await apply({...e,signed_at:iso(-0.02),revoked_at:iso(-0.02)});
 await apply(e);assert.equal((await grant()).status,'expired');
 await apply({...e,signed_at:iso(-0.01),revoked_at:null});
 assert.equal((await grant()).status,'active');
});
