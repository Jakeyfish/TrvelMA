-- 02-only pilot. Deploy before the Edge Function and clients.
begin;

alter table public.account_devices
    add column archive_only boolean not null default false;

create table public.expired_device_pairings (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    source_device uuid not null,
    replaced_device uuid not null,
    code_digest bytea not null,
    expires_at timestamptz not null,
    consumed_at timestamptz
);
alter table public.expired_device_pairings enable row level security;
revoke all on public.expired_device_pairings from public, anon, authenticated;

create table public.expired_device_verification_limits (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    window_started_at timestamptz not null,
    attempts integer not null
);
alter table public.expired_device_verification_limits enable row level security;
revoke all on public.expired_device_verification_limits from public, anon, authenticated;

create function public.reserve_expired_device_verification(p_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if p_owner is distinct from '86361373-d4ba-4fc6-8f38-420367b6484e'::uuid then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    insert into public.expired_device_verification_limits values (p_owner, statement_timestamp(), 1)
    on conflict (owner_id) do update set
        attempts = case when expired_device_verification_limits.window_started_at <= statement_timestamp() - interval '15 minutes'
            then 1 else expired_device_verification_limits.attempts + 1 end,
        window_started_at = case when expired_device_verification_limits.window_started_at <= statement_timestamp() - interval '15 minutes'
            then statement_timestamp() else expired_device_verification_limits.window_started_at end
    where expired_device_verification_limits.attempts < 5
       or expired_device_verification_limits.window_started_at <= statement_timestamp() - interval '15 minutes';
    if not found then
        raise exception 'Too many verification attempts' using errcode = '42501';
    end if;
end;
$$;
revoke all on function public.reserve_expired_device_verification(uuid) from public, anon, authenticated;
grant execute on function public.reserve_expired_device_verification(uuid) to service_role;

-- Only the server may issue a pairing, after verifying the owner's password.
create function public.issue_expired_device_pairing(p_owner uuid, p_source uuid, p_old uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
    v_code uuid := gen_random_uuid();
begin
    if p_owner is distinct from '86361373-d4ba-4fc6-8f38-420367b6484e'::uuid or p_source is null or p_old is null or p_source = p_old then
        raise exception 'Invalid device selection' using errcode = '22023';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_owner::text, 0));
    perform 1 from public.account_entitlements
        where owner_id = p_owner and status in ('active', 'grace', 'expired')
          and edition in ('cloud', 'sync') and expires_at <= statement_timestamp()
        for update;
    if not found or (select count(*) from public.account_devices
        where owner_id = p_owner and device_id in (p_source, p_old) and revoked_at is null) <> 2 then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    if not exists (select 1 from public.account_devices where owner_id = p_owner
        and device_id = p_source and revoked_at is null and not archive_only) then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    insert into public.expired_device_pairings values
        (p_owner, p_source, p_old, sha256(uuid_send(v_code)), statement_timestamp() + interval '5 minutes', null)
    on conflict (owner_id) do update set source_device = excluded.source_device,
        replaced_device = excluded.replaced_device, code_digest = excluded.code_digest,
        expires_at = excluded.expires_at, consumed_at = null;
    return v_code;
end;
$$;
revoke all on function public.issue_expired_device_pairing(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.issue_expired_device_pairing(uuid, uuid, uuid) to service_role;

create table public.expired_device_recovery_audit (
    owner_id uuid not null references auth.users(id) on delete cascade,
    source_device uuid not null,
    replaced_device uuid not null,
    new_device uuid not null,
    replaced_at timestamptz not null default statement_timestamp(),
    primary key (owner_id, new_device)
);
alter table public.expired_device_recovery_audit enable row level security;
revoke all on public.expired_device_recovery_audit from public, anon, authenticated;

create function public.complete_expired_device_pairing(p_code uuid, p_device uuid, p_type text)
returns void language plpgsql security definer set search_path = '' as $$
declare
    v_owner uuid := auth.uid();
    v_pair public.expired_device_pairings%rowtype;
begin
    if v_owner is distinct from '86361373-d4ba-4fc6-8f38-420367b6484e'::uuid or p_device is null or p_code is null then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_owner::text, 0));
    perform 1 from public.account_entitlements
        where owner_id = v_owner and status in ('active', 'grace', 'expired')
          and edition in ('cloud', 'sync') and expires_at <= statement_timestamp()
        for update;
    if not found then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    select * into v_pair from public.expired_device_pairings
        where owner_id = v_owner and code_digest = sha256(uuid_send(p_code))
          and consumed_at is null and expires_at > statement_timestamp()
        for update;
    if not found then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    perform 1 from public.account_devices where owner_id = v_owner
        and device_id = v_pair.source_device and revoked_at is null and not archive_only for update;
    if not found then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    update public.account_devices set revoked_at = statement_timestamp()
        where owner_id = v_owner and device_id = v_pair.replaced_device and revoked_at is null;
    if not found then
        raise exception 'Device recovery unavailable' using errcode = '42501';
    end if;
    -- An existing or revoked target causes a unique-constraint failure and rolls back the replacement.
    insert into public.account_devices(owner_id, device_id, device_type, archive_only)
        values (v_owner, p_device, case when p_type = 'iPad' then 'iPad' else 'iPhone' end, true);
    insert into public.expired_device_recovery_audit (owner_id, source_device, replaced_device, new_device)
        values (v_owner, v_pair.source_device, v_pair.replaced_device, p_device);
    update public.expired_device_pairings set consumed_at = statement_timestamp() where owner_id = v_owner;
end;
$$;
revoke all on function public.complete_expired_device_pairing(uuid, uuid, text) from public, anon;
grant execute on function public.complete_expired_device_pairing(uuid, uuid, text) to authenticated;
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
            revoked_at = null,
            archive_only = false;

    return pg_catalog.jsonb_build_object(
        'active_devices', case when v_already_active then v_active_count else v_active_count + 1 end,
        'max_devices', v_max_devices
    );
end;
$$;

-- A registered device id must accompany all cloud data and private Storage
-- requests. This makes the entitlement limit effective at the RLS boundary.
create or replace function public.can_access_cloud_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
          from public.account_entitlements as entitlement
          join public.account_devices as registered
            on registered.owner_id = entitlement.owner_id
           and registered.revoked_at is null
           and not registered.archive_only
         where entitlement.owner_id = (select auth.uid())
           and entitlement.edition in ('cloud', 'sync')
           and entitlement.status in ('active', 'grace')
           and (entitlement.expires_at is null or entitlement.expires_at > statement_timestamp())
           and registered.device_id = nullif(
               (pg_catalog.current_setting('request.headers', true)::jsonb ->> 'x-account-device-id'),
               ''
           )::uuid
    );
$$;

revoke all on function public.can_access_cloud_data() from public, anon;
grant execute on function public.can_access_cloud_data() to authenticated;

comment on function public.can_access_cloud_data() is
    'Checks active entitlement and active device registration for the authenticated account.';

commit;
