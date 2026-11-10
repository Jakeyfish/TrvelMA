-- Read-only release preflight. Does not read customer or trip contents.
select current_database() as database_name,
       current_setting('server_version') as postgres_version;

select 'agency_order_number' as requirement,
       exists(select 1 from information_schema.columns
              where table_schema='public' and table_name='trips'
                and column_name='travel_agency_order_number' and data_type='text') as ready;

select 'save_online_trip' as requirement,
       to_regprocedure('public.save_online_trip(jsonb,jsonb,jsonb)') is not null as ready
union all
select 'settle_online_trip',
       to_regprocedure('public.settle_online_trip(uuid,numeric,numeric,jsonb)') is not null;

select p.proname, p.prosecdef as security_definer, p.proconfig,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('save_online_trip','settle_online_trip');

select c.relname, c.relrowsecurity as row_level_security
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('trips','trip_expenses','trip_stops');
