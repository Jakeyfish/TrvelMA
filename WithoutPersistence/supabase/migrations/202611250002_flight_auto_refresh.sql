alter table public.user_settings
    add column flight_international_lead smallint not null default 60 check (flight_international_lead between 0 and 360),
    add column flight_domestic_lead smallint not null default 40 check (flight_domestic_lead between 0 and 360),
    add column flight_followup_delay smallint not null default 3 check (flight_followup_delay between 0 and 360);

create function public.flight_auto_preferences(p_international smallint default null, p_domestic smallint default null,
                                               p_followup smallint default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    caller uuid := auth.uid();
    prefs public.user_settings%rowtype;
begin
    if caller is null or not exists (
        select 1 from public.account_entitlements where owner_id = caller
        and edition in ('cloud', 'sync') and status in ('active', 'grace')
        and (expires_at is null or expires_at > now())
    ) then raise exception 'Flight entitlement required' using errcode = '42501'; end if;
    if p_international is not null and p_domestic is not null and p_followup is not null then
        insert into public.user_settings (owner_id, flight_international_lead, flight_domestic_lead, flight_followup_delay)
        values (caller, p_international, p_domestic, p_followup)
        on conflict (owner_id) do update set
            flight_international_lead = excluded.flight_international_lead,
            flight_domestic_lead = excluded.flight_domestic_lead,
            flight_followup_delay = excluded.flight_followup_delay
        returning * into prefs;
    else
        select * into prefs from public.user_settings where owner_id = caller;
    end if;
    return jsonb_build_object('international', coalesce(prefs.flight_international_lead, 60),
                              'domestic', coalesce(prefs.flight_domestic_lead, 40),
                              'followup', coalesce(prefs.flight_followup_delay, 3));
end;
$$;
revoke all on function public.flight_auto_preferences(smallint,smallint,smallint) from public, anon;
grant execute on function public.flight_auto_preferences(smallint,smallint,smallint) to authenticated;

create function public.flight_auto_airport(label text) returns text language sql stable set search_path = '' as $$
    select coalesce(
        case when btrim(label) ~ '^[A-Za-z]{3}$' then upper(btrim(label)) end,
        substring(label from '\(([A-Z]{3})\)'),
        case btrim(label)
            when '洛杉矶' then 'LAX' when '洛杉磯' then 'LAX' when '洛杉矶国际机场' then 'LAX' when '洛杉磯國際機場' then 'LAX'
            when '台湾桃园国际机场' then 'TPE' when '臺灣桃園國際機場' then 'TPE' when '台北桃园' then 'TPE' when '台北桃園' then 'TPE'
            when '杭州萧山' then 'HGH' when '杭州萧山国际机场' then 'HGH' when '成都天府' then 'TFU' when '成都天府国际机场' then 'TFU'
        end,
        (select min(code) from public.flight_auto_airports where name = lower(btrim(label)) having count(*) = 1)
    );
$$;

create function public.flight_auto_timestamp(value text, zone text) returns timestamptz
language plpgsql stable set search_path = '' as $$
begin
    if value is null or value !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}' then return null; end if;
    if value ~ '(Z|[+-]\d{2}:?\d{2})$' then return value::timestamptz; end if;
    return value::timestamp at time zone zone;
exception when invalid_datetime_format or datetime_field_overflow or invalid_parameter_value then
    return null;
end;
$$;

create table public.flight_auto_jobs (
    owner_id uuid not null references auth.users(id) on delete cascade,
    flight_number text not null,
    departure_date date not null,
    departure text not null,
    arrival text not null,
    completed_stage smallint not null default 0 check (completed_stage between 0 and 2),
    estimated_at timestamptz,
    actual_at timestamptz,
    state text,
    checked_at timestamptz,
    lease_id uuid,
    lease_until timestamptz,
    primary key (owner_id, flight_number, departure_date, departure, arrival)
);
create unique index flight_auto_jobs_lease on public.flight_auto_jobs(lease_id) where lease_id is not null;
alter table public.flight_auto_jobs enable row level security;
revoke all on public.flight_auto_jobs from public, anon, authenticated;

create index flight_auto_pending_pickups on public.trips(appointment_date)
    where not is_completed and not is_cancelled and deleted_at is null and service_type = '接机';

