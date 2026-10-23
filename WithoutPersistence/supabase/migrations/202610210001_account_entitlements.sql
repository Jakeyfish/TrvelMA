-- Server-owned product entitlements. Clients may read only their own active
-- entitlement; only trusted server-side tooling may grant or change editions.
create table if not exists public.account_entitlements (
    owner_id uuid primary key references auth.users (id) on delete cascade,
    edition text not null check (edition in ('local', 'cloud', 'sync')),
    status text not null default 'active'
        check (status in ('active', 'grace', 'expired', 'revoked')),
    expires_at timestamptz,
    max_devices integer not null default 1 check (max_devices between 1 and 100),
    updated_at timestamptz not null default now()
);

alter table public.account_entitlements enable row level security;

drop policy if exists account_entitlements_read_own on public.account_entitlements;
create policy account_entitlements_read_own on public.account_entitlements
    for select to authenticated using (owner_id = (select auth.uid()));

revoke all on public.account_entitlements from anon, authenticated;
grant select on public.account_entitlements to authenticated;
grant select, insert, update, delete on public.account_entitlements to service_role;

-- Single server-side provisioning contract for admin tooling and a future
-- verified StoreKit/webhook handler. Never expose this function to clients.
create or replace function public.set_account_entitlement(
    p_owner_id uuid,
    p_edition text,
    p_status text default 'active',
    p_expires_at timestamptz default null,
    p_max_devices integer default 1
)
returns public.account_entitlements
language plpgsql
security definer
set search_path = ''
as $$
declare
    saved_entitlement public.account_entitlements;
begin
    if p_edition not in ('local', 'cloud', 'sync') then
        raise exception 'Unsupported product edition';
    end if;
    if p_status not in ('active', 'grace', 'expired', 'revoked') then
        raise exception 'Unsupported entitlement status';
    end if;
    if p_max_devices < 1 or p_max_devices > 100 then
        raise exception 'Device limit must be between 1 and 100';
    end if;

    insert into public.account_entitlements (owner_id, edition, status, expires_at, max_devices, updated_at)
    values (p_owner_id, p_edition, p_status, p_expires_at, p_max_devices, statement_timestamp())
    on conflict (owner_id) do update
        set edition = excluded.edition,
            status = excluded.status,
            expires_at = excluded.expires_at,
            max_devices = excluded.max_devices,
            updated_at = excluded.updated_at
    returning * into saved_entitlement;

    return saved_entitlement;
end;
$$;

revoke all on function public.set_account_entitlement(uuid, text, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.set_account_entitlement(uuid, text, text, timestamptz, integer) to service_role;

comment on table public.account_entitlements is
    'Server-managed product edition and limits. Client roles can only read their own row.';
comment on column public.account_entitlements.edition is
    'local: device-only purchase; cloud: online-only; sync: cloud plus offline cache and cross-device sync.';
