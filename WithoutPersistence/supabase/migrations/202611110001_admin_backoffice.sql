begin;
create schema if not exists admin_private;
revoke all on schema admin_private from public, anon, authenticated;
create table admin_private.applications (
 id text primary key, name text not null, environment text not null,
 backend text not null check(backend in ('local','unconfigured')), enabled boolean not null default false
);
create unique index admin_single_local_backend on admin_private.applications(backend) where backend='local';
insert into admin_private.applications values('trvelma-production','云盛行程管家','production','local',true);
create table admin_private.principals (
 user_id uuid primary key references auth.users(id), enabled boolean not null default true
);
create table admin_private.bindings (
 user_id uuid references admin_private.principals(user_id), app_id text references admin_private.applications(id),
 permission text not null check(permission in ('read','write')), primary key(user_id,app_id)
);
create table admin_private.audit (
 id bigint generated always as identity primary key, occurred_at timestamptz not null default statement_timestamp(),
 actor uuid not null, app_id text not null, target uuid, action text not null, reason text,
 request_id uuid, request_body jsonb, before_value jsonb, after_value jsonb,
 unique(actor,app_id,request_id)
);
alter table admin_private.applications enable row level security;
alter table admin_private.principals enable row level security;
alter table admin_private.bindings enable row level security;
alter table admin_private.audit enable row level security;
create table admin_private.account_labels (
 app_id text references admin_private.applications(id),owner_id uuid references auth.users(id) on delete cascade,
 purpose text not null check(purpose in ('business','review','development','ordinary')),primary key(app_id,owner_id)
);
alter table admin_private.account_labels enable row level security;
-- Display-only labels, never administrator grants or access checks.
insert into admin_private.account_labels(app_id,owner_id,purpose)
select 'trvelma-production',id,case lower(email) when 'kingfun5102@gmail.com' then 'business' when 'tony5101.wu@gmail.com' then 'review' else 'development' end from auth.users where lower(email) in ('kingfun5102@gmail.com','tony5101.wu@gmail.com','ystechnology01@yahoo.com');
revoke all on all tables in schema admin_private from public,anon,authenticated;
revoke all on all sequences in schema admin_private from public,anon,authenticated;

create function admin_private.authorize(p_app text default null,p_write boolean default false,p_context boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); claims jsonb:=auth.jwt();
begin
 if v_actor is null or claims->>'aal' is distinct from 'aal2' then raise exception 'ADMIN_MFA_REQUIRED' using errcode='42501'; end if;
 if not exists(select 1 from auth.sessions s where s.id::text=claims->>'session_id' and s.user_id=v_actor and (s.not_after is null or s.not_after>statement_timestamp())) then raise exception 'ADMIN_SESSION_INVALID' using errcode='42501'; end if;
 if not exists(select 1 from admin_private.principals where user_id=v_actor and enabled) then raise exception 'ADMIN_FORBIDDEN' using errcode='42501'; end if;
 if p_write and not exists(select 1 from jsonb_array_elements(coalesce(claims->'amr','[]'::jsonb)) a where a->>'method'='totp' and (a->>'timestamp')::numeric>=extract(epoch from statement_timestamp())-600) then raise exception 'ADMIN_RECENT_MFA_REQUIRED' using errcode='42501'; end if;
 if p_app is null and not p_context then raise exception 'ADMIN_APP_FORBIDDEN' using errcode='42501'; end if;
 if p_app is not null and not exists(select 1 from admin_private.bindings b join admin_private.applications a on a.id=b.app_id where b.user_id=v_actor and a.id=p_app and a.enabled and a.backend='local' and (not p_write or b.permission='write')) then raise exception 'ADMIN_APP_FORBIDDEN' using errcode='42501'; end if;
 return v_actor;
end $$;

