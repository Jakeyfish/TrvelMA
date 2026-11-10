-- Run after migration, or embed its DDL within this transaction. QA only; rollback.
begin;
do $$
declare
    qa_id uuid := gen_random_uuid();
    protected_id uuid := gen_random_uuid();
    confirmed timestamptz := statement_timestamp();
    trial_expiry timestamptz;
    quota integer;
    trial_edition text;
begin
    insert into auth.users(id, email, created_at, updated_at)
    values(qa_id, qa_id::text || '@qa.invalid', confirmed, confirmed);
    if exists(select 1 from public.account_entitlements where owner_id=qa_id) then
        raise exception 'Unverified account was granted a trial';
    end if;
    update auth.users set email_confirmed_at=confirmed where id=qa_id;
    select expires_at, max_devices, account_entitlements.edition into trial_expiry, quota, trial_edition
    from public.account_entitlements where owner_id=qa_id;
    if trial_expiry is distinct from confirmed + interval '14 days' or quota is distinct from 4 or trial_edition is distinct from 'cloud' then
        raise exception 'Trial grant mismatch';
    end if;
    update auth.users set email_confirmed_at=confirmed + interval '2 days' where id=qa_id;
    if (select expires_at from public.account_entitlements where owner_id=qa_id) is distinct from trial_expiry then
        raise exception 'Repeat verification extended trial';
    end if;
    insert into auth.users(id,email,created_at,updated_at)
    values(protected_id,protected_id::text || '@qa.invalid',confirmed,confirmed);
    insert into public.account_entitlements(owner_id,edition,status,max_devices)
    values(protected_id,'sync','active',6);
    update auth.users set email_confirmed_at=confirmed where id=protected_id;
    if not exists(select 1 from public.account_entitlements where owner_id=protected_id and edition='sync' and max_devices=6 and expires_at is null) then
        raise exception 'Existing entitlement was changed';
    end if;
end;
$$;
select 'passed' as result, 'unverified blocked; verified 14 days/4 devices; no renewal; existing grants preserved; QA rolled back' as checks;
rollback;
