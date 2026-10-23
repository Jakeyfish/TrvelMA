-- Add a project-wide hourly budget so a large number of accounts cannot
-- exhaust the single server-side VariFlight credential collectively.
create table if not exists public.variflight_global_usage_windows (
    window_start timestamptz primary key,
    request_count integer not null default 0 check (request_count >= 0)
);

alter table public.variflight_global_usage_windows enable row level security;
revoke all on public.variflight_global_usage_windows from public, anon, authenticated;
grant all on public.variflight_global_usage_windows to service_role;

create or replace function public.consume_variflight_quota()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    current_window timestamptz := date_trunc('hour', statement_timestamp());
    account_used integer;
    project_used integer;
begin
    if caller_id is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    insert into public.variflight_usage_windows (owner_id, window_start, request_count)
    values (caller_id, current_window, 1)
    on conflict (owner_id, window_start) do update
        set request_count = public.variflight_usage_windows.request_count + 1
    returning request_count into account_used;

    if account_used > 30 then return false; end if;

    insert into public.variflight_global_usage_windows (window_start, request_count)
    values (current_window, 1)
    on conflict (window_start) do update
        set request_count = public.variflight_global_usage_windows.request_count + 1
    returning request_count into project_used;

    delete from public.variflight_usage_windows
    where owner_id = caller_id and window_start < current_window - interval '24 hours';
    delete from public.variflight_global_usage_windows
    where window_start < current_window - interval '24 hours';

    return project_used <= 300;
end;
$$;

revoke all on function public.consume_variflight_quota() from public, anon;
grant execute on function public.consume_variflight_quota() to authenticated;

comment on function public.consume_variflight_quota() is
    'Atomically enforces 30 VariFlight requests per account and 300 requests across the project per hour.';
