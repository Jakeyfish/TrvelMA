// A decoded claim only selects a verifier. The selected Apple verifier and
// transaction normalization still enforce the environment before persistence.
export function storekitEnvironment(mode, productionEnabled, signed, notification = false) {
  let environment = mode;
  if (mode === 'Dual') {
    if (typeof signed !== 'string' || signed.length > (notification ? 262144 : 65536)) throw Error('INVALID_JWS');
    const parts = signed.split('.');
    if (parts.length !== 3 || !parts.every(part => /^[A-Za-z0-9_-]+$/.test(part))) throw Error('INVALID_JWS');
    try {
      const bytes = Uint8Array.from(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')), char => char.charCodeAt(0));
      const claim = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
      environment = notification ? (claim.data ?? claim.summary ?? claim.appData)?.environment : claim.environment;
    } catch {
      throw Error('INVALID_JWS');
    }
    if (environment !== 'Sandbox' && environment !== 'Production') throw Error('ENVIRONMENT_REQUIRED');
  }
  if (environment !== 'Sandbox' && environment !== 'Production') throw Error('BILLING_DISABLED');
  if (environment === 'Production' && !productionEnabled) throw Error('BILLING_DISABLED');
  return environment;
}

// Availability only. This claim selects a gate and cannot authorize transaction persistence.
export function checkPurchaseAvailability(mode, productionEnabled, environment, ownerID, sandboxOwners) {
  if (environment !== 'Sandbox' && environment !== 'Production') throw Error('ENVIRONMENT_REQUIRED');
  if (mode !== 'Dual' && mode !== environment) throw Error('BILLING_DISABLED');
  if (environment === 'Production' && !productionEnabled) throw Error('BILLING_DISABLED');
  if (environment === 'Sandbox' && !sandboxOwners.has(ownerID.toLowerCase())) {
    throw Error('SANDBOX_ACCOUNT_NOT_ALLOWED');
  }
  return { available: true, environment };
}
