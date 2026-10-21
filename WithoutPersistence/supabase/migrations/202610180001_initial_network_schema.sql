-- Initial network schema for the travel-management app.
-- Apply only to a new Supabase project after reviewing the schema and RLS policies.

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    salutation text not null default '',
    phone text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.travel_agencies (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    agency_code text not null,
    name text not null,
    contact_person text not null default '',
    phone text not null default '',
    office_address text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (owner_id, agency_code),
    unique (id, owner_id)
);

create table public.customers (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    name text not null,
    email text not null default '',
    avatar_url text not null default '',
    source text not null default '',
    type integer not null default 1,
    category integer not null default 1,
    travel_agency_code text not null default '',
    travel_agency_name text not null default '',
    language_preference text not null default 'zh-Hans',
    remark text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (id, owner_id)
);

create table public.customer_contacts (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    customer_id uuid not null,
    label text not null default '',
    contact_type text not null,
    value text not null,
    is_default boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (id, owner_id),
    foreign key (customer_id, owner_id)
        references public.customers (id, owner_id) on delete cascade
);

create table public.customer_addresses (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    customer_id uuid not null,
    label text not null default '',
    address text not null,
    is_default boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (id, owner_id),
    foreign key (customer_id, owner_id)
        references public.customers (id, owner_id) on delete cascade
);

create table public.trips (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    service_type text not null,
    order_source text not null,
    travel_agency_code text not null default '',
    travel_agency_name text not null default '',
    customer_id uuid,
    customer_name text not null default '',
    customer_contact text not null default '',
    customer_count text not null default '1',
    customer_stuff text not null default '0',
    appointment_date timestamptz not null,
    appointment_time timestamptz not null,
    location_start text not null default '',
    location_end text not null default '',
    flight_info text not null default '',
    flight_date timestamptz not null,
    flight_departure_time text,
    flight_estimated_arrival_time text,
    flight_arrival_terminal text,
    flight_baggage_carousel text,
    memo text not null default '',
    price numeric(12, 2) not null default 0,
    tip numeric(12, 2) not null default 0,
    is_paid boolean not null default false,
    is_completed boolean not null default false,
    is_cancelled boolean not null default false,
    reminder_enabled boolean not null default false,
    reminder_at timestamptz,
    has_second_reminder boolean not null default false,
    second_reminder_at timestamptz,
    currency_code text not null default 'USD',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (id, owner_id),
    foreign key (customer_id, owner_id)
        references public.customers (id, owner_id) on delete set null (customer_id)
);

create table public.trip_stops (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    trip_id uuid not null,
    position integer not null,
    address text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (trip_id, position),
    foreign key (trip_id, owner_id)
        references public.trips (id, owner_id) on delete cascade
);

create table public.trip_expenses (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete cascade,
    trip_id uuid not null,
    is_addition boolean not null default false,
    title text not null default '',
    amount numeric(12, 2) not null default 0,
    position integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    foreign key (trip_id, owner_id)
        references public.trips (id, owner_id) on delete cascade
);

create table public.user_settings (
    owner_id uuid primary key references auth.users (id) on delete cascade,
    language_code text not null default 'zh-Hans',
    currency_country_code text not null default 'US',
    currency_name text not null default '美元',
    currency_code text not null default 'USD',
    currency_symbol text not null default '$',
    navigation_provider text not null default 'apple_maps',
    expense_catalog jsonb not null default '["居间费", "高速通行费"]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index customers_owner_updated_idx on public.customers (owner_id, updated_at desc);
create index trips_owner_appointment_idx on public.trips (owner_id, appointment_date);
create index travel_agencies_owner_updated_idx on public.travel_agencies (owner_id, updated_at desc);
create index customer_contacts_customer_idx on public.customer_contacts (owner_id, customer_id);
create index customer_addresses_customer_idx on public.customer_addresses (owner_id, customer_id);
create index trip_stops_trip_idx on public.trip_stops (owner_id, trip_id, position);
create index trip_expenses_trip_idx on public.trip_expenses (owner_id, trip_id, position);

-- Every exposed table is owner-scoped. Keep service-role credentials server-side.
do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'profiles', 'travel_agencies', 'customers', 'customer_contacts',
        'customer_addresses', 'trips', 'trip_stops', 'trip_expenses', 'user_settings'
    ] loop
        execute format('alter table public.%I enable row level security', table_name);
        execute format('revoke all on table public.%I from anon', table_name);
        execute format('grant select, insert, update, delete on table public.%I to authenticated', table_name);
    end loop;
end $$;

create policy profiles_read_own on public.profiles
    for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles
    for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
    for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy profiles_delete_own on public.profiles
    for delete to authenticated using (id = (select auth.uid()));

create policy agencies_read_own on public.travel_agencies
    for select to authenticated using (owner_id = (select auth.uid()));
create policy agencies_insert_own on public.travel_agencies
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy agencies_update_own on public.travel_agencies
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy agencies_delete_own on public.travel_agencies
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy customers_read_own on public.customers
    for select to authenticated using (owner_id = (select auth.uid()));
create policy customers_insert_own on public.customers
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy customers_update_own on public.customers
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy customers_delete_own on public.customers
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy contacts_read_own on public.customer_contacts
    for select to authenticated using (owner_id = (select auth.uid()));
create policy contacts_insert_own on public.customer_contacts
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy contacts_update_own on public.customer_contacts
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy contacts_delete_own on public.customer_contacts
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy addresses_read_own on public.customer_addresses
    for select to authenticated using (owner_id = (select auth.uid()));
create policy addresses_insert_own on public.customer_addresses
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy addresses_update_own on public.customer_addresses
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy addresses_delete_own on public.customer_addresses
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy trips_read_own on public.trips
    for select to authenticated using (owner_id = (select auth.uid()));
create policy trips_insert_own on public.trips
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy trips_update_own on public.trips
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy trips_delete_own on public.trips
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy stops_read_own on public.trip_stops
    for select to authenticated using (owner_id = (select auth.uid()));
create policy stops_insert_own on public.trip_stops
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy stops_update_own on public.trip_stops
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy stops_delete_own on public.trip_stops
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy expenses_read_own on public.trip_expenses
    for select to authenticated using (owner_id = (select auth.uid()));
create policy expenses_insert_own on public.trip_expenses
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy expenses_update_own on public.trip_expenses
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy expenses_delete_own on public.trip_expenses
    for delete to authenticated using (owner_id = (select auth.uid()));

create policy settings_read_own on public.user_settings
    for select to authenticated using (owner_id = (select auth.uid()));
create policy settings_insert_own on public.user_settings
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy settings_update_own on public.user_settings
    for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy settings_delete_own on public.user_settings
    for delete to authenticated using (owner_id = (select auth.uid()));
