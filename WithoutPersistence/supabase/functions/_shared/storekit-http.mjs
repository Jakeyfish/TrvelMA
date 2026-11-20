import { verifyPurchase, verifyNotification } from '../storekit-verify/core.mjs';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};
const reply = (status, body) => new Response(JSON.stringify(body), { status, headers });
class PayloadLimitError extends Error {}

async function readJSON(request, limit) {
  // Bound allocation by counting streamed bytes, not characters after reading.
  const declared = request.headers.get('content-length');
  if (declared && Number(declared) > limit) {
    // Edge runtimes may leave cancel pending until the connection closes.
    // Initiate cancellation, but do not block the rejection response on it.
    void request.body?.cancel().catch(() => {});
    throw new PayloadLimitError();
  }
  if (!request.body) throw Error('INVALID_BODY');
  const reader = request.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let size = 0, text = '';
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new PayloadLimitError();
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  } finally { reader.releaseLock(); }
  const body = JSON.parse(text);
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw Error('INVALID_BODY');
  return body;
}

function failure(error, fallback) {
  // Log only bounded error categories, never JWS, tokens, payloads or accounts.
  const diagnostic = {};
  if (error instanceof Error && /^[A-Z][A-Z0-9_]{1,63}$/.test(error.message)) diagnostic.code = error.message;
  if (Number.isInteger(error?.status)) diagnostic.verificationStatus = error.status;
  const cause = error?.cause;
  if (['JsonWebTokenError', 'TokenExpiredError', 'NotBeforeError', 'TypeError', 'Error'].includes(cause?.name)) diagnostic.causeType = cause.name;
  const causeMessage = typeof cause?.message === 'string' ? cause.message : '';
  const categories = [
    ['jwt-signature', /^invalid signature$/],
    ['jwt-algorithm', /^invalid algorithm$/],
    ['jwt-curve', /^"alg" parameter "ES(?:256|384|512)" requires curve /],
    ['jwt-key-material', /^secretOrPublicKey is not valid key material/],
    ['jwt-key-type', /^secretOrPublicKey must be an asymmetric key/],
    ['key-details', /Cannot read properties of undefined \(reading 'namedCurve'\)/],
  ];
  const causeCategory = categories.find(([, pattern]) => pattern.test(causeMessage));
  if (causeCategory) diagnostic.causeCategory = causeCategory[0];
  if (typeof error?.cause?.code === 'string' && /^[A-Z][A-Z0-9_]{1,63}$/.test(error.cause.code)) diagnostic.causeCode = error.cause.code;
  const missingFeature = /^Not implemented: ([A-Za-z0-9_. ]{1,120})/.exec(error?.cause?.message || '');
  if (missingFeature) diagnostic.missingFeature = missingFeature[1];
  console.warn('StoreKit request rejected', fallback, JSON.stringify(diagnostic));
  if (error instanceof PayloadLimitError) return reply(413, { error: 'PAYLOAD_TOO_LARGE' });
  const code = error instanceof Error ? error.message : '';
  if (['BILLING_DISABLED', 'PERSISTENCE_FAILED'].includes(code)) return reply(503, { error: code });
  return reply(400, { error: fallback });
}

export function purchaseHandler(context) {
  return async request => {
    if (request.method === 'OPTIONS') return new Response('ok', { headers });
    if (request.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
    const match = /^Bearer\s+(\S+)\s*$/i.exec(request.headers.get('authorization') || '');
    if (!match) return reply(401, { error: 'AUTH_REQUIRED' });
    try {
      const deps = context();
      const { data, error } = await deps.auth.auth.getUser(match[1]);
      if (error || !data?.user?.id) return reply(401, { error: 'AUTH_REQUIRED' });
      const body = await readJSON(request, 70000);
      const result = await verifyPurchase({ signedTransaction: body.signedTransaction, ownerID: data.user.id },
        deps.forPayload ? deps.forPayload(body.signedTransaction, false) : deps);
      return reply(200, result);
    } catch (error) { return failure(error, 'PURCHASE_VERIFICATION_FAILED'); }
  };
}

export function notificationHandler(context) {
  return async request => {
    if (request.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
    try {
      const deps = context();
      const body = await readJSON(request, 270000);
      await verifyNotification(body.signedPayload,
        deps.forPayload ? deps.forPayload(body.signedPayload, true) : deps);
      return reply(200, { received: true });
    } catch (error) { return failure(error, 'NOTIFICATION_VERIFICATION_FAILED'); }
  };
}