create view public.flight_auto_candidates as
select t.id, t.owner_id, t.flight_selection_snapshot as snapshot, snap.fnum as flight_number,
       coalesce(public.flight_auto_timestamp(snap.selected->>'scheduledDeparture', dep.zone) at time zone dep.zone,
                public.flight_auto_timestamp(snap.selected->>'departureTime', dep.zone) at time zone dep.zone,
                public.flight_auto_timestamp(snap.flight_date || ' 12:00', dep.zone) at time zone dep.zone)::date as departure_date,
       dep.code as departure, arr.code as arrival, arr.zone as arrival_zone,
       timing.planned_at, timing.estimated_at,
       case when dep.country = arr.country then coalesce(p.flight_domestic_lead,40)
            else coalesce(p.flight_international_lead,60) end as lead_minutes,
       coalesce(p.flight_followup_delay,3) as followup_minutes
from public.trips t
join public.account_entitlements e on e.owner_id = t.owner_id
left join public.user_settings p on p.owner_id = t.owner_id
cross join lateral (
    select t.flight_selection_snapshot->'selected' as selected,
           t.flight_selection_snapshot->>'flightNumber' as fnum,
           t.flight_selection_snapshot->>'flightDate' as flight_date
) snap
join public.flight_auto_airports dep on dep.code = public.flight_auto_airport(coalesce(snap.selected->>'departureAirportCode',snap.selected->>'departureAirport'))
join public.flight_auto_airports arr on arr.code = public.flight_auto_airport(coalesce(snap.selected->>'arrivalAirportCode',snap.selected->>'arrivalAirport'))
cross join lateral (
    select public.flight_auto_timestamp(snap.selected->>'scheduledArrival', arr.zone) as planned_at,
           public.flight_auto_timestamp(snap.selected->>'estimatedArrival', arr.zone) as estimated_at
) timing
where not t.is_completed and not t.is_cancelled and t.deleted_at is null and t.service_type = '接机'
  and t.appointment_date between now() - interval '2 days' and now() + interval '2 days'
  and dep.code <> arr.code and e.edition in ('cloud','sync') and e.status in ('active','grace')
  and (e.expires_at is null or e.expires_at > now())
  and t.flight_selection_snapshot->>'formatVersion' = '2'
  and snap.fnum = upper(btrim(t.flight_info)) and snap.fnum ~ '^[A-Z0-9]{2,10}$'
  and snap.flight_date ~ '^\d{4}-\d{2}-\d{2}$'
  and timing.planned_at is not null;
revoke all on public.flight_auto_candidates from public, anon, authenticated;

create function public.claim_flight_auto_jobs(p_limit integer default 8)
returns table(owner_id uuid, flight_number text, departure_date date, departure text, arrival text, lease_id uuid, stage integer)
language sql security definer set search_path = '' as $$
    with ready as (
        select c.owner_id, c.flight_number, c.departure_date, c.departure, c.arrival,
               case when max(j.completed_stage) = 1 then
                   coalesce((array_agg(c.estimated_at order by
                       case when jsonb_typeof(c.snapshot->'fetchedAt') = 'number' then (c.snapshot->>'fetchedAt')::numeric end desc nulls last)
                       filter (where c.estimated_at is not null))[1], max(j.estimated_at), min(c.planned_at))
                   + make_interval(mins => min(c.followup_minutes))
               else min(c.planned_at - make_interval(mins => c.lead_minutes)) end as due
        from public.flight_auto_candidates c
        left join public.flight_auto_jobs j using (owner_id, flight_number, departure_date, departure, arrival)
        where c.departure_date is not null and coalesce(j.completed_stage,0) < 2
          and (j.lease_until is null or j.lease_until <= now())
          and c.planned_at > now() - interval '1 day'
          and not (nullif(c.snapshot->'selected'->>'actualArrival','') is not null and j.completed_stage is null)
        group by c.owner_id,c.flight_number,c.departure_date,c.departure,c.arrival
    ), claimed as (
        insert into public.flight_auto_jobs as jobs (owner_id,flight_number,departure_date,departure,arrival,lease_id,lease_until)
        select r.owner_id,r.flight_number,r.departure_date,r.departure,r.arrival,gen_random_uuid(),now()+interval '5 minutes'
        from ready r where r.due <= now() order by r.due limit greatest(0,least(p_limit,20))
        on conflict on constraint flight_auto_jobs_pkey do update
            set lease_id=excluded.lease_id, lease_until=excluded.lease_until
            where jobs.completed_stage < 2 and (jobs.lease_until is null or jobs.lease_until <= now())
        returning jobs.*
    )
    select c.owner_id,c.flight_number,c.departure_date,c.departure,c.arrival,c.lease_id,c.completed_stage+1
    from claimed c;
