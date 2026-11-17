import test from 'node:test';
import assert from 'node:assert/strict';
import {safeNavigationURL} from '../parity.mjs';

for (const provider of ['appleMaps','googleMaps']) {
 test(`${provider}: unverified address is searched exactly, never automatically routed`,()=>{
  const address='123 QA Greenwood Ave 圣加百利, CA, 美国 #2 & North';
  const url=new URL(safeNavigationURL(address,provider));
  assert.equal(url.searchParams.get(provider==='googleMaps'?'query':'q'),address);
  assert.equal(url.searchParams.has('destination'),false);assert.equal(url.searchParams.has('daddr'),false);
  if(provider==='googleMaps')assert.equal(url.pathname,'/maps/search/');
 });
 test(`${provider}: explicit coordinates route without a place-name lookup`,()=>{
  const url=new URL(safeNavigationURL('34.123456, -118.123456',provider));
  assert.equal(url.searchParams.get(provider==='googleMaps'?'destination':'daddr'),'34.123456,-118.123456');
  assert.equal(url.searchParams.get(provider==='googleMaps'?'travelmode':'dirflg'),provider==='googleMaps'?'driving':'d');
 });
}
test('blank destinations do not launch maps',()=>{assert.equal(safeNavigationURL(' \n '),null);});
test('invalid coordinates never authorize a route and north/south addresses stay distinct',()=>{
 for(const value of ['91,0','0,181','NaN,12','Infinity,4','34,,118']) {
  const url=new URL(safeNavigationURL(value,'googleMaps'));
  assert.equal(url.searchParams.has('destination'),false);
 }
 assert.notEqual(safeNavigationURL('123 N QA Ave','googleMaps'),safeNavigationURL('123 S QA Ave','googleMaps'));
});
