import test from 'node:test';
import assert from 'node:assert/strict';
import { purchaseHandler, notificationHandler } from '../functions/_shared/storekit-http.mjs';
import { bundleID } from '../functions/storekit-verify/core.mjs';

const owner = '11111111-1111-4111-8111-111111111111';
function fixture(overrides = {}) {
  const calls = { auth: 0, verify: 0, persist: 0 };
  const now = Date.now();
  const tx = {
    bundleId: bundleID, environment: 'Sandbox', productId: bundleID + '.cloud.monthly',
    type: 'Auto-Renewable Subscription', appAccountToken: owner, inAppOwnershipType: 'PURCHASED',
    transactionId: '100', originalTransactionId: '90', purchaseDate: now - 10000,
    expiresDate: now + 86400000, signedDate: now,
  };
  const deps = {
    environment: 'Sandbox', now: () => now,
    auth: { auth: { getUser: async token => {
      calls.auth++; assert.equal(token, 'fixture-token'); return { data: { user: { id: owner } }, error: null };
    } } },
    verifier: {
      verifyAndDecodeTransaction: async () => { calls.verify++; return tx; },
      verifyAndDecodeNotification: async () => { calls.verify++; return {
        notificationType: 'DID_RENEW', signedDate: now,
        data: { bundleId: bundleID, environment: 'Sandbox', signedTransactionInfo: 'nested-fixture' },
      }; },
    },
    persist: async event => { calls.persist++; assert.equal(event.owner_id, owner); return { recorded: true }; },
    ...overrides,
  };
  return { deps, calls };
}
function request(body, options = {}) {
  return new Request('https://example.invalid/storekit', {
    method: 'POST', headers: { authorization: 'Bearer fixture-token', ...options.headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
    ...options,
  });
}
const purchaseBody = { signedTransaction: 'signed-fixture' };
const notificationBody = { signedPayload: 'signed-fixture' };

test('purchase uses authenticated owner, ignoring caller-supplied owner', async () => {
  const { deps, calls } = fixture();
  const response = await purchaseHandler(() => deps)(request({ ...purchaseBody, ownerID: 'attacker', owner_id: 'attacker' }));
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), { recorded: true });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(calls.auth, 1); assert.equal(calls.persist, 1);
});

test('preflight does not initialize billing or authenticate', async () => {
  const response = await purchaseHandler(() => { throw Error('must not initialize'); })(new Request('https://example.invalid', { method: 'OPTIONS' }));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('access-control-allow-methods'), 'POST,OPTIONS');
});

for (const [label, factory] of [['purchase', purchaseHandler], ['notification', notificationHandler]]) {
  test(`${label} rejects unsupported methods before any verification`, async () => {
    const response = await factory(() => { throw Error('must not initialize'); })(new Request('https://example.invalid'));
    assert.equal(response.status, 405);
  });
  test(`${label} disabled deployment remains unavailable`, async () => {
    const response = await factory(() => { throw Error('BILLING_DISABLED'); })(request(label === 'purchase' ? purchaseBody : notificationBody));
    assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: 'BILLING_DISABLED' });
  });
  for (const body of ['{broken', 'null', '[]']) {
    test(`${label} rejects malformed/non-object JSON ${body}`, async () => {
      const { deps, calls } = fixture();
      const response = await factory(() => deps)(request(body));
      assert.equal(response.status, 400); assert.equal(calls.verify, 0); assert.equal(calls.persist, 0);
    });
  }
  test(`${label} transient persistence failure is retryable and never acknowledged as success`, async () => {
    const { deps } = fixture({ persist: async () => { throw Error('PERSISTENCE_FAILED'); } });
    const response = await factory(() => deps)(request(label === 'purchase' ? purchaseBody : notificationBody));
    assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: 'PERSISTENCE_FAILED' });
  });
  test(`${label} enforces streamed byte limit and cancels oversized body`, async () => {
    const { deps, calls } = fixture();
    let cancelled = false;
    const chunk = new Uint8Array(label === 'purchase' ? 40000 : 150000).fill(32);
    const body = new ReadableStream({ pull(controller) { controller.enqueue(chunk); }, cancel() { cancelled = true; } });
    const response = await factory(() => deps)(request(body, { body, duplex: 'half' }));
    assert.equal(response.status, 413); assert.equal(cancelled, true);
    assert.equal(calls.verify, 0); assert.equal(calls.persist, 0);
  });
}

