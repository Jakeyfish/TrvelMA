// The caller verifies entitlements and consumes quota before requesting a fresh result.
export function queryVariFlight(variflightKey: string, flightNumber: string, flightDate: string,
                                departureAirport: string, arrivalAirport: string): Promise<Response> {
  return fetch("https://ai.variflight.com/servers/aviation/mcp", {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
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
}
