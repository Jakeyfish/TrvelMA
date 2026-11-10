-- Synthetic QA only. Always roll back; never consumes a real device slot.
begin;
do $$
declare
 q uuid := gen_random_uuid();
 first_device uuid := gen_random_uuid();
 extra_device uuid := gen_random_uuid();
 result jsonb;
begin
 insert into auth.users(id,email,email_confirmed_at,created_at,updated_at)
 values(q,q::text||'@qa.invalid',now(),now(),now());
 perform set_config('request.jwt.claim.sub',q::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',q,'role','authenticated')::text,true);
 perform public.register_account_device(first_device,'iPhone');
 for i in 1..3 loop
  perform public.register_account_device(gen_random_uuid(),'iPad');
 end loop;
 result := public.register_account_device(first_device,'iPhone');
 if (result->>'active_devices')::int <> 4 then raise exception 'Repeat device consumed quota'; end if;
 begin
  perform public.register_account_device(extra_device,'iPhone');
  raise exception 'Fifth device was admitted';
 exception when sqlstate 'P0001' then
  if sqlerrm not like '%ACCOUNT_DEVICE_LIMIT_REACHED%' then raise; end if;
 end;
 perform public.release_account_device(first_device);
 perform public.register_account_device(extra_device,'iPhone');
 if (select count(*) from public.account_devices where owner_id=q and revoked_at is null) <> 4 then raise exception 'Slot reuse mismatch'; end if;
 update public.account_entitlements set expires_at=now()-interval '1 minute' where owner_id=q;
 begin
  perform public.register_account_device(extra_device,'iPhone');
  raise exception 'Expired account was admitted';
 exception when insufficient_privilege then null;
 end;
end $$;
rollback;
select 'passed' as result, 'four devices; repeat stable; fifth blocked; released slot reusable; expired account blocked; all QA rolled back' as checks;
