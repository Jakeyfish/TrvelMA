// Resume the original enrollment so a verifier already saved on the phone keeps working.
export const ADMIN_FACTOR_NAME = '云盛管理后台';
export function selectFactor(factors = []) {
  return factors.find(f => f.factor_type === 'totp' && f.status === 'verified')
    || factors.find(f => f.factor_type === 'totp' && f.status === 'unverified' && f.friendly_name === ADMIN_FACTOR_NAME)
    || null;
}
export async function findFactor(request) {
  const user = await request('/auth/v1/user', undefined, 'GET');
  return selectFactor(user.factors || []);
}
export async function enrollOrResume(request) {
  const existing = await findFactor(request);
  if (existing) return { factor: existing, resumed: true };
  try {
    const result = await request('/auth/v1/factors', {factor_type: 'totp', friendly_name: ADMIN_FACTOR_NAME});
    return {factor: result, secret: result.totp.secret, resumed: false};
  } catch (error) {
    if (error.code !== 'mfa_factor_name_conflict') throw error;
    // A concurrent tab may have enrolled after our first GET. Never delete or replace its factor.
    const concurrent = await findFactor(request);
    if (concurrent) return {factor: concurrent, resumed: true};
    throw error;
  }
}
