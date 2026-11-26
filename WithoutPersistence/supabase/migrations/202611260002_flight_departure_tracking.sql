alter table public.flight_auto_jobs
    add column arrival_attempted_stage smallint not null default 0,
    add column departure_attempted_stage smallint not null default 0,
    add column departure_stage smallint not null default 0 check (departure_stage between 0 and 2),
    add column departure_due timestamptz,
    add column departure_state text,
    add column departure_lease uuid,
    add column departure_lease_until timestamptz;
create unique index flight_departure_lease on public.flight_auto_jobs(departure_lease) where departure_lease is not null;

create table public.flight_messages (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    trip_id uuid not null references public.trips(id) on delete cascade,
    flight_key text not null,
    event text not null check (event in ('delayed','departed')),
    title text not null,
    body text not null,
    created_at timestamptz not null default now(),
    unique(trip_id,flight_key,event)
);
alter table public.flight_messages enable row level security;
revoke all on public.flight_messages from public, anon, authenticated;

create function public.flight_message_inbox() returns jsonb
language sql security definer set search_path = '' as $$
    select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb) from (
        select id,title,body,created_at from public.flight_messages
        where owner_id=auth.uid() order by created_at desc limit 30
    ) m;
$$;
revoke all on function public.flight_message_inbox() from public, anon;
grant execute on function public.flight_message_inbox() to authenticated;

create view public.flight_departure_candidates as
select c.*, t.customer_name, a.zone as departure_zone,
       public.flight_auto_timestamp(c.snapshot->'selected'->>'scheduledDeparture',a.zone) as planned_departure,
       public.flight_auto_timestamp(c.snapshot->'selected'->>'estimatedDeparture',a.zone) as estimated_departure
from public.flight_auto_candidates c
join public.trips t on t.id=c.id and t.owner_id=c.owner_id
join public.flight_auto_airports a on a.code=c.departure;
revoke all on public.flight_departure_candidates from public, anon, authenticated;

create function public.claim_flight_departure_jobs(p_limit integer default 8)
returns table(owner_id uuid,flight_number text,departure_date date,departure text,arrival text,lease_id uuid,stage integer)
language sql security definer set search_path = '' as $$
    with eligible as (
        select c.owner_id,c.flight_number,c.departure_date,c.departure,c.arrival,
               case when max(j.departure_stage)=1 then
                   coalesce(greatest(max(c.estimated_departure)+interval '2 minutes',max(j.departure_due)),max(j.departure_due))
               else min(c.planned_departure)+interval '2 minutes' end as due
        from public.flight_departure_candidates c
        left join public.flight_auto_jobs j using(owner_id,flight_number,departure_date,departure,arrival)
        where c.planned_departure is not null and c.departure_date is not null
          and c.planned_at > now()-interval '1 day'
          and coalesce(j.departure_stage,0)<2
          and (j.departure_lease_until is null or j.departure_lease_until<=now())
          and (j.departure_stage=1 or nullif(c.snapshot->'selected'->>'actualDeparture','') is null)
        group by c.owner_id,c.flight_number,c.departure_date,c.departure,c.arrival
    ), claimed as (
        insert into public.flight_auto_jobs as j(owner_id,flight_number,departure_date,departure,arrival,departure_lease,departure_lease_until)
        select e.owner_id,e.flight_number,e.departure_date,e.departure,e.arrival,gen_random_uuid(),now()+interval '5 minutes'
        from eligible e where e.due<=now() order by e.due limit greatest(0,least(p_limit,20))
        on conflict on constraint flight_auto_jobs_pkey do update
        set departure_lease=excluded.departure_lease, departure_lease_until=excluded.departure_lease_until
        where j.departure_stage<2 and (j.departure_lease_until is null or j.departure_lease_until<=now())
        returning j.*
    )
    select c.owner_id,c.flight_number,c.departure_date,c.departure,c.arrival,c.departure_lease,c.departure_stage+1
    from claimed c;
$$;

