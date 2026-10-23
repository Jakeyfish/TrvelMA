-- Enforce cloud access at the database boundary. Existing accounts are
-- grandfathered as sync accounts; new accounts need an explicit server grant.
insert into public.account_entitlements (owner_id, edition, status, max_devices)
select id, 'sync', 'active', 100
from auth.users
on conflict (owner_id) do nothing;

create or replace function public.can_access_cloud_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.account_entitlements as entitlement
        where entitlement.owner_id = (select auth.uid())
          and entitlement.edition in ('cloud', 'sync')
          and entitlement.status in ('active', 'grace')
          and (entitlement.expires_at is null or entitlement.expires_at > statement_timestamp())
    );
$$;

revoke all on function public.can_access_cloud_data() from public, anon;
grant execute on function public.can_access_cloud_data() to authenticated;

drop policy if exists profiles_read_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_delete_own on public.profiles;
create policy profiles_read_own on public.profiles
    for select to authenticated using (id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy profiles_insert_own on public.profiles
    for insert to authenticated with check (id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy profiles_update_own on public.profiles
    for update to authenticated using (id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy profiles_delete_own on public.profiles
    for delete to authenticated using (id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists agencies_read_own on public.travel_agencies;
drop policy if exists agencies_insert_own on public.travel_agencies;
drop policy if exists agencies_update_own on public.travel_agencies;
drop policy if exists agencies_delete_own on public.travel_agencies;
create policy agencies_read_own on public.travel_agencies
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy agencies_insert_own on public.travel_agencies
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy agencies_update_own on public.travel_agencies
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy agencies_delete_own on public.travel_agencies
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists customers_read_own on public.customers;
drop policy if exists customers_insert_own on public.customers;
drop policy if exists customers_update_own on public.customers;
drop policy if exists customers_delete_own on public.customers;
create policy customers_read_own on public.customers
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy customers_insert_own on public.customers
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy customers_update_own on public.customers
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy customers_delete_own on public.customers
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists contacts_read_own on public.customer_contacts;
drop policy if exists contacts_insert_own on public.customer_contacts;
drop policy if exists contacts_update_own on public.customer_contacts;
drop policy if exists contacts_delete_own on public.customer_contacts;
create policy contacts_read_own on public.customer_contacts
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy contacts_insert_own on public.customer_contacts
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy contacts_update_own on public.customer_contacts
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy contacts_delete_own on public.customer_contacts
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists addresses_read_own on public.customer_addresses;
drop policy if exists addresses_insert_own on public.customer_addresses;
drop policy if exists addresses_update_own on public.customer_addresses;
drop policy if exists addresses_delete_own on public.customer_addresses;
create policy addresses_read_own on public.customer_addresses
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy addresses_insert_own on public.customer_addresses
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy addresses_update_own on public.customer_addresses
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy addresses_delete_own on public.customer_addresses
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists trips_read_own on public.trips;
drop policy if exists trips_insert_own on public.trips;
drop policy if exists trips_update_own on public.trips;
drop policy if exists trips_delete_own on public.trips;
create policy trips_read_own on public.trips
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy trips_insert_own on public.trips
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy trips_update_own on public.trips
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy trips_delete_own on public.trips
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists stops_read_own on public.trip_stops;
drop policy if exists stops_insert_own on public.trip_stops;
drop policy if exists stops_update_own on public.trip_stops;
drop policy if exists stops_delete_own on public.trip_stops;
create policy stops_read_own on public.trip_stops
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy stops_insert_own on public.trip_stops
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy stops_update_own on public.trip_stops
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy stops_delete_own on public.trip_stops
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists expenses_read_own on public.trip_expenses;
drop policy if exists expenses_insert_own on public.trip_expenses;
drop policy if exists expenses_update_own on public.trip_expenses;
drop policy if exists expenses_delete_own on public.trip_expenses;
create policy expenses_read_own on public.trip_expenses
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy expenses_insert_own on public.trip_expenses
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy expenses_update_own on public.trip_expenses
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy expenses_delete_own on public.trip_expenses
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

drop policy if exists settings_read_own on public.user_settings;
drop policy if exists settings_insert_own on public.user_settings;
drop policy if exists settings_update_own on public.user_settings;
drop policy if exists settings_delete_own on public.user_settings;
create policy settings_read_own on public.user_settings
    for select to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy settings_insert_own on public.user_settings
    for insert to authenticated with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy settings_update_own on public.user_settings
    for update to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()))
    with check (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));
create policy settings_delete_own on public.user_settings
    for delete to authenticated using (owner_id = (select auth.uid()) and (select public.can_access_cloud_data()));

-- Storage access follows the same active cloud/sync grant as business records.
drop policy if exists account_assets_read_own on storage.objects;
drop policy if exists account_assets_insert_own on storage.objects;
drop policy if exists account_assets_update_own on storage.objects;
drop policy if exists account_assets_delete_own on storage.objects;
create policy account_assets_read_own on storage.objects
    for select to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text
           and (select public.can_access_cloud_data()));
