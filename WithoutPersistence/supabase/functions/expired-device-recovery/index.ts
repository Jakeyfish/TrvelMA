import { createClient } from "npm:@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization,apikey,content-type,x-account-device-id",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
const reply = (status: number, payload: unknown) =>
  new Response(JSON.stringify(payload), { status, headers });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const options = { auth: { persistSession: false, autoRefreshToken: false } };

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return reply(405, {});
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  const source = request.headers.get("x-account-device-id");
  if (!token || !source || !uuid.test(source)) return reply(401, {});
  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serviceKey) return reply(503, {});
  try {
    const body = await request.json();
    if (!body || !["devices", "issue"].includes(body.action)) return reply(400, {});
    const client = createClient(url, publicKey, options);
    const { data: { user }, error } = await client.auth.getUser(token);
    if (error || !user?.email) return reply(401, {});
    if (user.id !== "86361373-d4ba-4fc6-8f38-420367b6484e") return reply(403, {});
    const admin = createClient(url, serviceKey, options);
    const { data: entitlement } = await admin.from("account_entitlements")
      .select("status,edition,expires_at").eq("owner_id", user.id).maybeSingle();
    if (!entitlement || !["active", "grace", "expired"].includes(entitlement.status)
      || !["cloud", "sync"].includes(entitlement.edition)
      || !entitlement.expires_at || !(Date.parse(entitlement.expires_at) <= Date.now())) return reply(403, {});
    const { data: devices } = await admin.from("account_devices")
      .select("device_id,device_type,last_seen_at,archive_only").eq("owner_id", user.id).is("revoked_at", null);
    if (!devices?.some((device) => device.device_id === source.toLowerCase() && !device.archive_only)) return reply(403, {});
    const choices = devices.filter((device) => device.device_id !== source.toLowerCase());
    if (body.action === "devices") return reply(200, { devices: choices });
    if (typeof body.password !== "string" || !body.password || body.password.length > 1024
      || !choices.some((device) => device.device_id === body.replacedDevice)) return reply(400, {});
    const { error: quotaError } = await admin.rpc("reserve_expired_device_verification", { p_owner: user.id });
    if (quotaError) return reply(429, {});
    const { data: verified, error: passwordError } = await client.auth.signInWithPassword({
      email: user.email, password: body.password,
    });
    if (passwordError || verified.user?.id !== user.id) return reply(401, {});
    const { data: code, error: pairingError } = await admin.rpc("issue_expired_device_pairing", {
      p_owner: user.id, p_source: source, p_old: body.replacedDevice,
    });
    if (pairingError || typeof code !== "string") return reply(403, {});
    return reply(200, { code });
  } catch {
    return reply(400, {});
  }
});
