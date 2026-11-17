-- Manual recovery only, after removing this QA owner from sandbox allowlists.
-- Review current QA entitlement and stop if anyone has changed its intended role.
-- Preserve all signed Sandbox ledger records; never reassign an Apple chain.
begin;
do $$
declare
 qa constant uuid := '86361373-d4ba-4fc6-8f38-420367b6484e';
 affected integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(qa::text, 5181));
 if not exists (select 1 from auth.users where id=qa and lower(email)='ystechnology02@yahoo.com') then
  raise exception 'QA_IDENTITY_MISMATCH';
 end if;
 if exists (select 1 from public.storekit_transactions where owner_id=qa and environment='Production') then
  raise exception 'DO_NOT_OVERWRITE_PRODUCTION_PURCHASE';
 end if;
 update public.account_entitlements set edition='cloud',status='active',
 expires_at='2026-11-26 05:11:10.214792+00'::timestamptz,max_devices=4,updated_at=now()
 where owner_id=qa and edition='cloud' and max_devices=4 and status in ('active','expired','grace');
 get diagnostics affected = row_count;
 if affected<>1 then raise exception 'QA_BASELINE_CHANGED'; end if;
end $$;
commit;
