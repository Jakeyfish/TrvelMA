-- Development project only. Synthetic QA rows live only inside this transaction.
-- Uses an existing entitled account/device only for a rolled-back synthetic fixture.
-- Does not change entitlements, devices, customer records or existing business trips.
begin;
do $setup$
declare
  v_owner uuid;
  v_device uuid;
  v_trip uuid := gen_random_uuid();
begin
  select d.owner_id,d.device_id into v_owner,v_device from public.account_devices d
   join public.account_entitlements e on e.owner_id=d.owner_id
   where d.revoked_at is null and e.edition in ('cloud','sync') and e.status in ('active','grace')
     and (e.expires_at is null or e.expires_at>statement_timestamp()) limit 1;
  if v_device is null then raise exception 'No eligible active cloud device'; end if;
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.headers',jsonb_build_object('x-account-device-id',v_device)::text,true);
  perform set_config('qa.trip_id',v_trip::text,true);
  insert into public.trips(id,owner_id,service_type,order_source,appointment_date,appointment_time,flight_date,
    travel_agency_order_number,memo,location_start,location_end,flight_info,flight_arrival_terminal,
    flight_selection_snapshot,reminder_enabled,has_second_reminder,reminder_at,second_reminder_at)
  values(v_trip,v_owner,'接机','旅行社订单','2026-11-25T20:00:00Z','2026-11-26T03:00:00Z','2026-11-25T20:00:00Z',
    'QA-MIGRATION-ROLLBACK','QA temporary transaction','LAX','QA destination','JX2','B',
    '{"qa":"unchanged"}'::jsonb,true,true,'2026-11-25T03:00:00Z','2026-11-26T01:00:00Z');
  insert into public.trip_stops(id,owner_id,trip_id,position,address)
  values(gen_random_uuid(),v_owner,v_trip,0,'QA stop unchanged');
end;
$setup$;
set local role authenticated;
do $test$
declare
  v_trip uuid := current_setting('qa.trip_id')::uuid;
  v_before jsonb;
  v_after jsonb;
  v_expenses jsonb;
  v_stops jsonb;
  v_duplicate uuid := gen_random_uuid();
begin
  if not public.can_access_cloud_data() then raise exception 'QA fixture cloud access unavailable'; end if;
  select to_jsonb(t) into v_before from public.trips t where id=v_trip;
  if v_before is null then raise exception 'RLS did not expose own QA fixture'; end if;
  perform public.save_online_trip_finances(v_trip,90,5,jsonb_build_array(jsonb_build_object(
    'id',gen_random_uuid(),'title','QA parking','amount',2,'position',0,'is_addition',false)));
  select to_jsonb(t) into v_after from public.trips t where id=v_trip;
  if (v_before - array['price','tip','is_paid','updated_at']) is distinct from
     (v_after - array['price','tip','is_paid','updated_at']) then raise exception 'Settlement overwrote unrelated fields'; end if;
  if (v_after->>'price')::numeric<>90 or (v_after->>'tip')::numeric<>5 or (v_after->>'is_paid')::boolean then
    raise exception 'Settlement financial fields incorrect'; end if;
  if not exists(select 1 from public.trip_stops where trip_id=v_trip and address='QA stop unchanged') then
    raise exception 'Settlement changed stops'; end if;
  select jsonb_agg(to_jsonb(e) order by e.id) into v_expenses from public.trip_expenses e where trip_id=v_trip;
  begin
    perform public.save_online_trip_finances(v_trip,999,99,jsonb_build_array(
      jsonb_build_object('id',v_duplicate,'title','QA duplicate A','amount',1),
      jsonb_build_object('id',v_duplicate,'title','QA duplicate B','amount',1)));
    raise exception 'Expected duplicate expense rejection';
  exception when unique_violation then null;
  end;
  if (select to_jsonb(t) from public.trips t where id=v_trip) is distinct from v_after then
    raise exception 'Rejected settlement failed to roll back parent'; end if;
  if (select jsonb_agg(to_jsonb(e) order by e.id) from public.trip_expenses e where trip_id=v_trip) is distinct from v_expenses then
    raise exception 'Rejected settlement failed to restore expenses'; end if;
  begin
    perform public.save_online_trip_finances(gen_random_uuid(),90,5,'[]'::jsonb);
    raise exception 'Expected unavailable trip rejection';
  exception when insufficient_privilege then null;
  end;
  perform public.settle_online_trip(v_trip,90,5,coalesce(v_expenses,'[]'::jsonb));
  perform public.save_online_trip_finances(v_trip,95,6,coalesce(v_expenses,'[]'::jsonb));
  if not (select is_paid from public.trips where id=v_trip) then
    raise exception 'Save-only reverted an already-paid trip'; end if;
  select to_jsonb(t) into v_after from public.trips t where id=v_trip;
  select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into v_stops from public.trip_stops s where trip_id=v_trip;
  perform public.save_online_trip(v_after - 'travel_agency_order_number',v_stops,coalesce(v_expenses,'[]'::jsonb));
  if (select travel_agency_order_number from public.trips where id=v_trip) <> 'QA-MIGRATION-ROLLBACK' then
    raise exception 'Legacy save erased independent order number'; end if;
end;
$test$;
reset role;
rollback;
select 'passed' as result,
       'save-only unpaid remains unpaid; paid remains paid; narrow money write; RLS; child-error rollback; QA rows rolled back' as checks;