create policy account_assets_insert_own on storage.objects
    for insert to authenticated
    with check (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text
                and (select public.can_access_cloud_data()));
create policy account_assets_update_own on storage.objects
    for update to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text
           and (select public.can_access_cloud_data()))
    with check (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text
                and (select public.can_access_cloud_data()));
create policy account_assets_delete_own on storage.objects
    for delete to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text
           and (select public.can_access_cloud_data()));

comment on function public.can_access_cloud_data() is
    'Checks active cloud/sync access for the authenticated account. New accounts need a server-created entitlement.';

-- Atomic online-edition customer write. Replacing a customer's related rows
-- and the parent record happens in one transaction; no offline queue is used.
create or replace function public.save_online_customer(
    p_customer jsonb,
    p_contacts jsonb default '[]'::jsonb,
    p_addresses jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_customer_id uuid;
    v_rows_changed integer;
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;
    if jsonb_typeof(p_customer) <> 'object'
       or nullif(p_customer ->> 'id', '') is null
       or nullif(btrim(p_customer ->> 'name'), '') is null then
        raise exception 'Customer id and name are required' using errcode = '22023';
    end if;
    begin
        v_customer_id := (p_customer ->> 'id')::uuid;
    exception when invalid_text_representation then
        raise exception 'Customer id must be a UUID' using errcode = '22023';
    end;
    if jsonb_typeof(coalesce(p_contacts, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_addresses, '[]'::jsonb)) <> 'array' then
        raise exception 'Contacts and addresses must be arrays' using errcode = '22023';
    end if;

    insert into public.customers (
        id, owner_id, name, email, avatar_url, source, type, category,
        travel_agency_code, travel_agency_name, language_preference, remark,
        created_at, updated_at, deleted_at
    ) values (
        v_customer_id, v_owner_id,
        p_customer ->> 'name', coalesce(p_customer ->> 'email', ''),
        coalesce(p_customer ->> 'avatar_url', ''), coalesce(p_customer ->> 'source', ''),
        coalesce((p_customer ->> 'type')::integer, 1),
        coalesce((p_customer ->> 'category')::integer, 1),
        coalesce(p_customer ->> 'travel_agency_code', ''),
        coalesce(p_customer ->> 'travel_agency_name', ''),
        coalesce(p_customer ->> 'language_preference', 'zh-Hans'),
        coalesce(p_customer ->> 'remark', ''),
        coalesce((p_customer ->> 'created_at')::timestamptz, statement_timestamp()),
        statement_timestamp(), null
    )
    on conflict (id) do update set
        name = excluded.name,
        email = excluded.email,
        avatar_url = excluded.avatar_url,
        source = excluded.source,
        type = excluded.type,
        category = excluded.category,
        travel_agency_code = excluded.travel_agency_code,
        travel_agency_name = excluded.travel_agency_name,
        language_preference = excluded.language_preference,
        remark = excluded.remark,
        updated_at = statement_timestamp(),
        deleted_at = null
    where public.customers.owner_id = v_owner_id;

    get diagnostics v_rows_changed = row_count;
    if v_rows_changed = 0 then
        raise exception 'Customer belongs to a different account' using errcode = '42501';
    end if;

    update public.customer_contacts
       set deleted_at = statement_timestamp(), updated_at = statement_timestamp()
     where owner_id = v_owner_id and customer_id = v_customer_id and deleted_at is null;
    insert into public.customer_contacts (
        id, owner_id, customer_id, label, contact_type, value, is_default, created_at, updated_at
    )
    select contact.id, v_owner_id, v_customer_id, coalesce(contact.label, ''),
           coalesce(contact.contact_type, ''), contact.value, coalesce(contact.is_default, false),
           statement_timestamp(), statement_timestamp()
      from jsonb_to_recordset(coalesce(p_contacts, '[]'::jsonb)) as contact(
          id uuid, label text, contact_type text, value text, is_default boolean
      )
    on conflict (id) do update set
        label = excluded.label,
        contact_type = excluded.contact_type,
        value = excluded.value,
        is_default = excluded.is_default,
        updated_at = statement_timestamp(),
        deleted_at = null
    where public.customer_contacts.owner_id = v_owner_id
      and public.customer_contacts.customer_id = v_customer_id;
    get diagnostics v_rows_changed = row_count;
    if v_rows_changed <> jsonb_array_length(coalesce(p_contacts, '[]'::jsonb)) then
        raise exception 'Contact id belongs to a different account or customer' using errcode = '42501';
    end if;

    update public.customer_addresses
       set deleted_at = statement_timestamp(), updated_at = statement_timestamp()
     where owner_id = v_owner_id and customer_id = v_customer_id and deleted_at is null;
    insert into public.customer_addresses (
        id, owner_id, customer_id, label, address, is_default, created_at, updated_at
    )
    select address.id, v_owner_id, v_customer_id, coalesce(address.label, ''),
           address.address, coalesce(address.is_default, false),
           statement_timestamp(), statement_timestamp()
      from jsonb_to_recordset(coalesce(p_addresses, '[]'::jsonb)) as address(
          id uuid, label text, address text, is_default boolean
      )
    on conflict (id) do update set
        label = excluded.label,
        address = excluded.address,
        is_default = excluded.is_default,
        updated_at = statement_timestamp(),
        deleted_at = null
    where public.customer_addresses.owner_id = v_owner_id
      and public.customer_addresses.customer_id = v_customer_id;
    get diagnostics v_rows_changed = row_count;
    if v_rows_changed <> jsonb_array_length(coalesce(p_addresses, '[]'::jsonb)) then
        raise exception 'Address id belongs to a different account or customer' using errcode = '42501';
    end if;
end;
$$;

revoke all on function public.save_online_customer(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.save_online_customer(jsonb, jsonb, jsonb) to authenticated;

comment on function public.save_online_customer(jsonb, jsonb, jsonb) is
    'Atomically saves a customer, contacts, and addresses for the authenticated account with active cloud access.';

create or replace function public.delete_online_customer(p_customer_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_deleted_at timestamptz := statement_timestamp();
    v_rows_changed integer;
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;

    if exists (
        select 1 from public.trips
         where customer_id = p_customer_id
           and owner_id = v_owner_id
           and deleted_at is null
    ) then
        raise exception 'Customer has trip history and cannot be deleted' using errcode = '23503';
    end if;

    update public.customers
       set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where id = p_customer_id and owner_id = v_owner_id and deleted_at is null;
    get diagnostics v_rows_changed = row_count;
    if v_rows_changed = 0 then
        raise exception 'Customer is unavailable for this account' using errcode = '42501';
    end if;

    update public.customer_contacts
       set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where customer_id = p_customer_id and owner_id = v_owner_id and deleted_at is null;
    update public.customer_addresses
       set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where customer_id = p_customer_id and owner_id = v_owner_id and deleted_at is null;
end;
$$;

revoke all on function public.delete_online_customer(uuid) from public, anon;
grant execute on function public.delete_online_customer(uuid) to authenticated;

comment on function public.delete_online_customer(uuid) is
    'Atomically soft-deletes a customer and its contact/address rows for the authenticated account.';

-- Online trips replace the parent and both child collections in one request,
-- so the UI cannot report a partially saved trip.
create or replace function public.save_online_trip(
    p_trip jsonb,
    p_stops jsonb default '[]'::jsonb,
    p_expenses jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_trip public.trips%rowtype;
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;
    if pg_catalog.jsonb_typeof(p_trip) <> 'object'
       or pg_catalog.jsonb_typeof(coalesce(p_stops, '[]'::jsonb)) <> 'array'
       or pg_catalog.jsonb_typeof(coalesce(p_expenses, '[]'::jsonb)) <> 'array' then
        raise exception 'Invalid trip payload' using errcode = '22023';
    end if;

    v_trip := pg_catalog.jsonb_populate_record(null::public.trips, p_trip);
    if v_trip.id is null or v_trip.appointment_date is null or v_trip.appointment_time is null
       or v_trip.flight_date is null then
        raise exception 'Trip identity and dates are required' using errcode = '22023';
    end if;
    if v_trip.customer_id is not null and not exists (
        select 1 from public.customers c
         where c.id = v_trip.customer_id and c.owner_id = v_owner_id and c.deleted_at is null
    ) then
        raise exception 'Customer is unavailable for this account' using errcode = '42501';
    end if;

    v_trip.owner_id := v_owner_id;
    v_trip.created_at := coalesce(v_trip.created_at, statement_timestamp());
    v_trip.updated_at := statement_timestamp();
    v_trip.deleted_at := null;

    -- The delete and insert share this transaction. A duplicate id owned by a
    -- different account still causes the following insert to fail safely.
    delete from public.trips where id = v_trip.id and owner_id = v_owner_id;
    insert into public.trips select (v_trip).*;

    insert into public.trip_stops (id, owner_id, trip_id, position, address, created_at, updated_at)
    select stop.id, v_owner_id, v_trip.id, stop.position, stop.address,
           statement_timestamp(), statement_timestamp()
      from pg_catalog.jsonb_to_recordset(coalesce(p_stops, '[]'::jsonb)) as stop(
          id uuid, position integer, address text
      );

    insert into public.trip_expenses (id, owner_id, trip_id, is_addition, title, amount, position, created_at, updated_at)
    select expense.id, v_owner_id, v_trip.id, coalesce(expense.is_addition, false),
           coalesce(expense.title, ''), coalesce(expense.amount, 0), coalesce(expense.position, 0),
           statement_timestamp(), statement_timestamp()
      from pg_catalog.jsonb_to_recordset(coalesce(p_expenses, '[]'::jsonb)) as expense(
          id uuid, is_addition boolean, title text, amount numeric, position integer
      );
end;
$$;

revoke all on function public.save_online_trip(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.save_online_trip(jsonb, jsonb, jsonb) to authenticated;

create or replace function public.delete_online_trip(p_trip_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_owner_id uuid := (select auth.uid());
    v_deleted_at timestamptz := statement_timestamp();
    v_rows_changed integer;
begin
    if v_owner_id is null or not (select public.can_access_cloud_data()) then
        raise exception 'Active cloud entitlement required' using errcode = '42501';
    end if;
    update public.trips
       set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where id = p_trip_id and owner_id = v_owner_id and deleted_at is null;
    get diagnostics v_rows_changed = row_count;
    if v_rows_changed = 0 then
        raise exception 'Trip is unavailable for this account' using errcode = '42501';
    end if;
    update public.trip_stops set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where trip_id = p_trip_id and owner_id = v_owner_id and deleted_at is null;
    update public.trip_expenses set deleted_at = v_deleted_at, updated_at = v_deleted_at
     where trip_id = p_trip_id and owner_id = v_owner_id and deleted_at is null;
end;
$$;

revoke all on function public.delete_online_trip(uuid) from public, anon;
grant execute on function public.delete_online_trip(uuid) to authenticated;
