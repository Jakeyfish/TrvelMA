// Only values returned by Apple's signature verifier may enter this module.
export const bundleID = 'com.yunshengtech.travelmanager';
export const cloudProducts = new Set([
  `${bundleID}.cloud.monthly`, `${bundleID}.cloud.yearly`,
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const fail = code => { throw new Error(code); };
const timestamp = value => Number.isSafeInteger(value) && value > 0;

export function normalizeTransaction(tx, { ownerID, environment, now = Date.now(), renewal, notification } = {}) {
  if (!['Production', 'Sandbox'].includes(environment)) fail('ENVIRONMENT_REQUIRED');
  if (tx?.bundleId !== bundleID || tx.environment !== environment) fail('WRONG_APP_OR_ENVIRONMENT');
  if (!cloudProducts.has(tx.productId) || tx.type !== 'Auto-Renewable Subscription') fail('UNSUPPORTED_PRODUCT');
  if (!uuid.test(ownerID || '') || typeof tx.appAccountToken !== 'string'
      || tx.appAccountToken.toLowerCase() !== ownerID.toLowerCase()) fail('ACCOUNT_MISMATCH');
  if (tx.inAppOwnershipType !== 'PURCHASED') fail('UNSUPPORTED_OWNERSHIP');
  for (const id of [tx.transactionId, tx.originalTransactionId]) {
    if (typeof id !== 'string' || !/^\d{1,128}$/.test(id)) fail('INVALID_TRANSACTION_ID');
  }
  if (!timestamp(tx.purchaseDate) || !timestamp(tx.expiresDate) || !timestamp(tx.signedDate)
      || tx.expiresDate <= tx.purchaseDate || tx.purchaseDate > now + 300_000
      || tx.signedDate > now + 300_000 || tx.purchaseDate > tx.signedDate + 300_000) fail('INVALID_TRANSACTION_DATE');
  if (tx.revocationDate != null && (!timestamp(tx.revocationDate)
      || tx.revocationDate > now + 300_000)) fail('INVALID_REVOCATION');
  let eventDate = tx.signedDate;
  let graceEnd = null;
  if (notification) {
    if (!timestamp(notification.signedDate) || notification.signedDate > now + 300_000) fail('INVALID_NOTIFICATION_DATE');
    eventDate = Math.max(eventDate, notification.signedDate);
    if (['REFUND','REVOKE'].includes(notification.notificationType) && tx.revocationDate == null) fail('REVOCATION_REQUIRED');
    if (renewal) {
      if (renewal.environment !== environment || renewal.originalTransactionId !== tx.originalTransactionId
          || !cloudProducts.has(renewal.productId)
          || !timestamp(renewal.signedDate) || renewal.signedDate > now + 300_000) fail('RENEWAL_MISMATCH');
      if (renewal.gracePeriodExpiresDate != null && !['EXPIRED','GRACE_PERIOD_EXPIRED'].includes(notification.notificationType)) {
        if (!timestamp(renewal.gracePeriodExpiresDate)
            || renewal.gracePeriodExpiresDate < tx.expiresDate) fail('INVALID_GRACE_PERIOD');
        graceEnd = renewal.gracePeriodExpiresDate;
      }
      if (notification.notificationType === 'DID_FAIL_TO_RENEW' && notification.subtype === 'GRACE_PERIOD' && graceEnd == null) fail('RENEWAL_REQUIRED');
    } else if (notification.notificationType === 'DID_FAIL_TO_RENEW' && notification.subtype === 'GRACE_PERIOD') {
      fail('RENEWAL_REQUIRED');
    }
  }
  return Object.freeze({
    owner_id: ownerID.toLowerCase(), environment,
    transaction_id: tx.transactionId, original_transaction_id: tx.originalTransactionId,
    product_id: tx.productId, purchased_at: new Date(tx.purchaseDate).toISOString(),
    expires_at: new Date(tx.expiresDate).toISOString(), signed_at: new Date(eventDate).toISOString(),
    revoked_at: tx.revocationDate == null ? null : new Date(tx.revocationDate).toISOString(),
    upgraded: tx.isUpgraded === true, grace_expires_at: graceEnd == null ? null : new Date(graceEnd).toISOString(),
  });
}

export async function verifyPurchase({ signedTransaction, ownerID }, deps) {
  if (typeof signedTransaction !== 'string' || signedTransaction.length > 65536 || !signedTransaction) fail('INVALID_JWS');
  // Never decode a client payload as a substitute for cryptographic verification.
  const tx = await deps.verifier.verifyAndDecodeTransaction(signedTransaction);
  const event = normalizeTransaction(tx, { ownerID, environment: deps.environment, now: deps.now?.() });
  return await deps.persist(event);
}

export async function verifyNotification(signedPayload, deps) {
  if (typeof signedPayload !== 'string' || !signedPayload || signedPayload.length > 262144) fail('INVALID_JWS');
  const notification = await deps.verifier.verifyAndDecodeNotification(signedPayload);
  if (notification.notificationType === 'TEST') return { test: true };
  const data = notification.data;
  if (data?.bundleId !== bundleID || data.environment !== deps.environment || !data.signedTransactionInfo) fail('WRONG_APP_OR_ENVIRONMENT');
  const tx = await deps.verifier.verifyAndDecodeTransaction(data.signedTransactionInfo);
  const renewal = data.signedRenewalInfo ? await deps.verifier.verifyAndDecodeRenewalInfo(data.signedRenewalInfo) : undefined;
  const event = normalizeTransaction(tx, { ownerID: tx.appAccountToken, environment: deps.environment,
    now: deps.now?.(), notification, renewal });
  return await deps.persist(event);
}