for (const authorization of ['', 'Basic fixture-token', 'Bearer', 'Bearer a b']) {
  test(`purchase rejects missing/malformed Bearer header ${authorization}`, async () => {
    const response = await purchaseHandler(() => { throw Error('must not initialize'); })(request(purchaseBody, { headers: { authorization } }));
    assert.equal(response.status, 401);
  });
}
test('invalid session is rejected before signature verification', async () => {
  const { deps, calls } = fixture({ auth: { auth: { getUser: async () => ({ data: { user: null }, error: {} }) } } });
  const response = await purchaseHandler(() => deps)(request(purchaseBody));
  assert.equal(response.status, 401); assert.equal(calls.verify, 0); assert.equal(calls.persist, 0);
});
test('UTF-8 bytes, not character count, determine purchase body limit', async () => {
  const { deps, calls } = fixture();
  const body = JSON.stringify({ ...purchaseBody, padding: '旅'.repeat(24000) });
  assert.ok(body.length < 70000); assert.ok(new TextEncoder().encode(body).length > 70000);
  const response = await purchaseHandler(() => deps)(request(body));
  assert.equal(response.status, 413); assert.equal(calls.verify, 0);
});
test('declared oversized purchase request is rejected without verification', async () => {
  const { deps, calls } = fixture();
  const response = await purchaseHandler(() => deps)(request(purchaseBody, { headers: { authorization: 'Bearer fixture-token', 'content-length': '70001' } }));
  assert.equal(response.status, 413); assert.equal(calls.verify, 0);
});
test('purchase accepts valid JSON at exact byte boundary', async () => {
  const { deps } = fixture();
  const base = JSON.stringify({ ...purchaseBody, padding: '' });
  const body = JSON.stringify({ ...purchaseBody, padding: 'x'.repeat(70000 - base.length) });
  assert.equal(new TextEncoder().encode(body).length, 70000);
  assert.equal((await purchaseHandler(() => deps)(request(body))).status, 200);
});
for (const [label, factory, declared] of [['purchase', purchaseHandler, '70001'], ['notification', notificationHandler, '270001']]) {
  test(`${label} oversized response does not wait for stream cancellation to settle`, async () => {
    const { deps, calls } = fixture();
    let cancellationStarted = false;
    const body = new ReadableStream({ cancel() { cancellationStarted = true; return new Promise(() => {}); } });
    const req = request(body, { body, duplex: 'half', headers: { authorization: 'Bearer fixture-token', 'content-length': declared } });
    let timer;
    try {
      const response = await Promise.race([
        factory(() => deps)(req),
        new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Response blocked on cancellation')), 1000); }),
      ]);
      assert.equal(response.status, 413); assert.equal(cancellationStarted, true);
      assert.equal(calls.verify, 0); assert.equal(calls.persist, 0);
    } finally { clearTimeout(timer); }
  });
}
test('signature errors expose no raw transaction or credential details', async () => {
  const { deps, calls } = fixture({ verifier: { verifyAndDecodeTransaction: async () => { throw Error('private-transaction-and-token'); } } });
  const response = await purchaseHandler(() => deps)(request(purchaseBody));
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: 'PURCHASE_VERIFICATION_FAILED' });
  assert.equal(calls.persist, 0);
});
test('notification must verify nested transaction before acknowledgement', async () => {
  const { deps, calls } = fixture();
  deps.verifier.verifyAndDecodeTransaction = async () => { throw Error('bad nested signature'); };
  const response = await notificationHandler(() => deps)(request(notificationBody));
  assert.equal(response.status, 400); assert.equal(calls.persist, 0);
});
test('verified deleted-account notification is acknowledged, purchase is not recorded', async () => {
  const ignored = { recorded: false, ignored: 'ACCOUNT_DELETED' };
  const { deps } = fixture({ persist: async () => ignored });
  const response = await notificationHandler(() => deps)(request(notificationBody));
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), { received: true });
  const purchase = await purchaseHandler(() => deps)(request(purchaseBody));
  assert.deepEqual(await purchase.json(), ignored);
});

test('verification diagnostics categorize known key errors without logging transaction or arbitrary error text',async()=>{
 const original=console.warn,logs=[];console.warn=(...args)=>logs.push(args.join(' '));
 try {
  for(const message of ['"alg" parameter "ES256" requires curve "prime256v1".','secret-fixture-token raw-private-payload']) {
   const {deps}=fixture();deps.verifier.verifyAndDecodeTransaction=async()=>{throw Object.assign(Error(),{status:1,cause:Error(message)});};
   const response=await purchaseHandler(()=>deps)(request({signedTransaction:'signed-fixture-secret'}));
   assert.equal(response.status,400);
   assert.deepEqual(await response.json(),{error:'PURCHASE_VERIFICATION_FAILED'});
  }
  assert.ok(logs[0].includes('jwt-curve'));
  const output=logs.join('\n');assert.ok(!output.includes('signed-fixture-secret'));assert.ok(!output.includes('raw-private-payload'));assert.ok(!output.includes('secret-fixture-token'));
 } finally {console.warn=original;}
});
