import crypto from 'node:crypto';
import { Buffer } from 'node:buffer';
import jsrsasign from 'npm:jsrsasign@11.1.5';
import { SignedDataVerifier, Environment } from 'npm:@apple/app-store-server-library@3.1.0';
import { edgeCompatibleCertificate } from '../functions/_shared/x509-edge-compat.mjs';
const Native=crypto.X509Certificate;
const missing=(member:string)=>{throw Object.assign(Error(`Not implemented: crypto.X509Certificate.prototype.${member}`),{code:'ERR_NOT_IMPLEMENTED'});};
class EdgeNative extends Native { get raw(){return missing('raw');} toString(){return missing('toString');} verify(){return missing('verify');} get infoAccess(){return missing('infoAccess');} }
crypto.X509Certificate=edgeCompatibleCertificate(EdgeNative,{Buffer,X509:jsrsasign.X509});
const f=JSON.parse(await Deno.readTextFile(new URL('./fixtures/apple-x509/certificates.json', import.meta.url)));
const root=new crypto.X509Certificate(Buffer.from(f.REAL_APPLE_ROOT_BASE64_ENCODED,'base64'));
const intermediate=new crypto.X509Certificate(Buffer.from(f.REAL_APPLE_INTERMEDIATE_BASE64_ENCODED,'base64'));
const verifier=new SignedDataVerifier([root.raw],true,Environment.SANDBOX,'com.example',1234);
await (verifier as any).checkOCSPStatus(intermediate,root);
console.log('APPLE_INTERMEDIATE_OCSP_VERIFIED_WITH_FORCED_EDGE_FALLBACK');
