-- Draft 1.1: service-only ledger. Do not deploy until sandbox acceptance completes.
create table public.storekit_account_state (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 environment text not null check(environment in ('Production','Sandbox')),
 baseline jsonb,
 last_written_at timestamptz,
 last_written_grant jsonb
);
create table public.storekit_subscription_owners (
 environment text not null check(environment in ('Production','Sandbox')),
 original_transaction_id text not null,
 owner_id uuid not null references auth.users(id) on delete cascade,
 primary key(environment, original_transaction_id)
);
create table public.storekit_transactions (
 environment text not null check(environment in ('Production','Sandbox')),
 transaction_id text not null,
 original_transaction_id text not null,
 owner_id uuid not null references auth.users(id) on delete cascade,
 product_id text not null check(product_id in ('com.yunshengtech.travelmanager.cloud.monthly','com.yunshengtech.travelmanager.cloud.yearly')),
 purchased_at timestamptz not null,
 expires_at timestamptz not null,
 signed_at timestamptz not null,
 revoked_at timestamptz,
 upgraded boolean not null,
 grace_expires_at timestamptz,
 primary key(environment, transaction_id),
 foreign key(environment,original_transaction_id) references public.storekit_subscription_owners(environment,original_transaction_id) on delete cascade,
 check(expires_at > purchased_at)
);
create index on public.storekit_transactions(owner_id,environment,expires_at);

alter table public.storekit_account_state enable row level security;
alter table public.storekit_subscription_owners enable row level security;
alter table public.storekit_transactions enable row level security;
revoke all on public.storekit_account_state, public.storekit_subscription_owners, public.storekit_transactions from public, anon, authenticated;
grant all on public.storekit_account_state, public.storekit_subscription_owners, public.storekit_transactions to service_role;

create or replace function public.apply_verified_storekit_event(p_event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 owner uuid := (p_event->>'owner_id')::uuid;
 env text := p_event->>'environment';
 current_grant public.account_entitlements;
 managed public.storekit_account_state;
 existing public.storekit_transactions;
 chain_owner uuid;
 winner record;
 baseline jsonb;
 chosen_edition text := 'cloud';
 chosen_status text := 'expired';
 chosen_expiry timestamptz := '1970-01-01 UTC';
 chosen_devices integer := 4;
 saved public.account_entitlements;
begin
 if env is null or env not in ('Production','Sandbox') then raise exception 'INVALID_ENVIRONMENT'; end if;
 perform pg_advisory_xact_lock(hashtextextended(owner::text, 5181));
 -- A verified delayed Apple event must never recreate a deleted account. Hold
 -- the user row against concurrent deletion until the ledger write completes.
 perform 1 from auth.users where id=owner for key share;
 if not found then
  return jsonb_build_object('recorded',false,'ignored','ACCOUNT_DELETED');
 end if;
 select * into current_grant from public.account_entitlements where owner_id=owner for update;
 select * into managed from public.storekit_account_state where owner_id=owner for update;
 if found and managed.environment <> env then raise exception 'ENVIRONMENT_CONFLICT'; end if;
 -- A manual revoke always wins; a signed payment must not silently reactivate it.
 if current_grant.status = 'revoked' then raise exception 'ACCOUNT_REVOKED'; end if;

 insert into public.storekit_subscription_owners(environment,original_transaction_id,owner_id)
 values(env,p_event->>'original_transaction_id',owner) on conflict do nothing;
 select owner_id into chain_owner from public.storekit_subscription_owners
 where environment=env and original_transaction_id=p_event->>'original_transaction_id';
 if chain_owner is distinct from owner then raise exception 'TRANSACTION_ACCOUNT_CONFLICT'; end if;
 select * into existing from public.storekit_transactions
 where environment=env and transaction_id=p_event->>'transaction_id';
 if found then
  if existing.owner_id <> owner or existing.original_transaction_id <> p_event->>'original_transaction_id'
     or existing.product_id <> p_event->>'product_id' then raise exception 'TRANSACTION_ID_CONFLICT'; end if;
  if existing.signed_at >= (p_event->>'signed_at')::timestamptz then
   return jsonb_build_object('recorded',true,'duplicate_or_stale',true);
  end if;
 end if;

 -- Keep the pre-billing grant as the fallback for refunds/expiry. Preserve later
 -- manual grants too; only changes written by this function are treated as billing.
 baseline := managed.baseline;
 if managed.owner_id is null or current_grant.updated_at is distinct from managed.last_written_at
    or to_jsonb(current_grant) is distinct from managed.last_written_grant then
  baseline := case when current_grant.owner_id is null then null else to_jsonb(current_grant) end;
 end if;
 insert into public.storekit_account_state(owner_id,environment,baseline)
 values(owner,env,baseline) on conflict(owner_id) do update set baseline=excluded.baseline;
 insert into public.storekit_transactions values(
  env,p_event->>'transaction_id',p_event->>'original_transaction_id',owner,p_event->>'product_id',
  (p_event->>'purchased_at')::timestamptz,(p_event->>'expires_at')::timestamptz,
  (p_event->>'signed_at')::timestamptz,(p_event->>'revoked_at')::timestamptz,
  (p_event->>'upgraded')::boolean,(p_event->>'grace_expires_at')::timestamptz
 ) on conflict(environment,transaction_id) do update set
  expires_at=excluded.expires_at, signed_at=excluded.signed_at, revoked_at=excluded.revoked_at,
  upgraded=excluded.upgraded, grace_expires_at=excluded.grace_expires_at;

 select greatest(expires_at,coalesce(grace_expires_at,expires_at)) as until_at,
  case when expires_at <= statement_timestamp() and grace_expires_at > statement_timestamp() then 'grace' else 'active' end as state
 into winner from public.storekit_transactions
 where owner_id=owner and environment=env and revoked_at is null and not upgraded
  and greatest(expires_at,coalesce(grace_expires_at,expires_at)) > statement_timestamp()
 order by until_at desc limit 1;
 if found then chosen_status:=winner.state; chosen_expiry:=winner.until_at; end if;
 if baseline is not null and baseline->>'status' in ('active','grace')
   and (baseline->>'expires_at' is null or (baseline->>'expires_at')::timestamptz > statement_timestamp()) then
  if (chosen_status = 'expired' or baseline->>'edition' in ('cloud','sync'))
     and (baseline->>'expires_at' is null or (baseline->>'expires_at')::timestamptz > chosen_expiry) then
   chosen_edition:=baseline->>'edition'; chosen_status:=baseline->>'status';
   chosen_expiry:=(baseline->>'expires_at')::timestamptz;
  end if;
  chosen_devices:=case when chosen_edition = 'local' then (baseline->>'max_devices')::integer
    else greatest(chosen_devices,(baseline->>'max_devices')::integer) end;
 end if;
 select * into saved from public.set_account_entitlement(owner,chosen_edition,chosen_status,chosen_expiry,chosen_devices);
 update public.storekit_account_state set last_written_at=saved.updated_at,
  last_written_grant=to_jsonb(saved) where owner_id=owner;
 return jsonb_build_object('recorded',true,'entitlement',to_jsonb(saved));
end $$;
revoke all on function public.apply_verified_storekit_event(jsonb) from public,anon,authenticated;
grant execute on function public.apply_verified_storekit_event(jsonb) to service_role;
