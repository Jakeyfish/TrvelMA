import test from 'node:test';import assert from 'node:assert/strict';
import {installEdgeECKeyCurveAliases} from '../functions/_shared/key-curve-edge-compat.mjs';
class AliasKey { constructor(curve,type='ec'){this.curve=curve;this.asymmetricKeyType=type;}get asymmetricKeyDetails(){return {namedCurve:this.curve,other:'preserved'};} }
test('only equivalent EC aliases normalize, unknown curves and RSA metadata remain unchanged',()=>{
 const sample=new AliasKey('p256'),undo=installEdgeECKeyCurveAliases(sample);
 try {
  for(const [alias,expected] of [['p256','prime256v1'],['p384','secp384r1'],['p521','secp521r1'],['secp256k1','secp256k1'],['unknown','unknown']]) assert.equal(new AliasKey(alias).asymmetricKeyDetails.namedCurve,expected);
  assert.equal(new AliasKey('p256','rsa').asymmetricKeyDetails.namedCurve,'p256');
  assert.equal(sample.asymmetricKeyDetails.other,'preserved');
  assert.equal(installEdgeECKeyCurveAliases(sample),null);
 } finally {undo();}
 assert.equal(sample.asymmetricKeyDetails.namedCurve,'p256');
});
test('already compatible keys do not modify their prototypes',()=>{
 const descriptor=Object.getOwnPropertyDescriptor(AliasKey.prototype,'asymmetricKeyDetails');
 assert.equal(installEdgeECKeyCurveAliases(new AliasKey('prime256v1')),null);
 assert.deepEqual(Object.getOwnPropertyDescriptor(AliasKey.prototype,'asymmetricKeyDetails'),descriptor);
});
