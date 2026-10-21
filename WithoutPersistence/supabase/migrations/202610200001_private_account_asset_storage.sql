-- Private storage for business-card portraits, contact QR codes, and payment QR codes.
-- Apply after the account-assets JSONB migration. Object names are prefixed by auth.uid().

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'account-assets',
    'account-assets',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists account_assets_read_own on storage.objects;
drop policy if exists account_assets_insert_own on storage.objects;
drop policy if exists account_assets_update_own on storage.objects;
drop policy if exists account_assets_delete_own on storage.objects;

create policy account_assets_read_own on storage.objects
    for select to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy account_assets_insert_own on storage.objects
    for insert to authenticated
    with check (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy account_assets_update_own on storage.objects
    for update to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text)
    with check (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy account_assets_delete_own on storage.objects
    for delete to authenticated
    using (bucket_id = 'account-assets' and (storage.foldername(name))[1] = (select auth.uid())::text);
