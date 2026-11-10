-- Append inside the migration transaction, replacing COMMIT. Synthetic QA only.
do $$
declare
 q uuid:=gen_random_uuid(); other_owner uuid:=gen_random_uuid(); device uuid:=gen_random_uuid(); archive jsonb;
begin
 insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values(q,q::text||'@qa.invalid',now(),now(),now()),(other_owner,other_owner::text||'@qa.invalid',now(),now(),now());
 insert into public.customers(id,owner_id,name) values(gen_random_uuid(),q,'QA Own Archive'),(gen_random_uuid(),other_owner,'QA Other Secret');
 perform set_config('request.jwt.claim.sub',q::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
 perform set_config('request.headers',jsonb_build_object('x-account-device-id',device)::text,true);
 perform public.register_account_device(device,'iPhone');
 begin
  perform public.read_expired_account_archive();
  raise exception 'Active account admitted to expired-only endpoint';
 exception when insufficient_privilege then null;
 end;
 update public.account_entitlements set expires_at=now()-interval '1 minute' where owner_id=q;
 archive:=public.read_expired_account_archive();
 if jsonb_array_length(archive->'customers')<>1 or archive->'customers'->0->>'name'<>'QA Own Archive' then raise exception 'Owner isolation failed'; end if;
 if public.can_access_cloud_data() then raise exception 'Normal write access unexpectedly restored'; end if;
 update public.account_devices set revoked_at=now() where owner_id=q;
 begin
  perform public.read_expired_account_archive();
  raise exception 'Revoked device admitted';
 exception when insufficient_privilege then null;
 end;
 update public.account_devices set revoked_at=null where owner_id=q;
 update public.account_entitlements set status='revoked' where owner_id=q;
 begin
  perform public.read_expired_account_archive();
  raise exception 'Revoked account admitted';
 exception when insufficient_privilege then null;
 end;
end $$;
rollback;
select 'passed' as result,'own archive only; active/revoked account denied; revoked device denied; normal access stays blocked; QA and DDL rolled back' as checks;
