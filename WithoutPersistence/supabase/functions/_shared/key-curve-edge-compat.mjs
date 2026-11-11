// Old Deno exposes WebCrypto-style curve aliases to Node consumers. Normalize
// only the equivalent names; keep JWT algorithm checks and signature checks on.
export function installEdgeECKeyCurveAliases(sampleKey) {
 const aliases = { p256: 'prime256v1', p384: 'secp384r1', p521: 'secp521r1' };
 if (sampleKey.asymmetricKeyType !== 'ec' || !aliases[sampleKey.asymmetricKeyDetails?.namedCurve]) return null;
 let prototype = Object.getPrototypeOf(sampleKey);
 while (prototype) {
  const descriptor = Object.getOwnPropertyDescriptor(prototype, 'asymmetricKeyDetails');
  if (descriptor) {
   if (!descriptor.get || !descriptor.configurable) return null; // Fail closed via official verifier.
   Object.defineProperty(prototype, 'asymmetricKeyDetails', { ...descriptor, get() {
    const details = descriptor.get.call(this);
    if (this.asymmetricKeyType === 'ec' && aliases[details?.namedCurve]) {
     return { ...details, namedCurve: aliases[details.namedCurve] };
    }
    return details;
   } });
   return () => Object.defineProperty(prototype, 'asymmetricKeyDetails', descriptor);
  }
  prototype = Object.getPrototypeOf(prototype);
 }
 return null;
}
