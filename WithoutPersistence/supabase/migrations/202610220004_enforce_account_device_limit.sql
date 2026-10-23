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
