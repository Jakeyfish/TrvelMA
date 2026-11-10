import test from 'node:test';
import assert from 'node:assert/strict';
import {SignedDataVerifier,Environment} from '@apple/app-store-server-library';
import {verifyPurchase,verifyNotification,normalizeTransaction,bundleID} from '../functions/storekit-verify/core.mjs';
const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222',now=Date.now();
const tx=(more={})=>({bundleId:bundleID,environment:'Sandbox',productId:bundleID+'.cloud.monthly',type:'Auto-Renewable Subscription',appAccountToken:owner,inAppOwnershipType:'PURCHASED',transactionId:'100',originalTransactionId:'90',purchaseDate:now-10000,expiresDate:now+86400000,signedDate:now-1000,...more});
const norm=t=>normalizeTransaction(t,{ownerID:owner,environment:'Sandbox',now});
test('verified cloud transaction normalizes exact owner and expiry',()=>{const e=norm(tx());assert.equal(e.owner_id,owner);assert.equal(e.expires_at,new Date(now+86400000).toISOString());});
for(const [name,more] of [['wrong owner',{appAccountToken:other}],['missing token',{appAccountToken:undefined}],['wrong app',{bundleId:'x'}],['wrong environment',{environment:'Production'}],['local cannot grant cloud',{productId:bundleID+'.local.lifetime'}],['family sharing denied',{inAppOwnershipType:'FAMILY_SHARED'}],['missing expiry',{expiresDate:undefined}],['expiry before purchase',{expiresDate:now-20000}],['future signed date',{signedDate:now+9999999}],['invalid transaction ID',{transactionId:'../../x'}]])test(name,()=>assert.throws(()=>norm(tx(more))));
test('failed signature never persists',async()=>{let writes=0;await assert.rejects(verifyPurchase({signedTransaction:'forged',ownerID:owner},{environment:'Sandbox',verifier:{verifyAndDecodeTransaction:async()=>{throw Error('bad')}},persist:async()=>writes++}));assert.equal(writes,0);});
test('official Apple library rejects unsigned transaction',async()=>{const v=new SignedDataVerifier([],true,Environment.SANDBOX,bundleID,6830031504);await assert.rejects(v.verifyAndDecodeTransaction('eyJhbGciOiJub25lIn0.eyJlbnZpcm9ubWVudCI6IlNhbmRib3gifQ.'));});
test('only verified payload is persisted',async()=>{let saved;await verifyPurchase({signedTransaction:'fixture',ownerID:owner,owner:other},{environment:'Sandbox',now:()=>now,verifier:{verifyAndDecodeTransaction:async()=>tx()},persist:async e=>{saved=e}});assert.equal(saved.owner_id,owner);});
const note=(more={})=>({notificationType:'DID_RENEW',signedDate:now,data:{bundleId:bundleID,environment:'Sandbox',signedTransactionInfo:'tx'},...more});
const deps=(n,t=tx(),r)=>({environment:'Sandbox',now:()=>now,persist:async e=>e,verifier:{verifyAndDecodeNotification:async()=>n,verifyAndDecodeTransaction:async()=>t,verifyAndDecodeRenewalInfo:async()=>r}});
test('notification nested signature and owner are required',async()=>{const e=await verifyNotification('signed',deps(note()));assert.equal(e.owner_id,owner);assert.equal(e.signed_at,new Date(now).toISOString());await assert.rejects(verifyNotification('signed',deps(note({data:{bundleId:bundleID,environment:'Production',signedTransactionInfo:'tx'}}))));});
test('grace is from signed renewal in same chain',async()=>{const r={environment:'Sandbox',originalTransactionId:'90',productId:bundleID+'.cloud.monthly',signedDate:now,gracePeriodExpiresDate:now+172800000},n=note({notificationType:'DID_FAIL_TO_RENEW',subtype:'GRACE_PERIOD'});n.data.signedRenewalInfo='r';const e=await verifyNotification('signed',deps(n,tx(),r));assert.equal(e.grace_expires_at,new Date(r.gracePeriodExpiresDate).toISOString());await assert.rejects(verifyNotification('signed',deps(n,tx(),{...r,originalTransactionId:'91'})));});
test('refund requires signed revocation',async()=>{await assert.rejects(verifyNotification('signed',deps(note({notificationType:'REFUND'}))));assert.equal((await verifyNotification('signed',deps(note({notificationType:'REFUND'}),tx({revocationDate:now})))).revoked_at,new Date(now).toISOString());});
test('cancel future renewal retains paid period',async()=>{assert.equal((await verifyNotification('signed',deps(note({notificationType:'DID_CHANGE_RENEWAL_STATUS',subtype:'AUTO_RENEW_DISABLED'})))).revoked_at,null);});
test('Apple TEST notification cannot grant',async()=>{let writes=0;const d=deps({notificationType:'TEST'});d.persist=async()=>writes++;assert.deepEqual(await verifyNotification('signed',d),{test:true});assert.equal(writes,0);});
test('future refund date cannot revoke current access',()=>{
 assert.throws(()=>norm(tx({revocationDate:now+9999999})),/INVALID_REVOCATION/);
});
test('deleted-account disposition is preserved for purchase and notification callers',async()=>{
 const disposition={recorded:false,ignored:'ACCOUNT_DELETED'},d=deps(note());
 d.persist=async()=>disposition;
 assert.deepEqual(await verifyPurchase({signedTransaction:'signed',ownerID:owner},d),disposition);
 assert.deepEqual(await verifyNotification('signed',d),disposition);
});
