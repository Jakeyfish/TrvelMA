#!/usr/bin/env python3
"""Serve an isolated Web UI with in-memory QA records. All remote requests are blocked.
The actual Web renderers, submit handlers and domain rules are used; persistence/flight
transport are replaced in the temporary copy. No auth, live cloud or browser account data.
"""
from pathlib import Path
import shutil,tempfile,argparse,http.server,os
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--port',type=int,default=4187);parser.add_argument('--screen',choices=['home','contact','trips','finance','flight','detail','new-flight','copy-flight','expiry'],default='trips');args=parser.parse_args()
root=Path(__file__).resolve().parents[1]/'web';base=Path(tempfile.mkdtemp(prefix='trvelma-web-qa-'));shutil.copytree(root,base,dirs_exist_ok=True)
p=base/'app.js';s=p.read_text();index=s.rfind('initialize();');assert index>0
s=s[:index]+'''
const qaOwner='11111111-1111-4111-8111-111111111111';
const qaTrips=[];
const qaCustomer={id:'22222222-2222-4222-8222-222222222222',name:'QA Guest'};
const qaAgency={id:'33333333-3333-4333-8333-333333333333',name:'途风旅行',agency_code:'QA TF0001',contact_person:'QA Desk',phone:'0000000000'};
state.user={id:qaOwner,email:'qa@example.invalid',user_metadata:{salutation:'隔离 QA'}};
state.session={access_token:'QA-NOT-A-TOKEN',user:state.user};
state.productEdition='cloud';state.entitlementResolved=true;
state.settings={...defaultSettings(),owner_id:qaOwner};
state.customers=[qaCustomer];state.contacts=[];state.addresses=[];state.agencies=[qaAgency];
currentSession=async()=>state.session;
queryFlights=async()=>parseFlights({result:{flights:[
 {FlightCompany:'QA Air',FlightDept:'TPE',FlightArr:'SFO',FlightHTerminal:'2',FlightTerminal:'I',FlightDeptimePlanDate:'23:40',FlightArrtimePlanDate:'18:30'},
 {FlightCompany:'QA Air',FlightDept:'TPE',FlightArr:'LAX',FlightHTerminal:'2',FlightTerminal:'B',FlightDeptimePlanDate:'23:40',FlightArrtimePlanDate:'19:05'}
]}});
loadData=async()=>{state.trips=structuredClone(qaTrips);};
request=async(table,options={})=>{
 const {method='GET',body={},query={}}=options;
 if(table==='rpc/save_online_trip') {
  const i=qaTrips.findIndex(t=>t.id===body.p_trip.id),trip={...body.p_trip,stops:body.p_stops,expenses:body.p_expenses};
  if(i<0)qaTrips.push(trip);else qaTrips[i]=trip;
  return null;
 }
 if(['rpc/settle_online_trip','rpc/save_online_trip_finances'].includes(table)) {
  const t=qaTrips.find(t=>t.id===body.p_trip_id);if(!t)throw Error('QA trip missing');
  Object.assign(t,{price:body.p_fare,tip:body.p_tip,expenses:body.p_expenses});if(table==='rpc/settle_online_trip')t.is_paid=true;return null;
 }
 if(table==='trips') {
  const matches=qaTrips.filter(t=>Object.entries(query).every(([k,v])=>['select','order','limit'].includes(k)||v==='is.null'?!t[k]:v.startsWith('eq.')?String(t[k])===v.slice(3):true));
  if(method==='PATCH'){matches.forEach(t=>Object.assign(t,body));return structuredClone(matches);}
  return structuredClone(matches);
 }
 throw Error('QA blocked unsupported request: '+table);
};
await airportCrosswalkReady;
state.page='trips';renderApp();
document.body.insertAdjacentHTML('afterbegin','<aside style="position:fixed;bottom:0;left:0;z-index:9999;background:#fff3bc;padding:8px">隔离 QA · 内存数据 · 云端请求已阻断 · 刷新重置</aside>');
'''
if args.screen == 'home':
 s=s.replace("const qaTrips=[];", """const qaTrips=[0,1,2].map((i)=>({id:'qa-home-'+i,customer_name:['QA 陈女士','QA 林先生','QA 王先生'][i],appointment_date:new Date(Date.now()+86400000*(i+1)).toISOString(),appointment_time:new Date(Date.now()+86400000*(i+1)).toISOString(),service_type:i===1?'送机':'接机',location_start:i===1?'QA Pasadena Hotel':'LAX Terminal B',location_end:i===1?'LAX Terminal B':'QA Pasadena Hotel',price:[90,120,110][i],tip:0,is_paid:false,is_completed:false,stops:[],expenses:[],customer_count:3,customer_stuff:4}));""")
 s=s.replace("state.page='trips';renderApp();", "state.trips=structuredClone(qaTrips);state.page='home';renderApp();")
