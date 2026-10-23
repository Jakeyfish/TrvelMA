-- Register app installations against the account's server-managed allowance.
-- Counts survive sign-out so a user cannot cycle through unlimited devices.
create table if not exists public.account_devices (
    owner_id uuid not null references auth.users (id) on delete cascade,
    device_id uuid not null,
    device_type text not null default 'iPhone'
        check (device_type in ('iPhone', 'iPad')),
    registered_at timestamptz not null default statement_timestamp(),
    last_seen_at timestamptz not null default statement_timestamp(),
    revoked_at timestamptz,
    primary key (owner_id, device_id)
);

alter table public.account_devices enable row level security;
revoke all on public.account_devices from public, anon, authenticated;
grant select, insert, update, delete on public.account_devices to service_role;

create or replace function public.register_account_device(
    p_device_id uuid,
    p_device_type text default 'iPhone'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_max_devices integer;
    v_active_count integer;
    v_already_active boolean;
begin
    if v_owner_id is null or p_device_id is null then
        raise exception 'Authenticated account and device id are required' using errcode = '42501';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_owner_id::text, 0));

    select entitlement.max_devices
      into v_max_devices
      from public.account_entitlements as entitlement
     where entitlement.owner_id = v_owner_id
       and entitlement.edition in ('cloud', 'sync')
       and entitlement.status in ('active', 'grace')
       and (entitlement.expires_at is null or entitlement.expires_at > statement_timestamp())
     for update;

    if v_max_devices is null then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;

    select exists (
        select 1 from public.account_devices as registered
         where registered.owner_id = v_owner_id
           and registered.device_id = p_device_id
           and registered.revoked_at is null
    ) into v_already_active;

    select count(*)::integer
      into v_active_count
      from public.account_devices as registered
     where registered.owner_id = v_owner_id
       and registered.revoked_at is null;

    if not v_already_active and v_active_count >= v_max_devices then
        raise exception 'ACCOUNT_DEVICE_LIMIT_REACHED' using errcode = 'P0001';
    end if;

    insert into public.account_devices (owner_id, device_id, device_type, registered_at, last_seen_at, revoked_at)
    values (v_owner_id, p_device_id, case when p_device_type = 'iPad' then 'iPad' else 'iPhone' end,
            statement_timestamp(), statement_timestamp(), null)
    on conflict (owner_id, device_id) do update
        set device_type = excluded.device_type,
            last_seen_at = excluded.last_seen_at,
            revoked_at = null;

    return pg_catalog.jsonb_build_object(
        'active_devices', case when v_already_active then v_active_count else v_active_count + 1 end,
        'max_devices', v_max_devices
    );
end;
$$;

revoke all on function public.register_account_device(uuid, text) from public, anon;
grant execute on function public.register_account_device(uuid, text) to authenticated;

create or replace function public.release_account_device(p_device_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
begin
    if v_owner_id is null or p_device_id is null then
        raise exception 'Authenticated account and device id are required' using errcode = '42501';
    end if;

    update public.account_devices
       set revoked_at = statement_timestamp()
     where owner_id = v_owner_id
       and device_id = p_device_id
       and revoked_at is null;
end;
$$;

revoke all on function public.release_account_device(uuid) from public, anon;
grant execute on function public.release_account_device(uuid) to authenticated;

comment on table public.account_devices is
    'App installations registered against an account entitlement device allowance.';
