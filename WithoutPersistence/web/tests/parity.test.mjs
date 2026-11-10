import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {recognizePickup,matchPickupAgency,pickupReminders,zonedISO,partsInZone,parseFlights,makeFlightSnapshot,readFlightSnapshot,routeMatches,compareTrips,settlementPayload,airportCodes} from '../parity.mjs';
const airports=JSON.parse(fs.readFileSync(new URL('../assets/airport-crosswalk.json',import.meta.url))).airports;
const raw=`订单号：C-1234567-US
接机日期：11/25  航班号：JX2，抵达机场：LAX
接机时间：预计19:00 到达
类型：接机
客人地址：QA Hotel 住址：928 E Colorado Blvd #101, Pasadena, CA 91106
联络人：QA GUEST（3人）
联络电话：886-900000001（台湾）
人数：3人，5件行李`;
const now=new Date('2026-10-26T18:00:00Z');
for (const [label,date,expected] of [['future','11/25','2026-11-25'],['past','10/25','2027-10-25'],['today','10/26','2026-10-26'],['explicit','2025/11/25','2025-11-25'],['trailing year','11/25/2028','2028-11-25']])test(`pickup date ${label}`,()=>assert.equal(recognizePickup(raw.replace('11/25',date),now).date,expected));
test('pickup guest, address unit, contact and LA ETA are preserved',()=>{const o=recognizePickup(raw,now);assert.equal(o.iso,'2026-11-26T03:00:00.000Z');assert.equal(o.contact,'QA GUEST');assert.equal(o.phone,'+886900000001');assert.equal(o.passengers,'3');assert.equal(o.luggage,'5');assert.match(o.destination,/#101/);assert.equal(o.reminders.length,2);});
for(const [label,replacement] of [['invalid date','02/30'],['invalid month','13/20']])test(label,()=>assert.throws(()=>recognizePickup(raw.replace('11/25',replacement),now)));
test('invalid arrival time is blocked',()=>assert.throws(()=>recognizePickup(raw.replace('19:00','25:00'),now)));
test('non LAX service is not guessed',()=>assert.throws(()=>recognizePickup(raw.replace('LAX','SFO'),now)));
test('agency exact aliases return stored code with spaces',()=>{const a={name:'途風旅遊 (Tours4Fun)',agency_code:'QA TF0001'};assert.equal(matchPickupAgency([a]).agency_code,'QA TF0001');});
test('duplicate aliases require manual choice',()=>assert.equal(matchPickupAgency([{name:'途风',agency_code:'1'},{name:'Tours4Fun',agency_code:'2'}]),null));
test('blank/deleted/non-exact agency must not match',()=>assert.equal(matchPickupAgency([{name:'途风',agency_code:'  '},{name:'途风',agency_code:'TF',deleted_at:'yes'},{name:'途风其他',agency_code:'OTHER'}]),null));
test('two near reminders remain distinct and future',()=>{const r=pickupReminders('2026-10-26T18:10:00Z',now);assert.equal(r.length,2);assert.notEqual(r[0],r[1]);assert.ok(r.every(t=>Date.parse(t)>+now&&Date.parse(t)<Date.parse('2026-10-26T18:10:00Z')));});
test('too-close pickup does not invent reminders',()=>assert.deepEqual(pickupReminders('2026-10-26T18:00:30Z',now),[]));
test('nonexistent DST local time is rejected',()=>assert.throws(()=>zonedISO('2027-03-14','02:30')));
test('LA conversion independent of host zone',()=>assert.equal(zonedISO('2026-11-25','19:00'),'2026-11-26T03:00:00.000Z'));
const first={FlightCompany:'QA Air',FlightDept:'TPE',FlightArr:'SFO',FlightDeptimePlanDate:'23:40',FlightArrtimePlanDate:'18:30',FlightHTerminal:'2',FlightTerminal:'I'};
const second={...first,FlightDept:'IAH',FlightArr:'LAX',FlightDeptimePlanDate:'16:30',FlightArrtimePlanDate:'18:07',FlightHTerminal:'C',FlightTerminal:'7'};
test('multi-leg records never flatten into a hybrid',()=>{const f=parseFlights({result:{structuredContent:{summary:{FlightDept:'TPE'},flights:[first,second]}}});assert.equal(f.length,2);assert.equal(f[1].departureAirport,'IAH');assert.equal(f[1].arrivalTerminal,'7');assert.equal(f[0].arrivalAirport,'SFO');});
test('provider departure and arrival terminal aliases stay separate',()=>{const [f]=parseFlights(first);assert.equal(f.departureTerminal,'2');assert.equal(f.arrivalTerminal,'I');});
test('numeric terminal accepted, boolean ignored',()=>{const [f]=parseFlights({...first,FlightHTerminal:2,FlightTerminal:true});assert.equal(f.departureTerminal,'2');assert.equal(f.arrivalTerminal,undefined);});
test('MCP text and duplicated legs are handled',()=>{const f=parseFlights({result:{content:[{type:'text',text:JSON.stringify([first,second,second])}]}});assert.equal(f.length,2);});
test('provider errors are not silently treated as flights',()=>assert.throws(()=>parseFlights({result:{isError:true,content:[]}})));
const selected=parseFlights(second)[0];const trip={flight_info:'UA1743',flight_date:'2026-10-24T07:00:00Z',service_type:'接机',location_start:'LAX Terminal 7'};
test('iOS-compatible format 2 snapshot reads without lookup',()=>{const snapshot=makeFlightSnapshot('UA1743','2026-10-24',selected,now);assert.equal(snapshot.fetchedAt,+now/1000-978307200);assert.equal(readFlightSnapshot({...trip,flight_selection_snapshot:snapshot},airports).arrivalTerminal,'7');});
test('old format/mismatched date/number cannot display stale snapshot',()=>{const snapshot=makeFlightSnapshot('UA1743','2026-10-24',selected);for(const patch of [{formatVersion:1},{flightDate:'2026-10-25'},{flightNumber:'UA2'}])assert.equal(readFlightSnapshot({...trip,flight_selection_snapshot:{...snapshot,...patch}},airports),null);});
test('wrong arrival route is rejected',()=>assert.equal(routeMatches(parseFlights(first)[0],trip,airports),false));
test('Chinese airport names crosswalk to IATA',()=>{assert.ok(airportCodes('洛杉矶机场',airports).has('LAX'));assert.ok(airportCodes('乔治布什',airports).has('IAH'));});
test('identical schedule sorts by whole creation second then stable id',()=>{const t={appointment_date:'2026-10-26T07:00Z',appointment_time:'2026-10-26T18:00Z'};const a={...t,id:'a',created_at:'2026-10-20T00:00:00.900Z'},b={...t,id:'b',created_at:'2026-10-20T00:00:00.100Z'};assert.ok(compareTrips(a,b)<0);assert.deepEqual([b,a].sort(compareTrips).map(x=>x.id),['a','b']);});
test('settlement payload contains only narrow financial fields',()=>{const body=settlementPayload({tripID:'qa',price:90,tip:0,expenses:[{id:'e',title:' QA Toll ',amount:2,is_addition:false}],location_start:'NEVER SEND'});assert.deepEqual(Object.keys(body).sort(),['p_expenses','p_fare','p_tip','p_trip_id']);assert.equal(body.p_expenses[0].title,'QA Toll');});
test('settlement rejects NaN, negative and empty expenses',()=>{for(const draft of [{price:NaN,tip:0,expenses:[]},{price:-1,tip:0,expenses:[]},{price:1,tip:0,expenses:[{title:' ',amount:2}]}])assert.throws(()=>settlementPayload(draft));});
test('arrival-only text terminal never populates departure terminal',()=>{const [f]=parseFlights('FlightDept: IAH\nFlightArr: LAX\nFlightArrTerminal: 7');assert.equal(f.arrivalTerminal,'7');assert.equal(f.departureTerminal,undefined);});
test('valid pickup survives a nonexistent previous-day reminder clock',()=>{const result=recognizePickup(raw.replace('11/25','2027/03/15').replace('19:00','02:30'),new Date('2027-03-10T00:00:00Z'));assert.equal(result.reminders.length,2);assert.ok(result.reminders.every(t=>Number.isFinite(Date.parse(t))));});
test('explicit airport mismatch is blocked even if crosswalk download fails',()=>assert.equal(routeMatches({arrivalAirport:'SFO'},{service_type:'接机',location_start:'LAX'},[]),false));
test('ordinary street address is not treated as its city airport',()=>assert.equal(routeMatches({arrivalAirport:'SFO'},{service_type:'接机',location_start:'123 Main St, Los Angeles, CA'},airports),true));

import {telephoneNumber, tripTelephoneContacts} from '../parity.mjs';
test('trip phone contacts use typed customer phone and never WeChat account',()=>{
 const trip={customer_id:'qa',customer_contact:'WeChat-QA'};
 const contacts=[{customer_id:'qa',contact_type:'微信',value:'12345678'},{customer_id:'qa',contact_type:'电话',value:'+1 (555) 000-0100'},{customer_id:'other',contact_type:'电话',value:'+15550000200'}];
 assert.deepEqual(tripTelephoneContacts(trip,contacts,['qa']),['+1 (555) 000-0100']);
 assert.equal(telephoneNumber('WeChat123456'),null);assert.equal(telephoneNumber('1+5550000100'),null);assert.equal(telephoneNumber('+1 (555) 000-0100'),'+15550000100');
 assert.deepEqual(tripTelephoneContacts({customer_contact:'886-953341193'},[],[]),['886-953341193']);
 assert.deepEqual(tripTelephoneContacts({customer_id:'qa',customer_contact:'+15550000100'},[],['qa']),[]);
});
