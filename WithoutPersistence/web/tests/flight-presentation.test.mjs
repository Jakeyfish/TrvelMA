import test from 'node:test';
import assert from 'node:assert/strict';
import {parseFlights,makeFlightSnapshot,flightDisplayName,flightStatusLabel} from '../parity.mjs';
test('six languages use localized names and real status, never infer missing status',()=>{
 for(const lang of ['zh-Hans','zh-Hant','en','es','ja','ko']){
  assert.notEqual(flightDisplayName('LAX','airport',lang),'LAX');
  assert.notEqual(flightStatusLabel(null,lang),flightStatusLabel('计划',lang));
  assert.ok(flightStatusLabel('延误',lang));
 }
 assert.equal(flightDisplayName('Tokyo','airport','ja'),'Tokyo');
 assert.equal(flightDisplayName('Unknown airline','airline','en'),'Unknown airline');
 assert.equal(flightDisplayName('长荣航空股份有限公司','airline','en'),'EVA Air');
 assert.equal(flightStatusLabel('4','en'),'Status unavailable');
});
test('provider status survives JSON/text parsing and saved snapshots',()=>{
 for(const value of [{FlightArr:'LAX',FlightState:'延误'},'FlightArr: LAX, FlightState: 延误']){
  const result=parseFlights(value)[0];assert.equal(result.status,'延误');
  assert.equal(JSON.parse(JSON.stringify(makeFlightSnapshot('BR15','2026-11-12',result))).selected.status,'延误');
 }
 assert.equal(parseFlights({FlightArr:'LAX'})[0].status,undefined);
 assert.equal(flightStatusLabel('landed','en'),'Landed');
 assert.equal(flightStatusLabel('Unexpected provider label','en'),'Unexpected provider label');
});

test('App and Web share the same six-language identity and status dictionaries',async()=>{
 const {readFile}=await import('node:fs/promises');
 const swift=await readFile(new URL('../../Wishlist/Models/VariFlightClient.swift',import.meta.url),'utf8');
 const web=await readFile(new URL('../parity.mjs',import.meta.url),'utf8');
 const names=[...swift.matchAll(/\("(airport|airline)", (\[[^\n]*?\]), (\[[^\n]*?\])\)/g)].map(m=>[m[1],JSON.parse(m[2]),JSON.parse(m[3])]);
 const statuses=[...swift.slice(swift.indexOf('private static let statuses:'),swift.indexOf('static func name(_ raw:')).matchAll(/\((\["[^\n]*?\]), (\["[^\n]*?\])\)/g)].map(m=>[JSON.parse(m[1]),JSON.parse(m[2])]);
 assert.deepEqual(names,JSON.parse(web.match(/const flightNames = (.*);/)[1]));
 assert.deepEqual(statuses,JSON.parse(web.match(/const flightStatuses = (.*);/)[1]));
 for(const row of names)assert.equal(row[2].length,6);
 for(const row of statuses)assert.equal(row[1].length,6);
});
