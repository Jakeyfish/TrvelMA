import test from 'node:test';
import assert from 'node:assert/strict';
import crypto, { X509Certificate as Native } from 'node:crypto';
import { Buffer } from 'node:buffer';
import jsrsasign from 'jsrsasign';
import { readFileSync } from 'node:fs';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { edgeCompatibleCertificate } from '../functions/_shared/x509-edge-compat.mjs';
const fixtures = JSON.parse(readFileSync(new URL('./fixtures/apple-x509/certificates.json',import.meta.url)));
const bytes = name => Buffer.from(fixtures[name + '_BASE64_ENCODED'], 'base64');
const missing = member => { throw Object.assign(Error(`Not implemented: crypto.X509Certificate.prototype.${member}`),{code:'ERR_NOT_IMPLEMENTED'}); };
class EdgeNative extends Native {
  get raw() { return missing('raw'); }
  toString() { return missing('toString'); }
  verify() { return missing('verify'); }
  get infoAccess() { return missing('infoAccess'); }
}
const Compat = edgeCompatibleCertificate(EdgeNative,{Buffer,X509:jsrsasign.X509});
const deps = {Buffer,X509:jsrsasign.X509};
test('all missing Edge certificate APIs match native Node for Apple fixtures',()=>{
 for(const raw of Object.values(fixtures).filter(s=>s.startsWith('MII')).map(s=>Buffer.from(s,'base64'))) {
  const normal = new Native(raw), adapted = new Compat(raw);
  assert.deepEqual(adapted.raw,normal.raw);
  assert.equal(adapted.toString(),normal.toString());
  const lines = value => value?.trim().split('\n').sort();
  assert.deepEqual(lines(adapted.infoAccess),lines(normal.infoAccess));
 }
});
test('certificate signatures accept correct issuer and reject wrong issuer or tampering',()=>{
 const root=new Compat(bytes('ROOT_CA')), inter=new Compat(bytes('INTERMEDIATE_CA')), leaf=new Compat(bytes('LEAF_CERT'));
 assert.equal(inter.verify(root.publicKey),true); assert.equal(leaf.verify(inter.publicKey),true);
 assert.equal(leaf.verify(root.publicKey),false);
 const altered=Buffer.from(leaf.raw); altered[altered.length-1]^=1;
 assert.equal(new Compat(altered).verify(inter.publicKey),false);
 assert.equal(new Compat(leaf.toString()).verify(inter.publicKey),true);
});
test('official Apple verifier uses adapter and retains chain, OID and expiry rejection',async()=>{
 const original=crypto.X509Certificate; crypto.X509Certificate=Compat;
 try {
  const verifier=new SignedDataVerifier([bytes('ROOT_CA')],false,Environment.SANDBOX,'com.example',1234);
  const check=(leaf='LEAF_CERT',inter='INTERMEDIATE_CA',when=new Date('2026-11-05T12:00:00Z'))=>verifier.verifyCertificateChainWithoutCaching(verifier.rootCertificates,new Compat(bytes(leaf)),new Compat(bytes(inter)),when);
  await check();
  await assert.rejects(()=>check('LEAF_CERT_INVALID_OID'));
  await assert.rejects(()=>check('LEAF_CERT_FOR_INTERMEDIATE_CA_INVALID_OID','INTERMEDIATE_CA_INVALID_OID'));
  await assert.rejects(()=>check('LEAF_CERT','INTERMEDIATE_CA',new Date('2040-01-01')));
  const unrelated=new SignedDataVerifier([bytes('REAL_APPLE_ROOT')],false,Environment.SANDBOX,'com.example',1234);
  await assert.rejects(()=>unrelated.verifyCertificateChainWithoutCaching(unrelated.rootCertificates,new Compat(bytes('LEAF_CERT')),new Compat(bytes('INTERMEDIATE_CA')),new Date()));
 } finally { crypto.X509Certificate=original; }
});
test('supported native APIs are used; non-compatibility errors propagate',()=>{
 const Working=edgeCompatibleCertificate(Native,deps);const n=new Native(bytes('ROOT_CA')), w=new Working(n.raw);
 assert.equal(w.toString(),n.toString());assert.equal(w.verify(w.publicKey),n.verify(n.publicKey));
 class Broken extends Native { verify(){throw Error('verification failure');} }
 assert.throws(()=>new (edgeCompatibleCertificate(Broken,deps))(n.raw).verify(n.publicKey),/verification failure/);
 assert.throws(()=>new Compat(Buffer.from('invalid certificate')));
});

