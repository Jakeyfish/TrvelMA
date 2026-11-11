// Failure-only, Sandbox diagnostics. Never returns certificate/JWS/account data.
export function certificateChainDiagnostic(roots, leaf, intermediate, X509) {
 const check = operation => { try { return operation() === true; } catch { return 'error'; } };
 const marker = (certificate, oid) => check(() => {
  const parsed = new X509(); parsed.readCertHex(certificate.raw.toString('hex'));
  return parsed.getExtInfo(oid) !== undefined;
 });
 return {
  rootSignature: roots.map(root => check(() => intermediate.verify(root.publicKey))),
  rootIssuer: roots.map(root => check(() => intermediate.issuer === root.subject)),
  leafSignature: check(() => leaf.verify(intermediate.publicKey)),
  leafIssuer: check(() => leaf.issuer === intermediate.subject),
  intermediateCA: check(() => intermediate.ca === true),
  leafMarker: marker(leaf, '1.2.840.113635.100.6.11.1'),
  intermediateMarker: marker(intermediate, '1.2.840.113635.100.6.2.1'),
 };
}
