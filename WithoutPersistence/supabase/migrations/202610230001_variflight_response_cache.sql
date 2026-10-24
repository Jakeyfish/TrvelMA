create table if not exists public.variflight_response_cache (
    query_hash text primary key check (query_hash ~ '^[0-9a-f]{64}$'),
    response_text text not null,
    content_type text not null default 'application/json; charset=utf-8',
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

alter table public.variflight_response_cache enable row level security;
revoke all on public.variflight_response_cache from public, anon, authenticated;
grant all on public.variflight_response_cache to service_role;

create index if not exists variflight_response_cache_expires_at_idx
    on public.variflight_response_cache (expires_at);

comment on table public.variflight_response_cache is
    'Shared cache of public flight provider responses. Only the server-side service role can access it.';
