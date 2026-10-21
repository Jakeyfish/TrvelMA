alter table public.user_settings
    add column if not exists business_card_data jsonb,
    add column if not exists business_card_data_updated_at timestamptz,
    add column if not exists wallet_payment_methods jsonb,
    add column if not exists wallet_payment_methods_updated_at timestamptz;
