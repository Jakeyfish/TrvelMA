import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {X509Certificate} from 'node:crypto';
import jsrsasign from 'jsrsasign';
import {certificateChainDiagnostic} from '../functions/_shared/storekit-chain-diagnostic.mjs';
const fixtures=JSON.parse(readFileSync(new URL('./fixtures/apple-x509/certificates.json',import.meta.url)));
const cert=name=>new X509Certificate(Buffer.from(fixtures[name+'_BASE64_ENCODED'],'base64'));
test('chain diagnostic distinguishes genuine chain predicates without exposing certificate data',()=>{
 const result=certificateChainDiagnostic([cert('ROOT_CA')],cert('LEAF_CERT'),cert('INTERMEDIATE_CA'),jsrsasign.X509);
 assert.deepEqual(result,{rootSignature:[true],rootIssuer:[true],leafSignature:true,leafIssuer:true,intermediateCA:true,leafMarker:true,intermediateMarker:true});
 const wrong=certificateChainDiagnostic([cert('REAL_APPLE_ROOT')],cert('LEAF_CERT_INVALID_OID'),cert('INTERMEDIATE_CA'),jsrsasign.X509);
 assert.deepEqual(wrong.rootSignature,[false]);assert.equal(wrong.leafMarker,false);
 assert.ok(!JSON.stringify(result).includes('CERTIFICATE'));
});
test('diagnostic failures are bounded categories and never escape as raw errors',()=>{
 const secret='secret-fixture-do-not-log';
 const broken=new Proxy({}, {get(){throw Error(secret)}});
 const result=certificateChainDiagnostic([broken],broken,broken,jsrsasign.X509);
 assert.ok(!JSON.stringify(result).includes(secret));
 assert.equal(result.leafSignature,'error');assert.deepEqual(result.rootSignature,['error']);
});
