create table public.flight_push_devices (
    owner_id uuid not null,
    device_id uuid not null,
    token text not null,
    environment text not null check (environment in ('development','production')),
    enabled_at timestamptz not null default now(),
    primary key(owner_id,device_id),
    unique(environment,token),
    foreign key(owner_id,device_id) references public.account_devices(owner_id,device_id) on delete cascade
);
create table public.flight_push_deliveries (
    message_id uuid not null references public.flight_messages(id) on delete cascade,
    owner_id uuid not null,
    device_id uuid not null,
    attempts smallint not null default 1,
    lease_until timestamptz not null,
    sent boolean not null default false,
    primary key(message_id,device_id),
    foreign key(owner_id,device_id) references public.flight_push_devices(owner_id,device_id) on delete cascade
);
alter table public.flight_push_devices enable row level security;
alter table public.flight_push_deliveries enable row level security;
revoke all on public.flight_push_devices,public.flight_push_deliveries from public,anon,authenticated;

create function public.set_flight_push_device(p_device uuid,p_token text default null,p_environment text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare caller uuid := auth.uid();
begin
    if caller is null then return false; end if;
    if p_token is null then
        delete from public.flight_push_devices where owner_id=caller and device_id=p_device;
        return true;
    end if;
    if length(p_token) not between 32 and 512 or p_token !~ '^[a-f0-9]+$' or p_environment is null or p_environment not in ('development','production')
       or not exists(select 1 from public.account_devices where owner_id=caller and device_id=p_device and revoked_at is null
                     and device_type in ('iPhone','iPad')) then return false; end if;
    perform pg_advisory_xact_lock(hashtextextended(p_token,52612));
    delete from public.flight_push_devices where environment=p_environment and token=p_token
      and (owner_id,device_id)<>(caller,p_device);
    insert into public.flight_push_devices(owner_id,device_id,token,environment)
    values(caller,p_device,p_token,p_environment)
    on conflict(owner_id,device_id) do update set token=excluded.token,environment=excluded.environment;
    return true;
end;
$$;
revoke all on function public.set_flight_push_device(uuid,text,text) from public,anon;
grant execute on function public.set_flight_push_device(uuid,text,text) to authenticated;

create function public.claim_flight_push(p_limit integer default 20)
returns table(message_id uuid,device_id uuid,owner_id uuid,token text,environment text,title text,body text)
language sql security definer set search_path='' as $$
    with jobs as (
      select m.id, p.owner_id,p.device_id
      from public.flight_messages m
      join public.flight_push_devices p on p.owner_id=m.owner_id and p.enabled_at<=m.created_at
      join public.account_devices d on d.owner_id=p.owner_id and d.device_id=p.device_id
      join public.account_entitlements e on e.owner_id=m.owner_id
      left join public.flight_push_deliveries q on q.message_id=m.id and q.device_id=p.device_id
      where m.created_at>now()-interval '30 minutes' and d.revoked_at is null
        and e.edition in ('sync','cloud') and e.status in ('active','grace') and (e.expires_at is null or e.expires_at>now())
        and (q.message_id is null or (not q.sent and q.attempts < 3 and q.lease_until<=now()))
      order by m.created_at
      limit greatest(0,least(30,p_limit))
    ), claimed as (
      insert into public.flight_push_deliveries as d(message_id,owner_id,device_id,lease_until)
      select j.id,j.owner_id,j.device_id,now()+interval '2 minutes' from jobs j
      on conflict on constraint flight_push_deliveries_pkey do update
      set attempts=d.attempts+1,lease_until=excluded.lease_until
      where not d.sent and d.attempts<3 and d.lease_until<=now()
      returning d.*
    )
    select c.message_id,c.device_id,c.owner_id,p.token,p.environment,m.title,m.body
    from claimed c join public.flight_push_devices p using(owner_id,device_id)
    join public.flight_messages m on m.id=c.message_id;
$$;

create function public.finish_flight_push(p_message uuid,p_device uuid,p_owner uuid,p_token text,p_status integer)
returns void language plpgsql security definer set search_path='' as $$
begin
    if p_status=410 then
        delete from public.flight_push_devices where owner_id=p_owner and device_id=p_device and token=p_token;
    elsif p_status=200 then
        update public.flight_push_deliveries set sent=true where message_id=p_message and device_id=p_device and owner_id=p_owner;
    end if;
end;
$$;
revoke all on function public.claim_flight_push(integer),public.finish_flight_push(uuid,uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.claim_flight_push(integer),public.finish_flight_push(uuid,uuid,uuid,text,integer) to service_role;
