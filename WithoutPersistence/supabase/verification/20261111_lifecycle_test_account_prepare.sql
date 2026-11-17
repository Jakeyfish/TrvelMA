-- Prepared only; run after explicit approval for this one disposable QA account.
-- No schema migration, deletions, or changes to other users/trial registration.
begin;
do $$
declare
 qa constant uuid := '86361373-d4ba-4fc6-8f38-420367b6484e';
 affected integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(qa::text, 5181));
 if not exists (select 1 from auth.users where id=qa and lower(email)='ystechnology02@yahoo.com' and email_confirmed_at is not null) then
  raise exception 'QA_IDENTITY_MISMATCH';
 end if;
 if exists (select 1 from public.trips where owner_id=qa)
 or exists (select 1 from public.customers where owner_id=qa)
 or exists (select 1 from public.storekit_transactions where owner_id=qa)
 or exists (select 1 from public.storekit_account_state where owner_id=qa) then
  raise exception 'QA_ACCOUNT_NOT_EMPTY';
 end if;
 update public.account_entitlements
 set status='expired', expires_at=now()-interval '1 minute', updated_at=now()
 where owner_id=qa and edition='cloud' and status='active' and max_devices=4
 and expires_at='2026-11-26 05:11:10.214792+00'::timestamptz;
 get diagnostics affected = row_count;
 if affected<>1 then raise exception 'QA_BASELINE_CHANGED'; end if;
end $$;
commit;
