import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { selectFlightUpdate } from '../functions/flight-auto-refresh/selection.mjs';

test('worker preserves real arrival fields and selects only the booked leg', () => {
  const job = {flight_number:'3U3838', departure:'LAX', arrival:'HGH'};
  const leg = {FlightNo:'3U3838', FlightDepcode:'LAX', FlightArrcode:'HGH',
    FlightArrtimePlanDate:'2026-12-01 04:10:00', FlightArrtimeReadyDate:'2026-12-01 04:06:00'};
  const wrong = {...leg, FlightDepcode:'HGH', FlightArrcode:'TFU', FlightArrtimeDate:'2026-12-01 08:00:00'};
  const text = JSON.stringify({result:{content:[{type:'text', text:JSON.stringify([wrong, leg])}]}});
  assert.deepEqual(selectFlightUpdate('data: '+text, job), {state:'tracking', selected:{
    scheduledArrival:leg.FlightArrtimePlanDate, estimatedArrival:leg.FlightArrtimeReadyDate, estimatedArrivalTime:leg.FlightArrtimeReadyDate
  }});
  assert.equal(selectFlightUpdate([wrong], job), null);
  assert.equal(selectFlightUpdate({...leg, FlightArrtimeDate:'2026-12-01 04:08:00'}, job).state, 'landed');
});