create function public.admin_context() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(null,false,true); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'environment',a.environment,'permission',b.permission) order by a.id),'[]'::jsonb) into result from admin_private.applications a join admin_private.bindings b on b.app_id=a.id where b.user_id=v_actor and a.enabled and a.backend='local';
 return jsonb_build_object('applications',result,'actor',v_actor);
end $$;

create function public.admin_users(p_app text,p_search text default '',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(p_app); result jsonb; total bigint;
begin
 if p_offset<0 or p_offset>100000 or length(p_search)>150 then raise exception 'INVALID_FILTER'; end if;
 select count(*) into total from auth.users u where u.email is not null and position(lower(p_search) in lower(u.email))>0;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
 select u.id,u.email,u.created_at,coalesce(l.purpose,'ordinary') as purpose,e.edition,e.status,e.expires_at,e.max_devices,e.updated_at,
 case when e.status='revoked' then 'revoked' when e.owner_id is null then 'unlicensed' when e.expires_at<=statement_timestamp() or e.status='expired' then 'expired' else e.status end as effective_status,
 (select count(*) from public.account_devices d where d.owner_id=u.id and d.revoked_at is null) as active_devices,
 exists(select 1 from public.account_trial_grants g where g.owner_id=u.id) as has_trial_history
 from auth.users u left join public.account_entitlements e on e.owner_id=u.id left join admin_private.account_labels l on l.owner_id=u.id and l.app_id=p_app
 where u.email is not null and position(lower(p_search) in lower(u.email))>0 order by u.created_at desc,u.id limit 25 offset p_offset
 ) t;
 return jsonb_build_object('total',total,'users',result);
end $$;

