import { deliverFlightPush } from "./push.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { queryVariFlight } from "../_shared/variflight-provider.ts";
import { lookupAutomaticFlight } from "./lookup.mjs";

type FlightAutoJob = {
  owner_id: string;
  flight_number: string;
  departure_date: string;
  departure: string;
  arrival: string;
  lease_id: string;
  stage: number;
};

Deno.serve(async (request) => {
  const cronSecret = Deno.env.get("FLIGHT_AUTO_REFRESH_SECRET");
  if (request.method !== "POST") return new Response(null, { status: 405 });
  if (!cronSecret || request.headers.get("Authorization") !== `Bearer ${cronSecret}`) {
    return new Response(null, { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const providerKey = Deno.env.get("VARIFLIGHT_API_KEY");
  if (!url || !serviceKey || !providerKey) return new Response(null, { status: 503 });

  const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
  const [arrival, departure] = await Promise.all([
    supabase.rpc("claim_flight_auto_jobs", { p_limit: 8 }),
    supabase.rpc("claim_flight_departure_jobs", { p_limit: 8 }),
  ]);
  if (arrival.error && departure.error) {
    console.error("Unable to claim automatic flight checks", arrival.error.code, departure.error.code);
    return new Response(null, { status: 503 });
  }

  const jobs: { job: FlightAutoJob; departure: boolean }[] = [
    ...(arrival.data ?? []).map((job: FlightAutoJob) => ({job, departure:false})),
    ...(departure.data ?? []).map((job: FlightAutoJob) => ({job, departure:true})),
  ];
  const results = await Promise.all(jobs.map(async ({job, departure}) => {
    const checkedAt = new Date().toISOString();
    let update = null;
    let lookupFailed = false;
    try {
      update = await lookupAutomaticFlight({
        rpc: (name: string, args: Record<string, unknown>) => supabase.rpc(name, args),
        query: () => queryVariFlight(providerKey, job.flight_number, job.departure_date, job.departure, job.arrival),
        charge: Deno.env.get("FLIGHT_BEANS_ENFORCED") === "true",
        job,
        departure,
      });
    } catch {
      lookupFailed = true;
      console.error("Automatic flight lookup failed");
    }

    const result = { p_lease: job.lease_id, p_selected: update?.selected ?? null, p_checked_at: checkedAt };
    const { error: finishError } = departure
      ? await supabase.rpc("finish_flight_departure_job", result)
      : await supabase.rpc("finish_flight_auto_job", {...result,
        p_state: update?.state ?? (job.stage === 1 ? "tracking" : "unconfirmed")});
    if (finishError) console.error("Unable to persist automatic flight check", finishError.code);
    return !finishError && !lookupFailed;
  }));
  try { await deliverFlightPush(supabase); }
  catch { console.error("Flight push is unavailable"); }
  return Response.json({ claimed: jobs.length, saved: results.filter(Boolean).length },
    { status: !arrival.error && !departure.error && results.every(Boolean) ? 200 : 503 });
});