create function public.finish_flight_departure_job(p_lease uuid,p_selected jsonb,p_checked_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare
    job public.flight_auto_jobs%rowtype;
    trip public.flight_departure_candidates%rowtype;
    actual_at timestamptz;
    estimated_at timestamptz;
    planned_at timestamptz;
    arrival_at timestamptz;
    delayed boolean := coalesce(lower(p_selected->>'status') in ('delayed','delay','延误','延誤','已延误','已延誤'),false);
    cancelled boolean := coalesce(lower(p_selected->>'status') in ('cancelled','canceled','取消','已取消'),false);
    next_due timestamptz;
    current_state text := 'unconfirmed';
    event_body text;
    message_event text;
    delay_minutes integer;
    flight_minutes integer;
    next_number smallint;
    v_flight_key text;
begin
    select * into job from public.flight_auto_jobs where departure_lease=p_lease for update;
    if not found or p_checked_at is null then return; end if;
    next_number := job.departure_stage+1;
    v_flight_key := concat_ws(':',job.flight_number,job.departure_date,job.departure,job.arrival);
    for trip in
        select c.* from public.flight_departure_candidates c
        where c.owner_id=job.owner_id and c.flight_number=job.flight_number and c.departure_date=job.departure_date
        and c.departure=job.departure and c.arrival=job.arrival
    loop
        actual_at := public.flight_auto_timestamp(coalesce(p_selected->>'actualDeparture',trip.snapshot->'selected'->>'actualDeparture'),trip.departure_zone);
        estimated_at := public.flight_auto_timestamp(p_selected->>'estimatedDeparture',trip.departure_zone);
        arrival_at := coalesce(public.flight_auto_timestamp(p_selected->>'estimatedArrival',trip.arrival_zone),trip.estimated_at);
        planned_at := coalesce(public.flight_auto_timestamp(coalesce(p_selected->>'originalScheduledDeparture',
            trip.snapshot->'selected'->>'originalScheduledDeparture'),trip.departure_zone),trip.planned_departure);
        message_event := null;
        if actual_at is not null and not cancelled then
            current_state := 'departed';
            next_number := 2;
            message_event := 'departed';
            delay_minutes := greatest(0,floor(extract(epoch from actual_at-planned_at)/60)::int);
            flight_minutes := case when arrival_at>actual_at then floor(extract(epoch from arrival_at-actual_at)/60)::int end;
            event_body := format('%s乘坐的 %s 已从 %s 起飞。实际起飞时间 %s。',
                coalesce(nullif(btrim(trip.customer_name),''),'客人'),job.flight_number,job.departure,
                to_char(actual_at at time zone trip.departure_zone,'YYYY-MM-DD HH24:MI'));
            if delay_minutes>0 then event_body := event_body || format('较原计划晚 %s 分钟。',delay_minutes); end if;
            if flight_minutes is not null then
                event_body := event_body || format('预计空中飞行 %s 小时 %s 分钟。',flight_minutes/60,flight_minutes%60);
            end if;
        elsif cancelled then
            current_state := 'cancelled';
            next_number := 2;
        elsif delayed then
            current_state := case when next_number=1 then 'delayed' else 'unconfirmed' end;
            message_event := 'delayed';
            event_body := format('%s乘坐的 %s，%s 报告航班延误。预计起飞时间 %s。',
              coalesce(nullif(btrim(trip.customer_name),''),'客人'),job.flight_number,job.departure,
              coalesce(to_char(estimated_at at time zone trip.departure_zone,'YYYY-MM-DD HH24:MI'),'待定'));
        end if;
        if next_number=1 then
            next_due := case when delayed and estimated_at is not null
                 then greatest(p_checked_at+interval '1 minute',estimated_at+interval '2 minutes')
                 else p_checked_at+interval '1 hour' end;
            if not delayed then current_state := 'tracking'; end if;
        end if;
        if message_event is not null then
            insert into public.flight_messages(owner_id,trip_id,flight_key,event,title,body)
            values(job.owner_id,trip.id,v_flight_key,message_event,'航班管家',event_body)
            on conflict(trip_id,flight_key,event) do nothing;
        end if;
        update public.trips t set
            flight_selection_snapshot=trip.snapshot || jsonb_build_object('selected',trip.snapshot->'selected'
              || jsonb_strip_nulls(jsonb_build_object(
                  'originalScheduledDeparture',coalesce(p_selected->>'originalScheduledDeparture',
                    trip.snapshot->'selected'->>'originalScheduledDeparture',trip.snapshot->'selected'->>'scheduledDeparture'),
                  'actualDeparture',p_selected->>'actualDeparture',
                  'estimatedDeparture',p_selected->>'estimatedDeparture',
                  'status', case when current_state='departed' and p_selected->>'status' is null then 'departed' else p_selected->>'status' end,
                  'automaticDepartureState',current_state))),
            updated_at=now()
        where t.id=trip.id and t.owner_id=job.owner_id and t.flight_selection_snapshot=trip.snapshot
          and not t.is_completed and not t.is_cancelled and t.deleted_at is null;
    end loop;
    update public.flight_auto_jobs set departure_stage=next_number,departure_due=next_due,departure_state=current_state,
        departure_lease=null,departure_lease_until=null where departure_lease=p_lease;
end;
$$;

revoke all on function public.claim_flight_departure_jobs(integer), public.finish_flight_departure_job(uuid,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.claim_flight_departure_jobs(integer), public.finish_flight_departure_job(uuid,jsonb,timestamptz) to service_role;


-- Persist the attempt before contacting the paid provider. If the worker dies
-- after sending the request, a reclaimed lease closes the stage without paying again.
create function public.admit_flight_auto_attempt(p_lease uuid,p_departure boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
    if p_departure then
        update public.flight_auto_jobs set departure_attempted_stage=departure_stage+1
        where departure_lease=p_lease and departure_lease_until>now() and departure_stage<2
          and departure_attempted_stage<departure_stage+1;
    else
        update public.flight_auto_jobs set arrival_attempted_stage=completed_stage+1
        where lease_id=p_lease and lease_until>now() and completed_stage<2
          and arrival_attempted_stage<completed_stage+1;
    end if;
    return found;
end;
$$;
revoke all on function public.admit_flight_auto_attempt(uuid,boolean) from public,anon,authenticated;
grant execute on function public.admit_flight_auto_attempt(uuid,boolean) to service_role;
