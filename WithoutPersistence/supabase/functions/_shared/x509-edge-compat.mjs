// Adapter for Edge runtimes missing four node:crypto X509 methods.
// Apple's SignedDataVerifier remains responsible for trust anchors, Apple marker
// OIDs, validity, JWS validation and online OCSP. No verification is skipped.
export function edgeCompatibleCertificate(Native, { Buffer, X509 }) {
  const rawBytes = new WeakMap();
  const parsed = new WeakMap();
  const unavailable = (error, member) => error?.code === 'ERR_NOT_IMPLEMENTED'
    && String(error.message).includes(`X509Certificate.prototype.${member}`);
  const parser = certificate => {
    if (!parsed.has(certificate)) {
      const value = new X509();
      value.readCertHex(rawBytes.get(certificate).toString('hex'));
      parsed.set(certificate, value);
    }
    return parsed.get(certificate);
  };
  return class EdgeCompatibleX509Certificate extends Native {
    constructor(input) {
      super(input); // Native parser still rejects malformed certificates.
      const bytes = typeof input === 'string' ? Buffer.from(input) : Buffer.from(input);
      const text = bytes.toString('ascii');
      const pem = /^-----BEGIN CERTIFICATE-----\s+([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----\s*$/.exec(text);
      rawBytes.set(this, pem ? Buffer.from(pem[1].replace(/\s/g, ''), 'base64') : Buffer.from(bytes));
    }
    get raw() {
      try { return super.raw; }
      catch (error) { if (!unavailable(error, 'raw')) throw error; return Buffer.from(rawBytes.get(this)); }
    }
    toString() {
      try { return super.toString(); }
      catch (error) {
        if (!unavailable(error, 'toString')) throw error;
        const base64 = rawBytes.get(this).toString('base64');
        return `-----BEGIN CERTIFICATE-----\n${base64.match(/.{1,64}/g).join('\n')}\n-----END CERTIFICATE-----\n`;
      }
    }
    verify(publicKey) {
      try { return super.verify(publicKey); }
      catch (error) {
        if (!unavailable(error, 'verify')) throw error;
        // jsrsasign is already used by Apple's official library. Verify the
        // complete certificate signature; never replace this with issuer names.
        const certificate = parser(this);
        const algorithm = certificate.getSignatureAlgorithmField();
        const keyType = publicKey.asymmetricKeyType;
        // Node returns false for a valid but incompatible issuer key. jsrsasign
        // throws a string instead (e.g. ECDSA certificate with an RSA root),
        // which would abort Apple's root search before the matching root.
        // Reject only known algorithm/key mismatches; never turn parser,
        // signature or unexpected runtime errors into a successful verification.
        const knownKey = ['rsa', 'rsa-pss', 'ec', 'dsa', 'ed25519', 'ed448'].includes(keyType);
        if (knownKey && /withECDSA$/.test(algorithm) && keyType !== 'ec') return false;
        if (knownKey && /withRSA(?:andMGF1)?$/.test(algorithm) && !['rsa', 'rsa-pss'].includes(keyType)) return false;
        return certificate.verifySignature(publicKey.export({ type: 'spki', format: 'pem' }));
      }
    }
    get infoAccess() {
      try { return super.infoAccess; }
      catch (error) {
        if (!unavailable(error, 'infoAccess')) throw error;
        const aia = parser(this).getExtAIAInfo();
        if (!aia) return undefined;
        return [...(aia.ocsp || []).map(uri => `OCSP - URI:${uri}`),
          ...(aia.caissuer || []).map(uri => `CA Issuers - URI:${uri}`)].join('\n');
      }
    }
  };
}
