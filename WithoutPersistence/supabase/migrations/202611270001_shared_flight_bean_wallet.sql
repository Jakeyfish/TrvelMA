begin;
create table admin_private.flight_bean_policy (
    singleton boolean primary key default true check (singleton),
    cost integer not null check (cost between 1 and 100),
    updated_at timestamptz not null default clock_timestamp()
);
alter table admin_private.flight_bean_policy enable row level security;
revoke all on admin_private.flight_bean_policy from public, anon, authenticated;
insert into admin_private.flight_bean_policy(cost) values (2);

-- Preserve the price of reservations that were made before this migration.
alter table public.flight_bean_holds
    add column amount integer not null default 1 check (amount > 0);
alter table public.flight_bean_holds alter column amount drop default;

create or replace function public.reserve_flight_bean(p_owner uuid, p_hold uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    available bigint;
    price integer;
begin
    perform public.flight_bean_lock(p_owner);
    if exists(select 1 from public.flight_bean_entries
              where event_key='refresh:'||p_owner::text||':'||p_hold::text) then return false; end if;
    delete from public.flight_bean_holds where owner_id=p_owner and expires_at <= now();
    select cost into strict price from admin_private.flight_bean_policy;
    select coalesce(sum(amount),0) - (select coalesce(sum(amount),0) from public.flight_bean_holds where owner_id=p_owner)
      into available from public.flight_bean_entries where owner_id=p_owner;
    if available < price then return false; end if;
    insert into public.flight_bean_holds(id,owner_id,expires_at,amount) values(p_hold,p_owner,now()+interval '2 minutes',price);
    return true;
end;
$$;

create or replace function public.finish_flight_bean(p_owner uuid,p_hold uuid,p_charge boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    reserved_amount integer;
begin
    perform public.flight_bean_lock(p_owner);
    delete from public.flight_bean_holds where id=p_hold and owner_id=p_owner and expires_at > now()
    returning amount into reserved_amount;
    if not found then
        return exists(select 1 from public.flight_bean_entries where owner_id=p_owner and event_key='refresh:'||p_owner::text||':'||p_hold::text);
    end if;
    if p_charge then
        insert into public.flight_bean_entries(owner_id,event_key,kind,amount)
        values(p_owner,'refresh:'||p_owner::text||':'||p_hold::text,'refresh',-reserved_amount) on conflict(event_key) do nothing;
    end if;
    return true;
end;
$$;
create function public.admin_flight_bean_policy(p_app text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
    perform admin_private.authorize(p_app);
    return (select jsonb_build_object('cost',cost,'updated_at',updated_at)
            from admin_private.flight_bean_policy);
end;
$$;

create function public.admin_set_flight_bean_policy(
    p_app text,p_cost integer,p_expected timestamptz,p_request uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
    actor_id uuid := admin_private.authorize(p_app,true);
    previous admin_private.flight_bean_policy;
    saved admin_private.flight_bean_policy;
    prior admin_private.audit;
    body jsonb;
    result jsonb;
begin
    if p_cost is null or p_cost not between 1 and 100 then
        raise exception 'INVALID_FLIGHT_BEAN_COST';
    end if;
    if p_request is null or p_reason is null or length(trim(p_reason)) not between 4 and 500 then
        raise exception 'REASON_AND_REQUEST_REQUIRED';
    end if;
    body := jsonb_build_object('action','set_flight_bean_policy','cost',p_cost,'expected',p_expected,'reason',trim(p_reason));
    perform pg_advisory_xact_lock(hashtextextended(actor_id::text||p_request::text,731));
    select * into prior from admin_private.audit where actor=actor_id and app_id=p_app and request_id=p_request;
    if found then
        if prior.request_body is distinct from body then raise exception 'REQUEST_CONFLICT'; end if;
        return prior.after_value;
    end if;

    select * into strict previous from admin_private.flight_bean_policy for update;
    if previous.updated_at is distinct from p_expected then raise exception 'FLIGHT_BEAN_POLICY_CHANGED_REFRESH'; end if;
    update admin_private.flight_bean_policy set cost=p_cost,updated_at=clock_timestamp()
        where singleton returning * into saved;
    result := jsonb_build_object('cost',saved.cost,'updated_at',saved.updated_at);
    insert into admin_private.audit(actor,app_id,action,reason,request_id,request_body,before_value,after_value)
    values(actor_id,p_app,'set_flight_bean_policy',trim(p_reason),p_request,body,
           jsonb_build_object('cost',previous.cost,'updated_at',previous.updated_at),result);
    return result;
end;
$$;

revoke all on function public.admin_flight_bean_policy(text),
    public.admin_set_flight_bean_policy(text,integer,timestamptz,uuid,text) from public, anon;
grant execute on function public.admin_flight_bean_policy(text),
    public.admin_set_flight_bean_policy(text,integer,timestamptz,uuid,text) to authenticated;
commit;
