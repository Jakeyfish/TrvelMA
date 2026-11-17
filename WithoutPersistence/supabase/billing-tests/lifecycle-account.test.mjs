import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const owner='86361373-d4ba-4fc6-8f38-420367b6484e',other='11111111-1111-4111-8111-111111111111';
const prepare=await readFile(new URL('../verification/20261111_lifecycle_test_account_prepare.sql',import.meta.url),'utf8');
const restore=await readFile(new URL('../verification/20261111_lifecycle_test_account_restore_trial.sql',import.meta.url),'utf8');
async function fixture(run){
 const db=new PGlite();
 try {
  await db.exec(`create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
   create table public.account_entitlements(owner_id uuid primary key,edition text,status text,expires_at timestamptz,max_devices int,updated_at timestamptz);
   create table public.trips(owner_id uuid);create table public.customers(owner_id uuid);
   create table public.storekit_transactions(owner_id uuid,environment text);create table public.storekit_account_state(owner_id uuid);
   insert into auth.users values('${owner}','ystechnology02@yahoo.com',now());
   insert into public.account_entitlements values('${owner}','cloud','active','2026-11-26 05:11:10.214792+00',4,now()),('${other}','cloud','active',null,4,now());`);
  await run(db);
 } finally { await db.close(); }
}
const grant=async db=>(await db.query('select status,expires_at,max_devices from public.account_entitlements where owner_id=$1',[owner])).rows[0];
test('QA preparation expires only target; recovery restores original trial without deleting ledger',()=>fixture(async db=>{
 await db.exec(prepare);assert.equal((await grant(db)).status,'expired');
 assert.ok(new Date((await grant(db)).expires_at)<new Date());
 assert.equal((await db.query('select status from public.account_entitlements where owner_id=$1',[other])).rows[0].status,'active');
 await db.query("insert into public.storekit_transactions values($1,'Sandbox')",[owner]);
 await db.exec(restore);assert.equal((await grant(db)).status,'active');
 assert.equal(new Date((await grant(db)).expires_at).toISOString(),'2026-11-26T05:11:10.214Z');
 assert.equal((await db.query('select count(*)::int n from public.storekit_transactions')).rows[0].n,1);
}));
for(const [name,setup,error] of [
 ['wrong identity',`update auth.users set email='other@example.invalid'`,'QA_IDENTITY_MISMATCH'],
 ['business records',`insert into public.trips values('${owner}')`,'QA_ACCOUNT_NOT_EMPTY'],
 ['changed trial',`update public.account_entitlements set max_devices=5 where owner_id='${owner}'`,'QA_BASELINE_CHANGED'],
 ['existing billing state',`insert into public.storekit_account_state values('${owner}')`,'QA_ACCOUNT_NOT_EMPTY']
]) test('QA preparation rejects '+name+' atomically',()=>fixture(async db=>{
 await db.exec(setup);await assert.rejects(db.exec(prepare),new RegExp(error));await db.exec('rollback');
 assert.equal((await grant(db)).status,'active');
}));
test('QA recovery cannot override a production purchase',()=>fixture(async db=>{
 await db.exec(prepare);await db.query("insert into public.storekit_transactions values($1,'Production')",[owner]);
 await assert.rejects(db.exec(restore),/DO_NOT_OVERWRITE_PRODUCTION_PURCHASE/);await db.exec('rollback');
 assert.equal((await grant(db)).status,'expired');
}));
