-- Save financial fields atomically without changing server-side payment or execution state.
begin;
create or replace function public.save_online_trip_finances(
    p_trip_id uuid, p_fare numeric, p_tip numeric, p_expenses jsonb default '[]'::jsonb
)
returns void language plpgsql security invoker set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;
    if p_trip_id is null or p_fare is null or p_tip is null or p_fare < 0 or p_tip < 0
       or p_fare::text in ('NaN', 'Infinity', '-Infinity')
       or p_tip::text in ('NaN', 'Infinity', '-Infinity')
       or pg_catalog.jsonb_typeof(coalesce(p_expenses, '[]'::jsonb)) <> 'array' then
        raise exception 'Invalid settlement payload' using errcode = '22023';
    end if;
    if exists (
        select 1 from pg_catalog.jsonb_to_recordset(coalesce(p_expenses, '[]'::jsonb))
            as e(id uuid, title text, amount numeric)
        where e.id is null or coalesce(pg_catalog.btrim(e.title), '') = ''
           or e.amount is null or e.amount <= 0 or e.amount::text in ('NaN', 'Infinity', '-Infinity')
    ) then
        raise exception 'Invalid expense' using errcode = '22023';
    end if;
    perform 1 from public.trips t
      where t.id = p_trip_id and t.owner_id = v_owner_id and t.deleted_at is null for update;
    if not found then
        raise exception 'Trip is unavailable for this account' using errcode = '42501';
    end if;
    update public.trips set price = p_fare, tip = p_tip, updated_at = statement_timestamp()
      where id = p_trip_id and owner_id = v_owner_id;
    delete from public.trip_expenses where trip_id = p_trip_id and owner_id = v_owner_id;
    insert into public.trip_expenses(id, owner_id, trip_id, is_addition, title, amount, position, created_at, updated_at)
    select e.id, v_owner_id, p_trip_id, coalesce(e.is_addition, false), e.title, e.amount,
           coalesce(e.position, 0), statement_timestamp(), statement_timestamp()
      from pg_catalog.jsonb_to_recordset(coalesce(p_expenses, '[]'::jsonb))
        as e(id uuid, is_addition boolean, title text, amount numeric, position integer);
end;
$$;
revoke all on function public.save_online_trip_finances(uuid, numeric, numeric, jsonb) from public, anon;
grant execute on function public.save_online_trip_finances(uuid, numeric, numeric, jsonb) to authenticated;
commit;
