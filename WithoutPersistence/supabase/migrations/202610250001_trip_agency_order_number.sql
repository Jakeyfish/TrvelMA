-- Additive nullable column: old clients can still insert records without it.
-- Apply before deploying the client that sends travel_agency_order_number.
begin;
alter table public.trips
    add column if not exists travel_agency_order_number text default '';
comment on column public.trips.travel_agency_order_number is
    'Agency-issued order number, separate from the agency identifier/code.';

create or replace function public.save_online_trip(
    p_trip jsonb,
    p_stops jsonb default '[]'::jsonb,
    p_expenses jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_trip public.trips%rowtype;
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;
    if pg_catalog.jsonb_typeof(p_trip) <> 'object'
       or pg_catalog.jsonb_typeof(coalesce(p_stops, '[]'::jsonb)) <> 'array'
       or pg_catalog.jsonb_typeof(coalesce(p_expenses, '[]'::jsonb)) <> 'array' then
        raise exception 'Invalid trip payload' using errcode = '22023';
    end if;

    v_trip := pg_catalog.jsonb_populate_record(null::public.trips, p_trip);
    if v_trip.id is null or v_trip.appointment_date is null or v_trip.appointment_time is null
       or v_trip.flight_date is null then
        raise exception 'Trip identity and dates are required' using errcode = '22023';
    end if;
    if v_trip.customer_id is not null and not exists (
        select 1 from public.customers c
         where c.id = v_trip.customer_id and c.owner_id = v_owner_id and c.deleted_at is null
    ) then
        raise exception 'Customer is unavailable for this account' using errcode = '42501';
    end if;

    -- Old clients omit the new field. Preserve an existing agency order number
    -- rather than erasing it during the legacy delete/insert save transaction.
    if coalesce(v_trip.order_source, '') <> '旅行社订单' then
        v_trip.travel_agency_order_number := '';
    elsif p_trip ? 'travel_agency_order_number' then
        v_trip.travel_agency_order_number := coalesce(v_trip.travel_agency_order_number, '');
    else
        v_trip.travel_agency_order_number := coalesce((
            select t.travel_agency_order_number from public.trips t
             where t.id = v_trip.id and t.owner_id = v_owner_id
             for update
        ), '');
    end if;

    v_trip.owner_id := v_owner_id;
    v_trip.created_at := coalesce(v_trip.created_at, statement_timestamp());
    v_trip.updated_at := statement_timestamp();
    v_trip.deleted_at := null;

    -- The delete and insert share this transaction. A duplicate id owned by a
    -- different account still causes the following insert to fail safely.
    delete from public.trips where id = v_trip.id and owner_id = v_owner_id;
    insert into public.trips select (v_trip).*;

    insert into public.trip_stops (id, owner_id, trip_id, position, address, created_at, updated_at)
    select stop.id, v_owner_id, v_trip.id, stop.position, stop.address,
           statement_timestamp(), statement_timestamp()
      from pg_catalog.jsonb_to_recordset(coalesce(p_stops, '[]'::jsonb)) as stop(
          id uuid, position integer, address text
      );

    insert into public.trip_expenses (id, owner_id, trip_id, is_addition, title, amount, position, created_at, updated_at)
    select expense.id, v_owner_id, v_trip.id, coalesce(expense.is_addition, false),
           coalesce(expense.title, ''), coalesce(expense.amount, 0), coalesce(expense.position, 0),
           statement_timestamp(), statement_timestamp()
      from pg_catalog.jsonb_to_recordset(coalesce(p_expenses, '[]'::jsonb)) as expense(
          id uuid, is_addition boolean, title text, amount numeric, position integer
      );
end;
$$;

revoke all on function public.save_online_trip(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.save_online_trip(jsonb, jsonb, jsonb) to authenticated;

commit;
