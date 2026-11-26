create table public.flight_bean_entries (
    id bigint generated always as identity primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    event_key text not null unique,
    kind text not null check (kind in ('subscription','refresh','referral','subscription_refund','referral_refund')),
    amount integer not null check (amount <> 0),
    created_at timestamptz not null default now()
);
create index flight_bean_entries_owner on public.flight_bean_entries(owner_id, id desc);

create table public.flight_bean_holds (
    id uuid primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    expires_at timestamptz not null
);
create index flight_bean_holds_owner on public.flight_bean_holds(owner_id, expires_at);

create table public.flight_bean_invites (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    code text not null unique default upper(replace(gen_random_uuid()::text,'-',''))
);
create table public.flight_bean_referrals (
    invitee_id uuid primary key references auth.users(id) on delete cascade,
    inviter_id uuid not null references auth.users(id) on delete cascade,
    credited_transaction text unique,
    check (invitee_id <> inviter_id)
);
alter table public.flight_bean_entries enable row level security;
alter table public.flight_bean_holds enable row level security;
alter table public.flight_bean_invites enable row level security;
alter table public.flight_bean_referrals enable row level security;
revoke all on public.flight_bean_entries, public.flight_bean_holds, public.flight_bean_invites, public.flight_bean_referrals from public, anon, authenticated;

create function public.flight_bean_lock(p_owner uuid) returns void
language sql set search_path = '' as $$
    select pg_advisory_xact_lock(hashtextextended(p_owner::text, 52611));
$$;

create function public.flight_bean_wallet() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    caller uuid := auth.uid();
    invite text;
    entries jsonb;
    balance bigint;
    period_end timestamptz;
begin
    if caller is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    insert into public.flight_bean_invites(owner_id) values (caller) on conflict (owner_id) do nothing;
    select code into invite from public.flight_bean_invites where owner_id=caller;
    select coalesce(sum(amount),0) into balance from public.flight_bean_entries where owner_id=caller;
    select coalesce(jsonb_agg(to_jsonb(e) order by id desc), '[]'::jsonb) into entries from (
        select id,kind,amount,created_at from public.flight_bean_entries where owner_id=caller order by id desc limit 30
    ) e;
    select max(expires_at) into period_end from public.storekit_transactions
    where owner_id=caller and environment='Production' and revoked_at is null and not upgraded and expires_at > now();
    return jsonb_build_object('balance',greatest(balance,0),'invite_code',invite,'entries',entries,'period_end',period_end,
        'referral_bound',exists(select 1 from public.flight_bean_referrals where invitee_id=caller));
end;
$$;

create function public.bind_flight_bean_invite(p_code text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    caller uuid := auth.uid();
    inviter uuid;
begin
    if caller is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    perform public.flight_bean_lock(caller);
    select owner_id into inviter from public.flight_bean_invites where code=upper(btrim(p_code));
    if inviter is null or inviter=caller then return false; end if;
    if exists(select 1 from public.storekit_transactions where owner_id=caller and environment='Production') then return false; end if;
    insert into public.flight_bean_referrals(invitee_id,inviter_id) values(caller,inviter)
    on conflict(invitee_id) do nothing;
    return exists(select 1 from public.flight_bean_referrals where invitee_id=caller and inviter_id=inviter);
end;
$$;

create function public.earn_flight_beans() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
    is_monthly boolean := new.product_id = 'com.yunshengtech.travelmanager.cloud.monthly';
    inviter uuid;
    credited text;
    grant_key text := 'subscription:' || new.transaction_id;
    reward_key text := 'referral:' || new.transaction_id;
begin
    if new.environment <> 'Production' then return new; end if;
    perform public.flight_bean_lock(new.owner_id);
    if new.revoked_at is not null then
        insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
        select owner_id,event_key||':refund',kind||'_refund',-amount from public.flight_bean_entries
        where event_key in (grant_key,reward_key) on conflict(event_key) do nothing;
        return new;
    end if;
    if new.upgraded or new.expires_at <= now() then return new; end if;

    insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
    values(new.owner_id,grant_key,'subscription',case when is_monthly then 20 else 300 end)
    on conflict(event_key) do nothing;
    select inviter_id,credited_transaction into inviter,credited from public.flight_bean_referrals
    where invitee_id=new.owner_id for update;
    if inviter is not null and credited is null and not exists (
        select 1 from public.storekit_transactions
        where owner_id=new.owner_id and environment='Production' and transaction_id<>new.transaction_id
          and purchased_at <= new.purchased_at
    ) then
        insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
        values(inviter,reward_key,'referral',case when is_monthly then 5 else 30 end)
        on conflict(event_key) do nothing;
        update public.flight_bean_referrals set credited_transaction=new.transaction_id where invitee_id=new.owner_id;
    end if;
    return new;
end;
$$;
create trigger earn_flight_beans after insert or update of revoked_at on public.storekit_transactions
for each row execute function public.earn_flight_beans();

-- Credit an existing live paid period once when the ledger is introduced.
insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
select distinct on (owner_id) owner_id,'subscription:'||transaction_id,'subscription',
       case when product_id='com.yunshengtech.travelmanager.cloud.monthly' then 20 else 300 end
from public.storekit_transactions where environment='Production' and revoked_at is null and not upgraded and expires_at > now()
order by owner_id,purchased_at desc,transaction_id;

create function public.reserve_flight_bean(p_owner uuid, p_hold uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    available bigint;
begin
    perform public.flight_bean_lock(p_owner);
    delete from public.flight_bean_holds where owner_id=p_owner and expires_at <= now();
    select coalesce(sum(amount),0) - (select count(*) from public.flight_bean_holds where owner_id=p_owner)
      into available from public.flight_bean_entries where owner_id=p_owner;
    if available <= 0 then return false; end if;
    insert into public.flight_bean_holds(id,owner_id,expires_at) values(p_hold,p_owner,now()+interval '2 minutes');
    return true;
end;
$$;

create function public.finish_flight_bean(p_owner uuid,p_hold uuid,p_charge boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
    perform public.flight_bean_lock(p_owner);
    delete from public.flight_bean_holds where id=p_hold and owner_id=p_owner;
    if not found then
        return exists(select 1 from public.flight_bean_entries where owner_id=p_owner and event_key='refresh:'||p_hold::text);
    end if;
    if p_charge then
        insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
        values(p_owner,'refresh:'||p_hold::text,'refresh',-1) on conflict(event_key) do nothing;
    end if;
    return true;
end;
$$;
revoke all on function public.flight_bean_lock(uuid), public.earn_flight_beans() from public, anon, authenticated;
revoke all on function public.flight_bean_wallet(), public.bind_flight_bean_invite(text) from public, anon;
grant execute on function public.flight_bean_wallet(), public.bind_flight_bean_invite(text) to authenticated;
revoke all on function public.reserve_flight_bean(uuid,uuid), public.finish_flight_bean(uuid,uuid,boolean) from public, anon, authenticated;
grant execute on function public.reserve_flight_bean(uuid,uuid), public.finish_flight_bean(uuid,uuid,boolean) to service_role;
