import { Buffer } from 'node:buffer';
import crypto from 'node:crypto';
import jsrsasign from 'npm:jsrsasign@11.1.5';
import { installEdgeECKeyCurveAliases } from './key-curve-edge-compat.mjs';
import { certificateChainDiagnostic } from './storekit-chain-diagnostic.mjs';
import { edgeCompatibleCertificate } from './x509-edge-compat.mjs';
import { Environment, SignedDataVerifier } from 'npm:@apple/app-store-server-library@3.1.0';
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { appleRootDERBase64 } from './apple-root-certificates.ts';
import { bundleID } from '../storekit-verify/core.mjs';

// Apple 3.1.0 uses the CommonJS crypto object; retain the official verifier
// and adapt only APIs whose native implementation explicitly throws.
crypto.X509Certificate = edgeCompatibleCertificate(crypto.X509Certificate, { Buffer, X509: jsrsasign.X509 }) as typeof crypto.X509Certificate;
const curveProbe = appleRootDERBase64.map(value => new crypto.X509Certificate(Buffer.from(value, 'base64')).publicKey).find(key => key.asymmetricKeyType === 'ec');
if (curveProbe) installEdgeECKeyCurveAliases(curveProbe);

// Keep the official verifier authoritative; diagnostics cannot authorize a transaction.
class SandboxDiagnosticVerifier extends SignedDataVerifier {
 protected override async verifyCertificateChainWithoutCaching(
  roots: crypto.X509Certificate[], leaf: crypto.X509Certificate,
  intermediate: crypto.X509Certificate, effectiveDate: Date,
 ): Promise<crypto.KeyObject> {
  try { return await super.verifyCertificateChainWithoutCaching(roots, leaf, intermediate, effectiveDate); }
  catch (error) {
   console.warn('StoreKit sandbox chain diagnostic', JSON.stringify(certificateChainDiagnostic(roots, leaf, intermediate, jsrsasign.X509)));
   throw error;
  }
 }
}

export function context() {
 const env = Deno.env.get('STOREKIT_ENVIRONMENT');
 if (Deno.env.get('STOREKIT_ENABLED') !== 'true' || !['Production','Sandbox'].includes(env || '')) throw Error('BILLING_DISABLED');
 if (env === 'Production' && Deno.env.get('STOREKIT_PRODUCTION_ENABLED') !== 'true') throw Error('BILLING_DISABLED');
 const url=Deno.env.get('SUPABASE_URL'), pub=Deno.env.get('SUPABASE_ANON_KEY'), key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if (!url || !pub || !key) throw Error('BILLING_DISABLED');
 const environment=env as 'Production'|'Sandbox';
 const Verifier = environment === 'Sandbox' ? SandboxDiagnosticVerifier : SignedDataVerifier;
 const verifier=new Verifier(appleRootDERBase64.map(value=>Buffer.from(value,'base64')),true,
  environment === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX,bundleID,6830031504);
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const auth=createClient(url,pub,{auth:{persistSession:false,autoRefreshToken:false}});
 const sandboxOwners=new Set((Deno.env.get('STOREKIT_SANDBOX_OWNER_IDS')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean));
 return { environment, verifier, auth,
  persist:async (event: {owner_id:string})=>{
   // Sandbox must never grant general production accounts paid privileges.
   if(environment==='Sandbox' && !sandboxOwners.has(event.owner_id)) throw Error('SANDBOX_ACCOUNT_NOT_ALLOWED');
   const {data,error}=await admin.rpc('apply_verified_storekit_event',{p_event:event});
   if(error) { console.error('StoreKit persistence rejected',error.code); throw Error('PERSISTENCE_FAILED'); }
   return data;
  },
 };
}
