-- Per-account hourly quota for the server-side VariFlight proxy.
-- The table is private; clients can only consume their own fixed quota.
create table if not exists public.variflight_usage_windows (
    owner_id uuid not null references auth.users (id) on delete cascade,
    window_start timestamptz not null,
    request_count integer not null default 0 check (request_count >= 0),
    primary key (owner_id, window_start)
);

alter table public.variflight_usage_windows enable row level security;
revoke all on public.variflight_usage_windows from public, anon, authenticated;
grant all on public.variflight_usage_windows to service_role;

create or replace function public.consume_variflight_quota()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    current_window timestamptz := date_trunc('hour', statement_timestamp());
    used integer;
begin
    if caller_id is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    insert into public.variflight_usage_windows (owner_id, window_start, request_count)
    values (caller_id, current_window, 1)
    on conflict (owner_id, window_start) do update
        set request_count = public.variflight_usage_windows.request_count + 1
    returning request_count into used;

    delete from public.variflight_usage_windows
    where owner_id = caller_id and window_start < current_window - interval '24 hours';

    return used <= 30;
end;
$$;

revoke all on function public.consume_variflight_quota() from public, anon;
grant execute on function public.consume_variflight_quota() to authenticated;

comment on function public.consume_variflight_quota() is
    'Atomically consumes one VariFlight proxy request from the authenticated account hourly limit (30).';
