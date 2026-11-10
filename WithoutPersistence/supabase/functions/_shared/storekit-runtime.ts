import { Buffer } from 'node:buffer';
import crypto from 'node:crypto';
import jsrsasign from 'npm:jsrsasign@11.1.5';
import { edgeCompatibleCertificate } from './x509-edge-compat.mjs';
import { Environment, SignedDataVerifier } from 'npm:@apple/app-store-server-library@3.1.0';
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { appleRootDERBase64 } from './apple-root-certificates.ts';
import { bundleID } from '../storekit-verify/core.mjs';

// Apple 3.1.0 uses the CommonJS crypto object; retain the official verifier
// and adapt only APIs whose native implementation explicitly throws.
crypto.X509Certificate = edgeCompatibleCertificate(crypto.X509Certificate, { Buffer, X509: jsrsasign.X509 }) as typeof crypto.X509Certificate;

export function context() {
 const env = Deno.env.get('STOREKIT_ENVIRONMENT');
 if (Deno.env.get('STOREKIT_ENABLED') !== 'true' || !['Production','Sandbox'].includes(env || '')) throw Error('BILLING_DISABLED');
 if (env === 'Production' && Deno.env.get('STOREKIT_PRODUCTION_ENABLED') !== 'true') throw Error('BILLING_DISABLED');
 const url=Deno.env.get('SUPABASE_URL'), pub=Deno.env.get('SUPABASE_ANON_KEY'), key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if (!url || !pub || !key) throw Error('BILLING_DISABLED');
 const environment=env as 'Production'|'Sandbox';
 const verifier=new SignedDataVerifier(appleRootDERBase64.map(value=>Buffer.from(value,'base64')),true,
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
