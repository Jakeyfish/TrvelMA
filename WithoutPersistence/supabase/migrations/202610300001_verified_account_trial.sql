-- New verified accounts receive one 14-day cloud trial, up to four devices.
-- Existing entitlements are never overwritten. Client metadata is not trusted.
begin;
create table if not exists public.account_trial_grants (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    starts_at timestamptz not null,
    expires_at timestamptz not null,
    check (expires_at = starts_at + interval '14 days')
);
alter table public.account_trial_grants enable row level security;
revoke all on public.account_trial_grants from public, anon, authenticated;
grant select, insert, update, delete on public.account_trial_grants to service_role;

create or replace function public.grant_verified_account_trial()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    granted_owner uuid;
begin
    if new.email_confirmed_at is null or nullif(new.email, '') is null then return new; end if;
    if exists(select 1 from public.account_entitlements where owner_id = new.id) then return new; end if;
    insert into public.account_trial_grants(owner_id, starts_at, expires_at)
    values(new.id, new.email_confirmed_at, new.email_confirmed_at + interval '14 days')
    on conflict (owner_id) do nothing returning owner_id into granted_owner;
    if granted_owner is null then return new; end if;
    insert into public.account_entitlements(owner_id, edition, status, expires_at, max_devices)
    values(new.id, 'cloud', 'active', new.email_confirmed_at + interval '14 days', 4)
    on conflict (owner_id) do nothing;
    return new;
end;
$$;
revoke all on function public.grant_verified_account_trial() from public, anon, authenticated;
drop trigger if exists on_verified_account_trial on auth.users;
create trigger on_verified_account_trial after insert or update of email_confirmed_at on auth.users
for each row execute function public.grant_verified_account_trial();
commit;