if args.screen == 'contact':
 s=s.replace("const qaTrips=[];", "const qaTrips=[{id:'44444444-4444-4444-8444-444444444444',customer_id:'22222222-2222-4222-8222-222222222222',customer_name:'QA Guest',customer_contact:'WeChat-QA',appointment_date:new Date().toISOString(),appointment_time:new Date().toISOString(),service_type:'接机',location_start:'QA Airport',location_end:'QA Hotel',price:90,tip:10,is_paid:true,is_completed:true,stops:[],expenses:[{title:'Extra',amount:5,is_addition:true},{title:'Parking',amount:8,is_addition:false}]}];")
 s=s.replace('state.contacts=[];', "state.contacts=[{id:'qa-phone',customer_id:qaCustomer.id,contact_type:'电话',value:'+1 (555) 000-0100',is_default:false},{id:'qa-wechat',customer_id:qaCustomer.id,contact_type:'微信',value:'WeChat-QA',is_default:true}];")
 s=s.replace("state.page='trips';renderApp();", "state.trips=structuredClone(qaTrips);state.page='trips';renderApp();")
if args.screen == 'finance':
 s=s.replace("const qaTrips=[];", "const qaTrips=[{id:'44444444-4444-4444-8444-444444444444',customer_name:'QA · 财务快照',appointment_date:new Date().toISOString(),appointment_time:new Date().toISOString(),service_type:'接机',location_start:'LAX',location_end:'Pasadena',price:90,tip:0,is_paid:true,is_completed:true,stops:[],expenses:[]}];")
 s=s.replace("state.page='trips';renderApp();", "state.trips=structuredClone(qaTrips);state.paymentMethods=[{id:'qa-payment',name:'QA 收款方式',qrImageData:null}];state.page='wallet';renderApp();")
if args.screen in ['flight','detail','new-flight','copy-flight']:
 s=s.replace("state.page='trips';renderApp();", """state.page='trips';renderApp();
 const qaFlightTrip={id:'44444444-4444-4444-8444-444444444444',customer_name:'QA Guest',customer_id:qaCustomer.id,appointment_date:'2026-11-25T19:00:00-08:00',appointment_time:'2026-11-25T19:00:00-08:00',flight_info:'JX2',flight_date:'2026-11-25',service_type:'接机',location_start:'LAX',location_end:'Pasadena',price:90,tip:0,stops:[],expenses:[],flight_selection_snapshot:makeFlightSnapshot('JX2','2026-11-25',{airlineName:'QA Air',departureAirport:'TPE',arrivalAirport:'LAX',departureTime:'23:40',estimatedArrivalTime:'19:00',departureTerminal:'2',arrivalTerminal:'B'})};
 state.trips=[qaFlightTrip];openTripForm(qaFlightTrip);""")
if args.screen == 'detail':
 s=s.replace('state.trips=[qaFlightTrip];openTripForm(qaFlightTrip);', "qaFlightTrip.order_source='旅行社订单';qaFlightTrip.travel_agency_name='QA 合作旅行社';qaFlightTrip.travel_agency_code='QA YH01';state.trips=[qaFlightTrip];openTripDetail(qaFlightTrip);")
if args.screen == 'copy-flight':
 s=s.replace('state.trips=[qaFlightTrip];openTripForm(qaFlightTrip);', "qaFlightTrip.tip=12;qaFlightTrip.is_paid=true;qaFlightTrip.is_completed=true;qaTrips.push(structuredClone(qaFlightTrip));state.trips=[qaFlightTrip];openTripForm(qaFlightTrip,true);")
if args.screen == 'new-flight':
 s=s.replace('state.trips=[qaFlightTrip];openTripForm(qaFlightTrip);', 'state.trips=[];openTripForm();')
if args.screen == 'expiry':
 s=s.replace("state.page='trips';renderApp();", """
let qaExpired=false;
ensureAccountDevice=async()=>{};
request=async(table)=>{
 if(table==='account_entitlements')return [{edition:'cloud',status:qaExpired?'expired':'active',expires_at:new Date(Date.now()+(qaExpired?-60000:86400000)).toISOString(),max_devices:4}];
 if(table==='rpc/read_expired_account_archive')return {read_only:true,trips:[],customers:[qaCustomer],travel_agencies:[]};
 throw Error('QA blocked unsupported request: '+table);
};
loadData=async()=>{state.customers=[qaCustomer];state.trips=[];};
state.page='customers';renderApp();
document.body.insertAdjacentHTML('afterbegin','<aside style="position:fixed;top:0;left:0;z-index:9999;background:#fff3bc;padding:8px"><button id="qa-expire">QA 模拟到期</button> <button id="qa-renew">QA 模拟恢复</button> <button id="qa-foreground">QA 模拟切回</button><span id="qa-phase">有效</span></aside>');
document.getElementById('qa-expire').addEventListener('click',()=>{qaExpired=true;document.getElementById('qa-phase').textContent='已模拟到期，请点正式刷新或切回页面';});
document.getElementById('qa-renew').addEventListener('click',()=>{qaExpired=false;document.getElementById('qa-phase').textContent='已模拟恢复，请点重新检查授权';});
document.getElementById('qa-foreground').addEventListener('click',()=>{void refreshOnForeground();});
""")
p.write_text(s)
index=base/'index.html';html=index.read_text().replace('<script type="module"', '''<script>const qaFetch=window.fetch.bind(window);window.fetch=(url,options)=>{const u=new URL(url,location.href);if(u.origin!==location.origin)return Promise.reject(Error('QA blocked remote request'));return qaFetch(url,options);};</script><script type="module"''');index.write_text(html)
print(f'QA root: {base}\nURL: http://localhost:{args.port}',flush=True)
os.chdir(base);http.server.ThreadingHTTPServer(('127.0.0.1',args.port),http.server.SimpleHTTPRequestHandler).serve_forever()
