alter table public.trips
    add column if not exists flight_selection_snapshot jsonb;
