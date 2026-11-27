import { selectFlightUpdate } from "./selection.mjs";

export async function lookupAutomaticFlight({ rpc, query, charge, job, departure }) {
  async function call(name, args) {
    const { data, error } = await rpc(name, args);
    if (error) throw error;
    return data;
  }

  const reservation = { p_owner: job.owner_id, p_hold: job.lease_id };
  if (charge && !await call("reserve_flight_bean", reservation)) return null;

  let update = null;
  try {
    if (!await call("consume_variflight_quota_for", { p_owner: job.owner_id })) return null;
    if (!await call("admit_flight_auto_attempt", {
      p_lease: job.lease_id,
      p_departure: departure,
    })) return null;

    const response = await query();
    if (response.ok) update = selectFlightUpdate(await response.text(), job);
    return update;
  } finally {
    if (charge) {
      const settled = await call("finish_flight_bean", { ...reservation, p_charge: update !== null });
      if (!settled) throw new Error("Unable to settle automatic flight lookup");
    }
  }
}
