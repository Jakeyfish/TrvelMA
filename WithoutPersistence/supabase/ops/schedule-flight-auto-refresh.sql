-- Run after the migrations and Edge Function are deployed and verified.
-- Provision matching secrets separately in Vault and the Edge environment.
create extension if not exists pg_net;
create extension if not exists pg_cron;
select cron.schedule('flight-auto-refresh', '* * * * *', $job$
    select net.http_post(
        url := rtrim(url.decrypted_secret, '/') || '/functions/v1/flight-auto-refresh',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || secret.decrypted_secret),
        body := '{}'::jsonb,
        timeout_milliseconds := 55000
    )
    from vault.decrypted_secrets url, vault.decrypted_secrets secret
    where url.name = 'flight_auto_project_url' and secret.name = 'flight_auto_refresh_secret';
$job$);
