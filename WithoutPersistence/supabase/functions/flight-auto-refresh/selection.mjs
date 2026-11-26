const fields = {
  actualDeparture: ['flightdeptimeDate', 'actualDepartureTime', 'actualDeparture'],
  estimatedDeparture: ['flightdeptimeReadyDate', 'estimatedDepartureTime', 'estimatedDeparture'],
  scheduledDeparture: ['flightdeptimePlanDate', 'scheduledDepartureTime', 'scheduledDeparture'],
  originalScheduledDeparture: ['FFlightDeptimePlanDate', 'originalScheduledDeparture'],
  actualArrival: ['flightarrtimeDate', 'actualArrivalTime', 'actualArrival'],
  estimatedArrival: ['flightarrtimeReadyDate', 'estimatedArrivalTime', 'estimatedArrival'],
  scheduledArrival: ['flightarrtimePlanDate', 'scheduledArrivalTime', 'scheduledArrival'],
  departureTerminal: ['FlightHTerminal', 'departureTerminal'],
  arrivalTerminal: ['FlightTerminal', 'arrivalTerminal'],
  baggageCarousel: ['BaggageID', 'baggageCarousel'],
  status: ['FlightState', 'FlightStatus', 'status'],
};

const value = input => typeof input === 'string' && !/^(?:null|--)?$/i.test(input.trim()) ? input.trim() : undefined;

function records(data) {
  if (typeof data === 'string') {
    try { return records(JSON.parse(data)); } catch { /* MCP text and SSE below */ }
    const events = data.split(/\r?\n/).filter(line => line.startsWith('data:'));
    if (events.length) return events.flatMap(line => records(line.slice(5).trim()));
    return [...data.matchAll(/\{[^{}]*\}/g)].map(match =>
      Object.fromEntries([...match[0].matchAll(/['"]([\w]+)['"]\s*:\s*['"]([^'"]*)['"]/g)]
        .map(pair => [pair[1], pair[2]])));
  }
  if (Array.isArray(data)) return data.flatMap(records);
  if (!data || typeof data !== 'object' || data.error || data.isError) return [];
  if (data.type === 'text') return records(data.text);
  return [data, ...Object.values(data).filter(item => item && typeof item === 'object').flatMap(records)];
}

export function selectFlightUpdate(payload, { flight_number, departure_date, departure, arrival }) {
  const candidates = records(payload).flatMap(record => {
    const row = Object.fromEntries(Object.entries(record).map(([key, item]) => [key.toLowerCase(), item]));
    const read = (...keys) => keys.map(key => value(row[key.toLowerCase()])).find(Boolean);
    if (read('FlightDepcode', 'departureAirportCode', 'departureAirport')?.toUpperCase() !== departure
        || read('FlightArrcode', 'arrivalAirportCode', 'arrivalAirport')?.toUpperCase() !== arrival) return [];
    const number = read('FlightNo', 'flightNumber', 'fnum');
    if (number && number.toUpperCase() !== flight_number) return [];
    const selected = Object.fromEntries(Object.entries(fields).flatMap(([key, aliases]) => {
      const item = read(...aliases);
      return item ? [[key, item]] : [];
    }));
    for (const key of ['actualDeparture','estimatedDeparture','scheduledDeparture','originalScheduledDeparture','actualArrival','estimatedArrival','scheduledArrival']) {
      if (selected[key] && !/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}/.test(selected[key])) delete selected[key];
    }
    if (departure_date && selected.scheduledDeparture && selected.scheduledDeparture.slice(0,10) !== departure_date) return [];
    if (!Object.keys(selected).length) return [];
    return [selected];
  });
  // Prefer status-bearing operational records over a schedule-only summary.
  const score = row => 8 * Number(Boolean(row.actualArrival)) + 4 * Number(Boolean(row.status))
    + 2 * Number(Boolean(row.estimatedArrival)) + Number(Boolean(row.actualDeparture));
  const selected = candidates.sort((a,b) => score(b) - score(a))[0];
  if (!selected) return null;
  const status = selected.status?.toLowerCase();
  const landed = selected.actualArrival || ['landed','arrived','到达','到達','抵达','抵達','落地','已落地','已到达','已到達'].includes(status);
  const cancelled = ['cancelled', 'canceled', '取消', '已取消'].includes(status);
  if (landed && !cancelled) selected.status = 'landed';
  const currentArrival = selected.estimatedArrival || selected.scheduledArrival;
  if (currentArrival) selected.estimatedArrivalTime = currentArrival;
  return { selected, state: cancelled ? 'cancelled' : landed ? 'landed' : 'tracking' };
}