test('scheduled checks share a claim, follow revised ETA and do not alter pickup time', async () => {
  const db = new PGlite();
  const owner = '11111111-1111-4111-8111-111111111111';
  const expired = '22222222-2222-4222-8222-222222222222';
  try {
    await db.exec(`
      create schema auth;
      create table auth.users (id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        \$\$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid\$\$;
      create role anon; create role authenticated; create role service_role;
      grant usage on schema auth to authenticated;
    `);
    for (const file of [
      '202610180001_initial_network_schema.sql',
      '202610210001_account_entitlements.sql',
      '202610220001_variflight_proxy_quota.sql',
      '202610220002_variflight_global_quota.sql',
      '202610220003_account_device_registry.sql',
      '202610220005_trip_flight_selection_snapshot.sql',
      '202611250001_flight_auto_airports.sql',
      '202611250002_flight_auto_refresh.sql',
      '202611260002_flight_departure_tracking.sql',
      '202611260003_flight_push.sql'
    ]) await db.exec(await readFile(new URL('../migrations/'+file, import.meta.url), 'utf8'));
    await db.query('insert into auth.users values ($1),($2)', [owner,expired]);
    await db.query("insert into account_entitlements(owner_id,edition,status,expires_at) values ($1,'cloud','active',null),($2,'cloud','active',now()-interval '1 day')",[owner,expired]);
    const timestamps = (await db.query(`
      select to_char(now() at time zone 'America/Los_Angeles' + interval '50 minutes','YYYY-MM-DD HH24:MI:SS') as plan,
             to_char(now() at time zone 'America/Los_Angeles' + interval '80 minutes','YYYY-MM-DD HH24:MI:SS') as delay,
             to_char(now() at time zone 'America/Los_Angeles' - interval '5 minutes','YYYY-MM-DD HH24:MI:SS') as arrived
    `)).rows[0];
    const snapshot = {flightNumber:'JX2', flightDate:new Date().toISOString().slice(0,10), formatVersion:2,
      selected:{departureAirport:'TPE',arrivalAirport:'LAX',scheduledArrival:timestamps.plan}};
    for (const id of [owner,owner,expired]) {
      await db.query(`insert into trips(id,owner_id,service_type,order_source,appointment_date,appointment_time,flight_info,flight_date,flight_selection_snapshot)
                     values(gen_random_uuid(),$1,'接机','普通订单',now(),now(), 'JX2', now(), $2)`,[id,snapshot]);
    }
    assert.equal((await db.query("select has_function_privilege('authenticated','public.claim_flight_auto_jobs(integer)','execute') as allowed")).rows[0].allowed,false);
    await db.exec("set role authenticated");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [owner]);
    assert.deepEqual((await db.query("select flight_auto_preferences() as prefs")).rows[0].prefs,{international:60,domestic:40,followup:3});
    await db.query("select flight_auto_preferences(45::smallint,40::smallint,3::smallint)");
    await db.exec("reset role");
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0);
    await db.query("update user_settings set flight_international_lead=65 where owner_id=$1",[owner]);
    const [first] = (await db.query("select * from claim_flight_auto_jobs()")).rows;
    assert.equal(first.stage,1);
    assert.equal(first.owner_id,owner);
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0);
    const original = (await db.query("select appointment_time from trips where owner_id=$1 order by id",[owner])).rows;
    await db.query("select finish_flight_auto_job($1,$2,'tracking',now())",[first.lease_id,{estimatedArrival:timestamps.delay}]);
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0);
    await db.query("update trips set flight_selection_snapshot=jsonb_set(flight_selection_snapshot,'{selected,estimatedArrival}',to_jsonb($2::text)) where owner_id=$1",[owner,timestamps.arrived]);
    const [followup] = (await db.query("select * from claim_flight_auto_jobs()")).rows;
    assert.equal(followup.stage,2);
    await db.query("select finish_flight_auto_job($1,$2,'landed',now())",[followup.lease_id,{actualArrival:timestamps.arrived,status:'landed'}]);
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0);
    const rows = (await db.query("select appointment_time,flight_selection_snapshot->'selected' as flight from trips where owner_id=$1 order by id",[owner])).rows;
    assert.deepEqual(rows.map(({appointment_time})=>({appointment_time})),original);
    assert.ok(rows.every(row=>row.flight.automaticRefreshState==='landed' && row.flight.actualArrival===timestamps.arrived));
    assert.equal((await db.query("select count(*)::int n from trips where owner_id=$1 and flight_selection_snapshot->'selected' ? 'automaticRefreshState'",[expired])).rows[0].n,0);
    assert.equal((await db.query("select count(*)::int n from flight_auto_jobs where completed_stage=2 and actual_at is not null")).rows[0].n,1);
    assert.equal((await db.query("select flight_auto_timestamp('2026-07-01 12:00','America/Los_Angeles')::text as time")).rows[0].time, '2026-07-01 19:00:00+00');

    const domestic = {...snapshot, flightNumber:'UA42',selected:{departureAirport:'SFO',arrivalAirport:'LAX',scheduledArrival:timestamps.plan}};
    await db.query(`insert into trips(id,owner_id,service_type,order_source,appointment_date,appointment_time,flight_info,flight_date,flight_selection_snapshot)
                     values(gen_random_uuid(),$1,'接机','普通订单',now(),now(), 'UA42', now(), $2)`,[owner,domestic]);
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0, "domestic default is 40 minutes");
    await db.query("update user_settings set flight_domestic_lead=55, flight_followup_delay=0 where owner_id=$1",[owner]);
    const [domesticFirst] = (await db.query("select * from claim_flight_auto_jobs()")).rows;
    assert.equal(domesticFirst.stage,1);
    await db.query("select finish_flight_auto_job($1,$2,'tracking',now())",[domesticFirst.lease_id,{estimatedArrival:timestamps.arrived,status:'airborne'}]);
    const [domesticFollowup] = (await db.query("select * from claim_flight_auto_jobs()")).rows;
    assert.equal(domesticFollowup.stage,2);
    await db.query("select finish_flight_auto_job($1,null,'unconfirmed',now())",[domesticFollowup.lease_id]);
    const pending = (await db.query("select flight_selection_snapshot->'selected' as flight from trips where flight_info = 'UA42'")).rows[0].flight;
    assert.equal(pending.automaticRefreshState,'unconfirmed');
    assert.equal(pending.status,'airborne');
    assert.equal((await db.query("select * from claim_flight_auto_jobs()")).rows.length,0);


    const device='33333333-3333-4333-8333-333333333333';
    await db.query("insert into account_devices(owner_id,device_id,device_type) values($1,$2,'iPhone')",[owner,device]);
    await db.exec("set role authenticated");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
    assert.equal((await db.query("select set_flight_push_device($1,$2,'development') as registered",[device,'a'.repeat(64)])).rows[0].registered,true);
    await db.exec("reset role");
    const departing = {...snapshot,flightNumber:'UA60',
      selected:{departureAirport:'SFO',arrivalAirport:'LAX',scheduledDeparture:timestamps.arrived,scheduledArrival:timestamps.plan}};
    await db.query(`insert into trips(id,owner_id,service_type,order_source,appointment_date,appointment_time,flight_info,flight_date,flight_selection_snapshot,customer_name)
                    values(gen_random_uuid(),$1,'接机','普通订单',now(),now(), 'UA60', now(), $2,'QA Passenger')`, [owner,departing]);
    const [departureFirst] = (await db.query("select * from claim_flight_departure_jobs()")).rows;
    assert.equal(departureFirst.stage,1);
    const admit = async lease => (await db.query("select admit_flight_auto_attempt($1,true) as admitted",[lease])).rows[0].admitted;
    assert.equal(await admit(departureFirst.lease_id),true);
    assert.equal(await admit(departureFirst.lease_id),false);
    await db.query("update flight_auto_jobs set departure_lease_until=now()-interval '1 second' where departure_lease=$1",[departureFirst.lease_id]);
    const [reclaimed] = (await db.query("select * from claim_flight_departure_jobs()")).rows;
    assert.equal(reclaimed.stage,1);
    assert.equal(await admit(reclaimed.lease_id),false);

    await db.query("select finish_flight_departure_job($1,$2,now())",[reclaimed.lease_id,{status:"delayed",estimatedDeparture:timestamps.delay}]);
    assert.equal((await db.query("select * from claim_flight_departure_jobs()")).rows.length,0);
    const [notice] = (await db.query("select * from claim_flight_push()")).rows;
    assert.equal(notice.title,'航班管家');
    assert.match(notice.body,/QA Passenger.*UA60.*延误/);
    assert.equal((await db.query("select * from claim_flight_push()")).rows.length,0);
    await db.query("select finish_flight_push($1,$2,$3,$4,200)",[notice.message_id,notice.device_id,notice.owner_id,notice.token]);
    await db.query("update flight_auto_jobs set departure_due=now()-interval '2 minutes' where departure_stage=1");
    await db.query("update trips set flight_selection_snapshot=flight_selection_snapshot #- '{selected,estimatedDeparture}' where flight_info='UA60'");
    const [departureFinish] = (await db.query("select * from claim_flight_departure_jobs()")).rows;
    assert.equal(departureFinish.stage,2);
    const times = (await db.query(`select
        to_char(now() at time zone 'America/Los_Angeles' - interval '2 minutes','YYYY-MM-DD HH24:MI:SS') as actual,
        to_char(now() at time zone 'America/Los_Angeles' + interval '65 minutes','YYYY-MM-DD HH24:MI:SS') as arrival`)).rows[0];
    await db.query("select finish_flight_departure_job($1,$2,now())",[departureFinish.lease_id,
      {status:"departed",actualDeparture:times.actual,estimatedArrival:times.arrival}]);
    const [takeoff] = (await db.query("select body from flight_messages where event='departed'")).rows;
    assert.match(takeoff.body,/晚 3 分钟/);
    assert.match(takeoff.body,/1 小时 7 分钟/);
    assert.equal((await db.query("select * from claim_flight_departure_jobs()")).rows.length,0);
  } finally { await db.close(); }
});
