import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonError(405, "Method not allowed");

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return jsonError(401, "登录状态无效，请重新登录。");

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const variflightKey = Deno.env.get("VARIFLIGHT_API_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publishableKey || !variflightKey) {
    console.error("VariFlight proxy is missing required server configuration");
    return jsonError(503, "航班查询服务尚未完成配置。");
  }

  const supabase = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) return jsonError(401, "登录状态无效，请重新登录。");

  const { data: entitlement, error: entitlementError } = await supabase
    .from("account_entitlements")
    .select("edition,status,expires_at")
    .eq("owner_id", user.id)
    .maybeSingle();
  if (entitlementError) {
    console.error("Unable to verify VariFlight entitlement", entitlementError.message);
    return jsonError(503, "暂时无法验证云端账号权限，请稍后重试。");
  }
  const expiry = entitlement?.expires_at ? Date.parse(entitlement.expires_at) : Number.POSITIVE_INFINITY;
  if (!entitlement || !["cloud", "sync"].includes(entitlement.edition)
      || !["active", "grace"].includes(entitlement.status)
      || !Number.isFinite(expiry) && entitlement.expires_at
      || expiry <= Date.now()) {
    return jsonError(403, "此账号当前没有有效的云端航班查询权限。");
  }

  let body: { flightNumber?: unknown; flightDate?: unknown; departureAirport?: unknown; arrivalAirport?: unknown; forceRefresh?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonError(400, "查询参数格式无效。");
  }
  const flightNumber = typeof body.flightNumber === "string"
    ? body.flightNumber.trim().toUpperCase().replace(/[^A-Z0-9]/g, "") : "";
  const flightDate = typeof body.flightDate === "string" ? body.flightDate : "";
  const departureAirport = typeof body.departureAirport === "string" ? body.departureAirport.trim().toUpperCase() : "";
  const arrivalAirport = typeof body.arrivalAirport === "string" ? body.arrivalAirport.trim().toUpperCase() : "";
  const forceRefresh = body.forceRefresh === true;
  if (!/^[A-Z0-9]{2,10}$/.test(flightNumber)) return jsonError(400, "请输入有效的航班号。");
  if ((departureAirport && !/^[A-Z]{3}$/.test(departureAirport)) || (arrivalAirport && !/^[A-Z]{3}$/.test(arrivalAirport))) {
    return jsonError(400, "机场代码格式无效。");
  }
  const parsedDate = /^\d{4}-\d{2}-\d{2}$/.test(flightDate)
    ? new Date(`${flightDate}T00:00:00.000Z`) : null;
  if (!parsedDate || Number.isNaN(parsedDate.getTime()) || parsedDate.toISOString().slice(0, 10) !== flightDate) {
    return jsonError(400, "航班日期格式无效。");
  }

  const queryKey = JSON.stringify([flightNumber, flightDate, departureAirport, arrivalAirport]);
  const queryDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(queryKey));
  const queryHash = Array.from(new Uint8Array(queryDigest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  const cache = serviceRoleKey
    ? createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } })
    : null;

  if (!forceRefresh && cache) {
    const { data: cached, error: cacheError } = await cache
      .from("variflight_response_cache")
      .select("response_text,content_type")
      .eq("query_hash", queryHash)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (cacheError) {
      console.error("Unable to read VariFlight response cache", cacheError.message);
    } else if (cached) {
      return new Response(cached.response_text, {
        status: 200,
        headers: { ...corsHeaders, "Cache-Control": "no-store", "Content-Type": cached.content_type },
      });
    }
  }

  const { data: allowed, error: quotaError } = await supabase.rpc("consume_variflight_quota");
  if (quotaError) {
    console.error("Unable to consume VariFlight quota", quotaError.message);
    return jsonError(503, "暂时无法确认航班查询额度，请稍后重试。");
  }
  if (allowed !== true) return jsonError(429, "查询次数已达上限，请稍后再试。");

  let upstream: Response;
  try {
    upstream = await fetch("https://ai.variflight.com/servers/aviation/mcp", {
      method: "POST",
      redirect: "error",
      headers: {
        "X-API-Key": variflightKey,
        Accept: "application/json, text/event-stream",
        "Content-Type": "application/json",
        "MCP-Protocol-Version": "2025-03-26",
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "searchFlightsByNumber",
          arguments: {
            fnum: flightNumber,
            date: flightDate,
            ...(departureAirport ? { dep: departureAirport } : {}),
            ...(arrivalAirport ? { arr: arrivalAirport } : {}),
          },
        },
      }),
    });
  } catch (error) {
    console.error("VariFlight upstream request failed", error instanceof Error ? error.message : "unknown error");
    return jsonError(502, "无法连接飞友航班服务，请稍后重试。");
  }

  const headers = new Headers(corsHeaders);
  headers.set("Cache-Control", "no-store");
  const contentType = upstream.headers.get("Content-Type") ?? "application/json; charset=utf-8";
  headers.set("Content-Type", contentType);
  if (!upstream.ok) {
    // Do not pass upstream diagnostics through; they can contain provider details.
    console.error("VariFlight upstream returned HTTP", upstream.status);
    const status = upstream.status === 401 ? 502 : upstream.status === 403 ? 503 : 502;
    return jsonError(status, upstream.status === 403
      ? "航班查询服务暂不可用，请联系管理员检查服务额度。"
      : "飞友航班查询失败，请稍后重试。");
  }
  const responseText = await upstream.text();
  const ttlMilliseconds = flightDate > new Date().toISOString().slice(0, 10)
    ? 6 * 60 * 60 * 1000
    : 2 * 60 * 1000;
  const expiresAt = new Date(Date.now() + ttlMilliseconds).toISOString();
  if (cache) {
    const { error: cacheWriteError } = await cache
      .from("variflight_response_cache")
      .upsert({
        query_hash: queryHash,
        response_text: responseText,
        content_type: contentType,
        expires_at: expiresAt,
      }, { onConflict: "query_hash" });
    if (cacheWriteError) console.error("Unable to write VariFlight response cache", cacheWriteError.message);
    await cache.from("variflight_response_cache").delete().lt("expires_at", new Date().toISOString());
  }
  return new Response(responseText, { status: 200, headers });
});
