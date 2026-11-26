import test from 'node:test';
import assert from 'node:assert/strict';
import {flightDisplayTimes,parseFlights,makeFlightSnapshot,flightDisplayName,flightStatusLabel,lookupTripFlightCandidates} from '../parity.mjs';
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

test('LAX drop-off retries a same-date lookup when only the onward leg is returned', async () => {
 const onward = {departureAirport:'HGH',arrivalAirport:'TFU'};
 const first = {departureAirport:'LAX',arrivalAirport:'HGH',departureTime:'2026-11-29 21:30'};
 const through = {...first, arrivalAirport:'TFU'};
 const calls=[];
 const candidates=await lookupTripFlightCandidates(async airport=>{
  calls.push(airport);
  return airport.departureAirport ? [first,through,onward] : [onward];
 }, {service_type:'送机',location_end:'LAX Tom Bradley International Terminal'}, []);
 assert.deepEqual(calls,[{},{departureAirport:'LAX'}]);
 assert.deepEqual(candidates,[first,through]);
});

test('explicit pickup retries an empty result, but ordinary addresses stay unrestricted', async () => {
 const leg = {departureAirport:'LAX',arrivalAirport:'HGH'};
 const calls=[];
 const query=async airport=>{calls.push(airport);return airport.arrivalAirport?[leg]:[];};
 assert.deepEqual(await lookupTripFlightCandidates(query,{service_type:'接机',location_start:'HGH'},[]),[leg]);
 assert.deepEqual(calls,[{},{arrivalAirport:'HGH'}]);
 assert.deepEqual(await lookupTripFlightCandidates(async airport=>{assert.deepEqual(airport,{});return [leg];},
  {service_type:'送机',location_end:'123 Los Angeles Ave'},[]),[leg]);
});

test('provider single-quoted MCP response preserves every 3U3838 itinerary', async () => {
 const text = "Flight details: {'code': 200, 'data': [{'fcategory': '0', 'FlightDepcode': 'HGH', 'FlightArrcode': 'TFU', 'FlightState': '提前取消'}, {'fcategory': '1', 'FlightDepcode': 'LAX', 'FlightArrcode': 'TFU', 'FlightDeptimePlanDate': '2026-11-29 21:30:00', 'FlightArrtimePlanDate': '2026-12-01 08:10:00'}, {'fcategory': '1', 'FlightDepcode': 'LAX', 'FlightArrcode': 'HGH', 'FlightDeptimePlanDate': '2026-11-29 21:30:00', 'FlightArrtimePlanDate': '2026-12-01 04:10:00'}]}";
 const flights = parseFlights({result:{content:[{type:'text',text}]}});
 assert.equal(flights.length,3);
 const selected = await lookupTripFlightCandidates(async () => flights,{service_type:'送机',location_end:'LAX'},[]);
 assert.deepEqual(selected.map(f=>[f.departureAirport,f.arrivalAirport,f.estimatedArrivalTime]),[
  ['LAX','TFU','2026-12-01 08:10:00'],['LAX','HGH','2026-12-01 04:10:00']
 ]);
});

test('JX2 shows actual departure and estimated arrival while retaining the scheduled flight date', () => {
  const payload = {
    FlightDepcode: 'TPE', FlightArrcode: 'LAX',
    FlightDeptimePlanDate: '2026-11-25 23:40:00', FlightDeptimeDate: '2026-11-26 00:12:00',
    FlightArrtimePlanDate: '2026-11-25 19:05:00', FlightArrtimeReadyDate: '2026-11-25 18:58:00'
  };
  const text = '{' + Object.entries(payload).map(([key, value]) => "'" + key + "': '" + value + "'").join(', ') + '}';
  for (const response of [payload, text]) {
    const [flight] = parseFlights(response);
    assert.equal(flight.departureTime, '2026-11-25 23:40:00');
    assert.deepEqual(flightDisplayTimes(flight), {
      departure: ['2026-11-26 00:12:00', '实际起飞'],
      arrival: ['2026-11-25 18:58:00', '预计到达时间']
    });
  }
  const [planned] = parseFlights({FlightArrtimePlanDate: '19:05', FlightArrtimeReadyDate: '--'});
  assert.deepEqual(flightDisplayTimes(planned).arrival, ['19:05', '计划到达']);
});
