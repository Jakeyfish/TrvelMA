import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type PushJob = {
  message_id: string;
  device_id: string;
  owner_id: string;
  token: string;
  environment: "development" | "production";
  title: string;
  body: string;
};

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const encode = (value: unknown) => b64url(new TextEncoder().encode(JSON.stringify(value)));
let cachedToken: { value: string; expires: number } | undefined;

async function providerToken(): Promise<string | undefined> {
  const pem = Deno.env.get("FLIGHT_APNS_PRIVATE_KEY");
  const kid = Deno.env.get("FLIGHT_APNS_KEY_ID");
  const issuer = Deno.env.get("FLIGHT_APNS_TEAM_ID");
  if (!pem || !kid || !issuer) return;
  const now = Math.floor(Date.now()/1000);
  if (cachedToken && cachedToken.expires > now) return cachedToken.value;
  const bytes = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", bytes, {name:"ECDSA", namedCurve:"P-256"}, false, ["sign"]);
  const input = `${encode({alg:"ES256",kid})}.${encode({iss:issuer,iat:now})}`;
  const signature = await crypto.subtle.sign({name:"ECDSA", hash:"SHA-256"}, key, new TextEncoder().encode(input));
  const value = `${input}.${b64url(new Uint8Array(signature))}`;
  cachedToken = {value,expires:now+3000};
  return value;
}

export async function deliverFlightPush(admin: SupabaseClient) {
  const token = await providerToken();
  if (!token) return;
  const topic = Deno.env.get("FLIGHT_APNS_TOPIC") ?? "com.yunshengtech.travelmanager";
  const {data, error} = await admin.rpc("claim_flight_push", {p_limit: 20});
  if (error) throw Error("Flight push claim failed");
  await Promise.all((data ?? []).map(async (job: PushJob) => {
    try {
      const host = job.environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const response = await fetch(`https://${host}/3/device/${job.token}`, {
        method:"POST", redirect:"error", signal:AbortSignal.timeout(10_000),
        headers: {authorization:`bearer ${token}`, "apns-topic":topic, "apns-push-type":"alert",
          "apns-collapse-id":job.message_id, "apns-expiration":String(Math.floor(Date.now()/1000)+900),
          "content-type":"application/json"},
        body:JSON.stringify({aps:{alert:{title:job.title, body: Array.from(job.body).slice(0,350).join("")},sound:"default"}}),
      });
      await response.body?.cancel();
      const {error: finishError} = await admin.rpc("finish_flight_push", {
        p_message:job.message_id,p_device:job.device_id,p_owner:job.owner_id,p_token:job.token,p_status:response.status
      });
      if (finishError || ![200,410].includes(response.status)) console.error("Flight push delivery failed", response.status);
    } catch {
      console.error("Flight push transport failed");
    }
  }));
}