test('online checks still reject a chain without OCSP information',async()=>{
 const original=crypto.X509Certificate; crypto.X509Certificate=Compat;
 try {
  const verifier=new SignedDataVerifier([bytes('ROOT_CA')],true,Environment.SANDBOX,'com.example',1234);
  await assert.rejects(()=>verifier.verifyCertificateChainWithoutCaching(verifier.rootCertificates,
    new Compat(bytes('LEAF_CERT')),new Compat(bytes('INTERMEDIATE_CA')),new Date()));
 } finally { crypto.X509Certificate=original; }
});

test('full ES256 JWS passes forced Edge APIs; tampering, app and environment mismatches fail',async()=>{
 const {mkdtempSync,writeFileSync,rmSync}=await import('node:fs');
 const {tmpdir}=await import('node:os');const {join}=await import('node:path');
 const {execFileSync}=await import('node:child_process');
 const {verifyPurchase,bundleID}=await import('../functions/storekit-verify/core.mjs');
 const dir=mkdtempSync(join(tmpdir(),'trvelma-public-test-pki-'));
 const run=(...args)=>execFileSync('/usr/bin/openssl',args,{cwd:dir,stdio:'pipe'});
 const original=crypto.X509Certificate;crypto.X509Certificate=Compat;
 try {
  run('req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1','-pkeyopt','ec_param_enc:named_curve','-nodes','-keyout','root.key','-out','root.pem','-subj','/CN=Isolated Test Root','-days','1');
  for(const name of ['intermediate','leaf'])run('req','-new','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1','-pkeyopt','ec_param_enc:named_curve','-nodes','-keyout',name+'.key','-out',name+'.csr','-subj','/CN=Isolated Test '+name);
  writeFileSync(join(dir,'intermediate.ext'),'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n1.2.840.113635.100.6.2.1=DER:05:00\n');
  writeFileSync(join(dir,'leaf.ext'),'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n1.2.840.113635.100.6.11.1=DER:05:00\n');
  run('x509','-req','-in','intermediate.csr','-CA','root.pem','-CAkey','root.key','-set_serial','2','-days','1','-extfile','intermediate.ext','-out','intermediate.pem');
  run('x509','-req','-in','leaf.csr','-CA','intermediate.pem','-CAkey','intermediate.key','-set_serial','3','-days','1','-extfile','leaf.ext','-out','leaf.pem');
  const cert=name=>new Compat(readFileSync(join(dir,name+'.pem')));
  const root=cert('root'),inter=cert('intermediate'),leaf=cert('leaf');
  const verifier=new SignedDataVerifier([root.raw],false,Environment.SANDBOX,bundleID,6830031504);
  const now=Date.now(),owner='11111111-1111-4111-8111-111111111111';
  const payload={bundleId:bundleID,environment:'Sandbox',productId:bundleID+'.cloud.monthly',type:'Auto-Renewable Subscription',appAccountToken:owner,inAppOwnershipType:'PURCHASED',transactionId:'100',originalTransactionId:'100',purchaseDate:now-1000,expiresDate:now+86400000,signedDate:now};
  const header=Buffer.from(JSON.stringify({alg:'ES256',x5c:[leaf.raw,inter.raw,root.raw].map(b=>b.toString('base64'))})).toString('base64url');
  const sign=body=>{const input=header+'.'+Buffer.from(JSON.stringify(body)).toString('base64url');return input+'.'+crypto.sign('sha256',Buffer.from(input),{key:readFileSync(join(dir,'leaf.key')),dsaEncoding:'ieee-p1363'}).toString('base64url');};
  let writes=0;
  const deps={environment:'Sandbox',verifier,persist:async event=>{writes++;assert.equal(event.owner_id,owner);return {recorded:true};}};
  await verifier.verifyCertificateChainWithoutCaching(verifier.rootCertificates,leaf,inter,new Date());
  assert.deepEqual(await verifyPurchase({signedTransaction:sign(payload),ownerID:owner},deps),{recorded:true});
  const signed=sign(payload).split('.');signed[1]=Buffer.from(JSON.stringify({...payload,appAccountToken:'22222222-2222-4222-8222-222222222222'})).toString('base64url');
  await assert.rejects(()=>verifyPurchase({signedTransaction:signed.join('.'),ownerID:owner},deps));
  await assert.rejects(()=>verifyPurchase({signedTransaction:sign({...payload,bundleId:'wrong.app'}),ownerID:owner},deps));
  await assert.rejects(()=>verifyPurchase({signedTransaction:sign({...payload,environment:'Production'}),ownerID:owner},deps));
  assert.equal(writes,1,'Only the fully verified matching transaction can persist');
 } finally {crypto.X509Certificate=original;rmSync(dir,{recursive:true,force:true});}
});
