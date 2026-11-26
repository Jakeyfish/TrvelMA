import {readFile} from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';

test('verified subscription periods and first referral grant once; refunds reverse and failed refresh releases holds', async () => {
  const db = new PGlite();
  const inviter = '11111111-1111-4111-8111-111111111111';
  const monthly = '22222222-2222-4222-8222-222222222222';
  const yearly = '33333333-3333-4333-8333-333333333333';
  const sandbox = '44444444-4444-4444-8444-444444444444';
  const hold = '55555555-5555-4555-8555-555555555555';
  const ms = Date.now();
  const date = offset => new Date(ms+offset).toISOString();
  const apply = (owner, id, more={}) => db.query('select apply_verified_storekit_event($1::jsonb)',[{
    owner_id:owner,environment:'Production',transaction_id:id,original_transaction_id:id,
    product_id:'com.yunshengtech.travelmanager.cloud.monthly',purchased_at:date(-86400000),
    expires_at:date(86400000),signed_at:date(0),revoked_at:null,upgraded:false,grace_expires_at:null,...more
  }]);
  const balance = async owner => (await db.query("select coalesce(sum(amount),0)::int as beans from flight_bean_entries where owner_id=$1",[owner])).rows[0].beans;
  const assume = async owner => {
    await db.exec("set role authenticated");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
  };
  try {
    await db.exec(`
      create schema auth;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        \$\$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid\$\$;
      create role anon;create role authenticated;create role service_role;
    `);
    for (const file of ['202610210001_account_entitlements.sql','202611040001_storekit_verified_ledger.sql','202611260001_flight_beans.sql']) {
      await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
    }
    await db.query('insert into auth.users values ($1),($2),($3),($4)',[inviter,monthly,yearly,sandbox]);
    await assume(inviter);
    const code = (await db.query("select flight_bean_wallet() as info")).rows[0].info.invite_code;
    assert.equal((await db.query("select bind_flight_bean_invite($1) as bound",[code])).rows[0].bound,false);
    await db.exec("reset role");
    for(const user of [monthly,yearly,sandbox]) {
      await assume(user);
      assert.equal((await db.query("select bind_flight_bean_invite($1) as bound",[code])).rows[0].bound,true);
      assert.equal((await db.query("select flight_bean_wallet() as info")).rows[0].info.balance,0);
      await assert.rejects(db.query("select reserve_flight_bean($1,$2)",[inviter,hold]),/permission denied/);
      await db.exec("reset role");
    }
    // Apple can deliver a renewal before the original purchase is replayed.
    await apply(monthly,'11',{original_transaction_id:'10',purchased_at:date(-5000),expires_at:date(172800000)});
    assert.equal(await balance(inviter),0);
    await apply(monthly,'10');
    await apply(monthly,'10');
    await apply(monthly,'12',{original_transaction_id:'10'});
    assert.equal(await balance(monthly),40, 'restore for the same paid period must not issue a second grant');
    assert.equal(await balance(inviter),5, 'restore must not issue another invitation reward');
    await apply(yearly,'20',{product_id:'com.yunshengtech.travelmanager.cloud.yearly'});
    await apply(sandbox,'30',{environment:'Sandbox'});
    assert.equal(await balance(monthly),40);
    assert.equal(await balance(yearly),300);
    assert.equal(await balance(inviter),35);
    assert.equal(await balance(sandbox),0);
    await apply(monthly,'11',{original_transaction_id:'10',purchased_at:date(-5000),expires_at:date(172800000)});
    assert.equal(await balance(inviter),35);
    assert.equal(await balance(monthly),40);
    assert.equal((await db.query("select reserve_flight_bean($1,$2) as held",[monthly,hold])).rows[0].held,true);
    await db.query("select finish_flight_bean($1,$2,false)",[monthly,hold]);
    assert.equal(await balance(monthly),40);
    await db.query("select reserve_flight_bean($1,$2)",[monthly,hold]);
    await db.query("select finish_flight_bean($1,$2,true)",[monthly,hold]);
    await db.query("select finish_flight_bean($1,$2,true)",[monthly,hold]);
    assert.equal(await balance(monthly),39);
    const expiredHold = '66666666-6666-4666-8666-666666666666';
    await db.query("select reserve_flight_bean($1,$2)",[monthly,expiredHold]);
    await db.query("update flight_bean_holds set expires_at=now()-interval '1 second' where id=$1",[expiredHold]);
    assert.equal((await db.query("select finish_flight_bean($1,$2,true) as charged",[monthly,expiredHold])).rows[0].charged,false);
    assert.equal(await balance(monthly),39);

    // One remaining bean can be reserved by only one request.
    await db.query("insert into flight_bean_entries(owner_id,event_key,kind,amount) values($1,'qa:aggregate-spend','refresh',-299)",[yearly]);
    assert.equal((await db.query("select reserve_flight_bean($1,$2) as held",[yearly,hold])).rows[0].held,true);
    assert.equal((await db.query("select reserve_flight_bean($1,$2) as held",[yearly,expiredHold])).rows[0].held,false);
    await db.query("select finish_flight_bean($1,$2,true)",[yearly,hold]);
    assert.equal(await balance(yearly),0);
    assert.equal((await db.query("select reserve_flight_bean($1,$2) as held",[yearly,expiredHold])).rows[0].held,false);

    await apply(monthly,'10',{revoked_at:date(500),signed_at:date(1000)});
    await apply(monthly,'10',{revoked_at:date(500),signed_at:date(1000)});
    assert.equal(await balance(monthly),19);
    assert.equal(await balance(inviter),30);
    await assume(monthly);
    assert.equal((await db.query("select bind_flight_bean_invite($1) as bound",[code])).rows[0].bound,false);
    await db.exec("reset role");
  } finally { await db.close(); }
});