$$;

create function public.finish_flight_auto_job(p_lease uuid, p_selected jsonb, p_state text, p_checked_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
    job public.flight_auto_jobs%rowtype;
begin
    select * into job from public.flight_auto_jobs where lease_id = p_lease for update;
    if not found or p_state is null or p_checked_at is null or p_state not in ('tracking','landed','cancelled','unconfirmed') then return; end if;
    update public.trips t
    set flight_selection_snapshot = c.snapshot || jsonb_build_object(
        'selected', (c.snapshot->'selected') || jsonb_strip_nulls(coalesce(p_selected,'{}'::jsonb))
                    || jsonb_build_object('automaticRefreshState', case when job.completed_stage = 1 and p_state = 'tracking' then 'unconfirmed' else p_state end),
        'automaticCheckedAt', extract(epoch from p_checked_at) - 978307200,
        'fetchedAt', coalesce(case when p_selected is not null then to_jsonb(extract(epoch from p_checked_at) - 978307200) end, c.snapshot->'fetchedAt')),
        updated_at = now()
    from public.flight_auto_candidates c
    where t.id = c.id and t.owner_id = job.owner_id and c.owner_id = job.owner_id
      and not t.is_completed and not t.is_cancelled and t.deleted_at is null
      and t.flight_selection_snapshot = c.snapshot
      and c.flight_number = job.flight_number and c.departure_date = job.departure_date
      and c.departure = job.departure and c.arrival = job.arrival
      and case when jsonb_typeof(c.snapshot->'fetchedAt') = 'number'
          then (c.snapshot->>'fetchedAt')::numeric <= extract(epoch from p_checked_at) - 978307200 else true end;
    update public.flight_auto_jobs
    set completed_stage = case when p_state in ('landed','cancelled','unconfirmed') then 2 else job.completed_stage+1 end,
        estimated_at = coalesce(public.flight_auto_timestamp(p_selected->>'estimatedArrival',
                          (select zone from public.flight_auto_airports where code=job.arrival)), job.estimated_at),
        actual_at = case when p_state = 'landed' then public.flight_auto_timestamp(p_selected->>'actualArrival',
                        (select zone from public.flight_auto_airports where code=job.arrival)) end,
        state = case when job.completed_stage = 1 and p_state = 'tracking' then 'unconfirmed' else p_state end,
        checked_at = p_checked_at, lease_id = null, lease_until = null
    where lease_id = p_lease;
end;
$$;

revoke all on function public.claim_flight_auto_jobs(integer), public.finish_flight_auto_job(uuid,jsonb,text,timestamptz) from public, anon, authenticated;
grant execute on function public.claim_flight_auto_jobs(integer), public.finish_flight_auto_job(uuid,jsonb,text,timestamptz) to service_role;
revoke all on function public.flight_auto_airport(text), public.flight_auto_timestamp(text,text) from public, anon, authenticated;

-- Reuse the same counters and caps for manual and scheduled lookups.
create function public.consume_variflight_quota_for(p_owner uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
    current_window timestamptz := date_trunc('hour', statement_timestamp());
    account_used integer;
    project_used integer;
begin
    if p_owner is null or not exists (
        select 1 from public.account_entitlements
        where owner_id = p_owner and edition in ('cloud','sync') and status in ('active','grace')
          and (expires_at is null or expires_at > now())
    ) then return false; end if;

    insert into public.variflight_usage_windows(owner_id,window_start,request_count)
    values(p_owner,current_window,1)
    on conflict(owner_id,window_start) do update set request_count=public.variflight_usage_windows.request_count+1
    returning request_count into account_used;
    if account_used > 30 then return false; end if;

    insert into public.variflight_global_usage_windows(window_start,request_count)
    values(current_window,1)
    on conflict(window_start) do update set request_count=public.variflight_global_usage_windows.request_count+1
    returning request_count into project_used;

    delete from public.variflight_usage_windows where owner_id=p_owner and window_start < current_window-interval '24 hours';
    delete from public.variflight_global_usage_windows where window_start < current_window-interval '24 hours';
    return project_used <= 300;
end;
$$;
revoke all on function public.consume_variflight_quota_for(uuid) from public, anon, authenticated;
grant execute on function public.consume_variflight_quota_for(uuid) to service_role;
create or replace function public.consume_variflight_quota()
returns boolean language sql security definer set search_path = '' as $$
    select public.consume_variflight_quota_for(auth.uid());
$$;