create function public.admin_user_detail(p_app text,p_owner uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(p_app); devices jsonb; transactions jsonb; entitlement jsonb;
begin
 if not exists(select 1 from auth.users where id=p_owner) then raise exception 'ACCOUNT_NOT_FOUND'; end if;
 select to_jsonb(e) into entitlement from public.account_entitlements e where owner_id=p_owner;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into devices from (select device_id,device_type,registered_at,last_seen_at,revoked_at from public.account_devices where owner_id=p_owner order by last_seen_at desc limit 100) t;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into transactions from (select environment,product_id,purchased_at,expires_at,revoked_at,grace_expires_at from public.storekit_transactions where owner_id=p_owner order by purchased_at desc limit 50) t;
 insert into admin_private.audit(actor,app_id,target,action) values(v_actor,p_app,p_owner,'view_account');
 return jsonb_build_object('entitlement',entitlement,'devices',devices,'transactions',transactions);
end $$;

create function public.admin_release_device(p_app text,p_owner uuid,p_device uuid,p_last_seen timestamptz,p_request uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(p_app,true); old public.account_devices; saved public.account_devices; prior admin_private.audit; body jsonb;
begin
 if p_request is null or p_reason is null or length(trim(p_reason))<4 or length(p_reason)>500 then raise exception 'REASON_AND_REQUEST_REQUIRED'; end if;
 body:=jsonb_build_object('owner',p_owner,'device',p_device,'last_seen',p_last_seen,'reason',p_reason);
 perform pg_advisory_xact_lock(hashtextextended(v_actor::text||p_request::text,731));
 select a.* into prior from admin_private.audit a where a.actor=v_actor and a.app_id=p_app and a.request_id=p_request;
 if found then if prior.request_body<>body then raise exception 'REQUEST_CONFLICT'; end if; return prior.after_value; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
 select * into old from public.account_devices where owner_id=p_owner and device_id=p_device for update;
 if not found or old.revoked_at is not null or old.last_seen_at is distinct from p_last_seen then raise exception 'DEVICE_CHANGED_REFRESH'; end if;
 update public.account_devices set revoked_at=statement_timestamp() where owner_id=p_owner and device_id=p_device returning * into saved;
 insert into admin_private.audit(actor,app_id,target,action,reason,request_id,request_body,before_value,after_value) values(v_actor,p_app,p_owner,'release_device',p_reason,p_request,body,to_jsonb(old),to_jsonb(saved));
 return to_jsonb(saved);
end $$;

create function public.admin_audit(p_app text,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(p_app); result jsonb;
begin
 if p_offset<0 or p_offset>100000 then raise exception 'INVALID_FILTER'; end if;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (select id,occurred_at,actor,target,action,reason,before_value,after_value from admin_private.audit where app_id=p_app order by id desc limit 25 offset p_offset) t;
 return result;
end $$;
create function public.admin_set_entitlement(p_app text,p_owner uuid,p_expected timestamptz,p_edition text,p_status text,p_expiry timestamptz,p_devices integer,p_request uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=admin_private.authorize(p_app,true); old public.account_entitlements; saved public.account_entitlements; prior admin_private.audit; body jsonb; occupied integer;
begin
 if p_request is null or p_reason is null or length(trim(p_reason))<4 or length(p_reason)>500 then raise exception 'REASON_AND_REQUEST_REQUIRED'; end if;
 if p_edition is null or p_edition not in ('local','cloud','sync') or p_status is null or p_status not in ('active','grace','expired','revoked') or p_devices is null or p_devices not between 1 and 100 then raise exception 'INVALID_ENTITLEMENT'; end if;
 if p_status in ('active','grace') and p_expiry is not null and p_expiry<=statement_timestamp() then raise exception 'ACTIVE_EXPIRY_IN_PAST'; end if;
 body:=jsonb_build_object('owner',p_owner,'expected',p_expected,'edition',p_edition,'status',p_status,'expiry',p_expiry,'devices',p_devices,'reason',p_reason);
 perform pg_advisory_xact_lock(hashtextextended(v_actor::text||p_request::text,731));
 select a.* into prior from admin_private.audit a where a.actor=v_actor and a.app_id=p_app and a.request_id=p_request;
 if found then if prior.request_body<>body then raise exception 'REQUEST_CONFLICT'; end if; return prior.after_value; end if;
 -- Match both registration and verified billing writers; always take locks in this order.
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,5181));
 perform 1 from auth.users where id=p_owner for key share;
 if not found then raise exception 'ACCOUNT_NOT_FOUND'; end if;
 select * into old from public.account_entitlements where owner_id=p_owner for update;
 if old.updated_at is distinct from p_expected then raise exception 'ENTITLEMENT_CHANGED_REFRESH'; end if;
 select count(*) into occupied from public.account_devices where owner_id=p_owner and revoked_at is null;
 if p_devices<occupied then raise exception 'DEVICE_ALLOWANCE_BELOW_OCCUPANCY'; end if;
 saved:=public.set_account_entitlement(p_owner,p_edition,p_status,p_expiry,p_devices);
 insert into admin_private.audit(actor,app_id,target,action,reason,request_id,request_body,before_value,after_value) values(v_actor,p_app,p_owner,'set_entitlement',p_reason,p_request,body,case when old.owner_id is null then null else to_jsonb(old) end,to_jsonb(saved));
 return to_jsonb(saved);
end $$;
revoke all on function public.admin_set_entitlement(text,uuid,timestamptz,text,text,timestamptz,integer,uuid,text) from public,anon;
grant execute on function public.admin_set_entitlement(text,uuid,timestamptz,text,text,timestamptz,integer,uuid,text) to authenticated;
revoke all on all functions in schema admin_private from public,anon,authenticated;
revoke all on function public.admin_context(),public.admin_users(text,text,integer),public.admin_user_detail(text,uuid),public.admin_release_device(text,uuid,uuid,timestamptz,uuid,text),public.admin_audit(text,integer) from public,anon;
grant execute on function public.admin_context(),public.admin_users(text,text,integer),public.admin_user_detail(text,uuid),public.admin_release_device(text,uuid,uuid,timestamptz,uuid,text),public.admin_audit(text,integer) to authenticated;
commit;
