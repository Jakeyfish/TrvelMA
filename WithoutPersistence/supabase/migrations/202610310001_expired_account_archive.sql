-- Expired owners can read/export their archive without re-enabling normal writes.
begin;
create or replace function public.read_expired_account_archive()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 owner uuid := (select auth.uid());
 ent public.account_entitlements%rowtype;
 result jsonb := '{}'::jsonb;
 rows jsonb;
 table_name text;
begin
 if owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into ent from public.account_entitlements where owner_id=owner;
 if not found or ent.edition not in ('cloud','sync') or ent.status not in ('active','grace','expired')
   or ent.expires_at is null or ent.expires_at > statement_timestamp() then
  raise exception 'Expired account archive unavailable' using errcode='42501';
 end if;
 -- A past registered device is required; a revoked device cannot read the archive.
 if not exists(select 1 from public.account_devices d where d.owner_id=owner
   and d.revoked_at is null and d.device_id::text = lower(coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-account-device-id')) then
  raise exception 'Registered device required' using errcode='42501';
 end if;
 foreach table_name in array array['customers','customer_contacts','customer_addresses','trips','trip_stops','trip_expenses','travel_agencies','user_settings'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t where owner_id=$1',table_name) into rows using owner;
  result := result || jsonb_build_object(table_name,rows);
 end loop;
 return result || jsonb_build_object('schema_version',1,'read_only',true,'exported_at',statement_timestamp(),'expires_at',ent.expires_at);
end $$;
revoke all on function public.read_expired_account_archive() from public,anon;
grant execute on function public.read_expired_account_archive() to authenticated;
commit;
