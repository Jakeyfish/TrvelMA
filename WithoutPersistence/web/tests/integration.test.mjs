import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import * as parity from '../parity.mjs';
import {statementPDF} from '../statement-pdf.mjs';
import {localized} from '../localization.mjs';
const source=fs.readFileSync(new URL('../app.js',import.meta.url),'utf8').replace(/^import .*?;\n/gm,'').replace(/initialize\(\);\s*$/,'');
function boot(){
 const storage=new Map(),listeners={};
 class FormDataMock {constructor(form){this.values=form.values;}get(k){return this.values[k]??null;}*[Symbol.iterator](){yield*Object.entries(this.values);}}
 const c=vm.createContext({...parity,localized,statementPDF,FormData:FormDataMock,console,Date,Intl,URL,URLSearchParams,AbortController,Map,Set,structuredClone,crypto:webcrypto,Blob,Uint8Array,ArrayBuffer,TextEncoder,setTimeout:()=>0,clearTimeout:()=>{},atob,btoa,navigator:{onLine:true},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},window:{addEventListener:()=>{}},location:{hash:''},document:{documentElement:{lang:'zh-Hans'},visibilityState:'visible',addEventListener:(name,fn)=>{listeners[name]=fn;},getElementById:()=>null,querySelector:()=>null,querySelectorAll:()=>[],body:{insertAdjacentHTML:()=>{}}},fetch:async()=>({ok:true,json:async()=>({airports:[]})})});
 vm.runInContext(source,c);
 c.productionRenderApp=vm.runInContext("renderApp",c);
 vm.runInContext(`state.user={id:'owner'};state.productEdition='cloud';state.entitlementResolved=true;ensureAccountDevice=async()=>{};showToast=()=>{};renderApp=()=>{};loadData=async()=>{};`,c);
 c.listeners=listeners;
 return c;
}
test('actual offline settlement overlay changes only money/expenses and preserves route/stops',()=>{const c=boot();c.snapshot={trips:[{id:'t',owner_id:'owner',location_start:'LAX',is_completed:false}],stops:[{trip_id:'t',address:'Keep'}],expenses:[{trip_id:'t',id:'old'},{trip_id:'other',id:'keep'}]};vm.runInContext(`applyQueuedOperation(snapshot,{table:'rpc/settle_online_trip',owner_id:'owner',body:{p_trip_id:'t',p_fare:90,p_tip:0,p_expenses:[{id:'e',title:'Toll',amount:2}]}})`,c);assert.equal(c.snapshot.trips[0].price,90);assert.equal(c.snapshot.trips[0].location_start,'LAX');assert.equal(c.snapshot.trips[0].is_completed,false);assert.equal(c.snapshot.stops[0].address,'Keep');assert.equal(c.snapshot.expenses.length,2);assert.ok(c.snapshot.expenses.find(e=>e.id==='keep'));});
test('actual settlement submit uses one atomic narrow RPC and stable expense ids',async()=>{const c=boot();c.calls=[];vm.runInContext(`request=async(path,options)=>{calls.push({path,...options});};state.trips=[{id:'t',location_start:'Keep',stops:[]}];state.settlementDraft={tripID:'t',price:90,tip:0,expenses:[{id:'stable'}]};`,c);c.form={values:{price:'90',tip:'0',expense_addition_0:'false',expense_title_0:'Toll',expense_amount_0:'2'},querySelectorAll:()=>[{}]};await vm.runInContext('submitSettlement(form)',c);assert.equal(c.calls.length,1);assert.equal(c.calls[0].path,'rpc/settle_online_trip');assert.equal(c.calls[0].body.p_expenses[0].id,'stable');assert.equal(c.calls[0].body.p_fare,90);assert.equal(c.calls[0].queueOffline,false);});
test('sync settlement queues the same atomic operation, never multiple row writes',async()=>{const c=boot();c.calls=[];vm.runInContext(`state.productEdition='sync';request=async(path,options)=>{calls.push({path,...options});};state.trips=[{id:'t'}];state.settlementDraft={tripID:'t',price:0,tip:0,expenses:[]};`,c);c.form={values:{price:'0',tip:'0'},querySelectorAll:()=>[]};await vm.runInContext('submitSettlement(form)',c);assert.equal(c.calls.length,1);assert.equal(c.calls[0].queueOffline,true);});
test('actual settlement rejects nonfinite values before network',async()=>{const c=boot();c.calls=[];vm.runInContext(`request=async(...args)=>{calls.push(args);};state.trips=[{id:'t'}];state.settlementDraft={tripID:'t',expenses:[]};`,c);c.form={values:{price:'NaN',tip:'0'},querySelectorAll:()=>[]};await assert.rejects(vm.runInContext('submitSettlement(form)',c));assert.equal(c.calls.length,0);});
function tripForm(){return {dataset:{id:'stable-trip-id'},values:{service_type:'接机',order_source:'旅行社订单',travel_agency_code:'QA TF0001',travel_agency_name:'途风旅行',travel_agency_order_number:'C-1234567-US',customer_id:'',customer_name:'QA GUEST',customer_contact:'+886900000001',customer_count:'3',customer_stuff:'5',appointment_date:'2026-11-25',appointment_time:'19:00',location_start:'LAX',location_end:'QA Hotel',flight_info:'JX2',flight_date:'2026-11-25',flight_selection_snapshot:'null',flight_departure_time:'',flight_estimated_arrival_time:'19:00',flight_arrival_terminal:'',flight_baggage_carousel:'',memo:'QA',price:'90',tip:'0',is_paid:'false',reminder_date:'2026-11-24',reminder_time:'19:00',second_reminder_date:'2026-11-25',second_reminder_time:'17:00'},elements:{reminder_enabled:{checked:true},has_second_reminder:{checked:true}},querySelectorAll:()=>[]};}
test('actual smart draft save keeps order number, stable retry id and LA instants',async()=>{const c=boot();c.calls=[];c.form=tripForm();c.form.dataset.timeZone='America/Los_Angeles';vm.runInContext(`request=async(path,options)=>{calls.push({path,...options});};`,c);await vm.runInContext('submitTrip(form)',c);await vm.runInContext('submitTrip(form)',c);assert.equal(c.calls.length,2);const row=c.calls[0].body.p_trip;assert.equal(row.id,'stable-trip-id');assert.equal(c.calls[1].body.p_trip.id,row.id);assert.equal(row.travel_agency_order_number,'C-1234567-US');assert.equal(row.appointment_time,'2026-11-26T03:00:00.000Z');assert.equal(row.second_reminder_at,'2026-11-26T01:00:00.000Z');});
test('ordinary order clears agency-only number',async()=>{const c=boot();c.calls=[];c.form=tripForm();c.form.values.order_source='普通客户';vm.runInContext(`request=async(path,options)=>{calls.push({path,...options});};`,c);await vm.runInContext('submitTrip(form)',c);assert.equal(c.calls[0].body.p_trip.travel_agency_order_number,'');assert.equal(c.calls[0].body.p_trip.travel_agency_code,'');});
test('stale trip edit preserves draft and does not write',async()=>{const c=boot();c.form=tripForm();c.form.dataset.originalUpdatedAt='old';c.calls=[];vm.runInContext(`state.trips=[{id:'stable-trip-id',updated_at:'old'}];getRows=async()=>[{id:'stable-trip-id',updated_at:'new'}];request=async(...args)=>calls.push(args);`,c);await assert.rejects(vm.runInContext('submitTrip(form)',c),/其他设备更新/);assert.equal(c.calls.length,0);assert.equal(c.form.values.customer_name,'QA GUEST');});
test('saved card reads both terminals without network and escapes provider content',()=>{const c=boot();c.trip={flight_info:'JX2',flight_date:'2026-11-25T08:00Z',service_type:'接机',location_start:'LAX',flight_selection_snapshot:parity.makeFlightSnapshot('JX2','2026-11-25',{departureAirport:'TPE',arrivalAirport:'LAX',departureTerminal:'<img onerror=x>',arrivalTerminal:'B'})};const html=vm.runInContext('flightDetailsHTML(trip)',c);assert.match(html,/出发航站楼/);assert.match(html,/到达航站楼/);assert.ok(html.includes('&lt;img onerror=x&gt;'));assert.ok(!html.includes('<img onerror'));});
test('queued immutable image is restored by referenced path, not legacy filename assumptions',()=>{const c=boot();c.snapshot={settings:[{business_card_data:{portraitPath:'owner/business-card/portrait-digest.jpg',qrCodes:[]}}]};c.ops=[{kind:'storage-upload',owner_id:'owner',path:'object/account-assets/owner/business-card/portrait-digest.jpg',base64:'QA'}];vm.runInContext(`restoreQueuedStorageImages(snapshot,ops,'owner')`,c);assert.equal(c.snapshot.settings[0].business_card_data.portraitData,'QA');});
test('different image bytes get different immutable paths; unchanged bytes do not upload',async()=>{const c=boot();c.uploads=[];vm.runInContext(`imageAsJpeg=async text=>new Blob([text],{type:'image/jpeg'});storageRequest=async path=>{uploads.push(path);return {};};`,c);c.first={portraitData:'first',qrCodes:[]};const a=await vm.runInContext(`cloudAssetValue('business_card_data',first,'owner')`,c);c.second={portraitData:'second',portraitPath:a.portraitPath,qrCodes:[]};const b=await vm.runInContext(`cloudAssetValue('business_card_data',second,'owner')`,c);assert.notEqual(a.portraitPath,b.portraitPath);assert.match(a.portraitPath,/-[a-f0-9]{64}\.jpg$/);c.same={portraitData:'second',portraitPath:b.portraitPath,qrCodes:[]};await vm.runInContext(`cloudAssetValue('business_card_data',same,'owner')`,c);assert.equal(c.uploads.length,2);});
test('foreground refresh leaves unsaved modal intact',async()=>{const c=boot();c.resolveProductEdition=async()=>{};c.counts={load:0,render:0};vm.runInContext(`document.getElementById=()=>({});loadData=async()=>counts.load++;renderApp=()=>counts.render++;renderConnectionStatus=()=>{};`,c);await vm.runInContext('refreshOnForeground()',c);assert.equal(c.counts.load,1);assert.equal(c.counts.render,0);});
test('refresh checks expiry before normal reads or queued writes, preserving a paused draft',async()=>{
 const c=boot();c.calls=[];c.draft={dataset:{},hidden:false,inert:false,value:'Unsaved QA'};
 c.document.getElementById=id=>id==='modal-root'?c.draft:null;
 vm.runInContext(`resolveProductEdition=async()=>{calls.push('grant');state.archiveMode=true;};queuedOperationCount=()=>1;replayOfflineQueue=async()=>calls.push('write');loadData=async()=>calls.push('normal-read');renderExpiredArchive=()=>calls.push('readonly');loadExpiredArchive=async()=>calls.push('archive-read');`,c);
 assert.equal(await c.refreshAuthorizedWorkspace(),'archive');assert.deepEqual(c.calls,['grant','readonly','archive-read']);
 assert.equal(c.draft.hidden,true);assert.equal(c.draft.inert,true);assert.equal(c.draft.value,'Unsaved QA');
});
test('renewed grant resumes preserved draft without replacing it',async()=>{
 const c=boot();c.calls=[];c.draft={dataset:{entitlementPaused:'true'},hidden:true,inert:true,value:'Keep QA'};
 c.document.getElementById=id=>id==='modal-root'?c.draft:null;
 vm.runInContext(`state.archiveMode=true;resolveProductEdition=async()=>{state.archiveMode=false;};loadData=async()=>calls.push('normal-read');renderConnectionStatus=()=>calls.push('status');renderApp=()=>calls.push('replace-background');`,c);
 assert.equal(await c.refreshAuthorizedWorkspace(),'workspace');assert.equal(c.draft.hidden,false);assert.equal(c.draft.inert,false);
 assert.equal(c.draft.value,'Keep QA');assert.deepEqual(c.calls,['normal-read','replace-background']);
});
test('account change while checking expiry stops old workspace reads',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`resolveProductEdition=async()=>{state.user={id:'new-owner'};};loadData=async()=>calls.push('normal-read');loadExpiredArchive=async()=>calls.push('archive-read');`,c);
 assert.equal(await c.refreshAuthorizedWorkspace(),undefined);assert.deepEqual(c.calls,[]);
});
test('all address navigation buttons launch the selected field without reusing another destination',async()=>{
 const c=boot();c.opened=[];c.window.open=url=>c.opened.push(url);c.getAccountPreference=()=> 'googleMaps';
 const form={elements:{location_start:{value:'123 N QA Ave'},location_end:{value:'456 S QA Blvd'}},querySelector:()=>({value:'34.123456,-118.123456'})};
 for(const [target,expected] of [['start','123 N QA Ave'],['end','456 S QA Blvd'],['stop:0','34.123456,-118.123456']]){
  const button={dataset:{action:'navigate-address',target},closest:()=>form};
  await c.listeners.click({target:{closest:s=>s==='[data-action]'?button:null}});
  const url=new URL(c.opened.at(-1));
  assert.equal(url.searchParams.get(target==='stop:0'?'destination':'query'),expected);
  assert.equal(url.pathname,target==='stop:0'?'/maps/dir/':'/maps/search/');
 }
 const button={dataset:{action:'navigate-saved-address',address:'789 QA Hotel & Conference'}};
 await c.listeners.click({target:{closest:s=>s==='[data-action]'?button:null}});
 assert.equal(new URL(c.opened.at(-1)).searchParams.get('query'),'789 QA Hotel & Conference');
 assert.equal(c.opened.length,4);
});
test('narrow completion and restore patches never include financial or route fields',async()=>{const c=boot();c.calls=[];vm.runInContext(`patch=async(table,query,body)=>calls.push({table,query,body});`,c);await vm.runInContext(`markTrip('t',{is_completed:true,is_cancelled:false})`,c);await vm.runInContext(`markTrip('t',{is_completed:false,is_cancelled:false})`,c);assert.equal(c.calls.length,2);for(const call of c.calls){assert.equal(call.table,'trips');assert.equal(Object.hasOwn(call.body,'price'),false);assert.equal(Object.hasOwn(call.body,'location_start'),false);assert.equal(Object.hasOwn(call.body,'is_paid'),false);}assert.equal(c.calls[1].body.is_completed,false);});
test('late image download cannot overwrite an image selected locally',async()=>{const c=boot();let release;c.response=()=>new Promise(r=>{release=r;});vm.runInContext(`state.businessCard={portraitPath:'owner/business-card/portrait.jpg',qrCodes:[]};storageRequest=async()=>({arrayBuffer:response});`,c);const task=vm.runInContext('hydrateAccountAssets()',c);await new Promise(r=>setImmediate(r));vm.runInContext(`state.businessCard.portraitData='NEW-LOCAL';`,c);release(new TextEncoder().encode('OLD-CLOUD').buffer);await task;assert.equal(vm.runInContext('state.businessCard.portraitData',c),'NEW-LOCAL');});
test('late account image read cannot write into a newly selected account',async()=>{const c=boot();let release;c.read=()=>new Promise(r=>{release=r;});c.saves=[];vm.runInContext(`readImageBase64=read;saveBusinessCard=async()=>saves.push('save');`,c);const task=vm.runInContext(`setCardPhoto({})`,c);vm.runInContext(`state.user={id:'other'};state.businessCard={nickname:'Other',qrCodes:[]};`,c);release('OLD-ACCOUNT');await task;assert.equal(vm.runInContext('state.businessCard.portraitData',c),undefined);assert.equal(c.saves.length,0);});
test('newest image choice wins when file reads complete out of order',async()=>{const c=boot();const readers=[];c.read=()=>new Promise(r=>readers.push(r));c.saves=[];vm.runInContext(`readImageBase64=read;saveBusinessCard=async()=>saves.push(state.businessCard.portraitData);updatePageContent=()=>{};`,c);const first=vm.runInContext('setCardPhoto({})',c),second=vm.runInContext('setCardPhoto({})',c);readers[1]('NEW');await second;readers[0]('OLD');await first;assert.equal(vm.runInContext('state.businessCard.portraitData',c),'NEW');assert.deepEqual(c.saves,['NEW']);});
function pendingSnapshot(c){const waits=[];c.getSnapshotRows=table=>new Promise(resolve=>waits.push({table,resolve}));vm.runInContext(`getRows=getSnapshotRows;hydrateAccountAssets=async()=>{};scheduleWebReminders=()=>{};`,c);return waits;}
test('same-account logout/login invalidates an earlier load',async()=>{const c=boot();vm.runInContext(source.slice(source.indexOf('async function loadData()'),source.indexOf('async function resolveProductEdition')),c);const waits=pendingSnapshot(c);const task=vm.runInContext('loadData()',c);vm.runInContext(`resetAccountWorkspace();state.user={id:'owner'};state.trips=[{id:'new-session'}];`,c);for(const {table,resolve}of waits)resolve(table==='trips'?[{id:'old-session'}]:[]);await task;assert.equal(vm.runInContext('state.trips[0].id',c),'new-session');});
test('slower load cannot replace a newer completed refresh',async()=>{const c=boot();vm.runInContext(source.slice(source.indexOf('async function loadData()'),source.indexOf('async function resolveProductEdition')),c);const waits=pendingSnapshot(c);const old=vm.runInContext('loadData()',c);vm.runInContext(`getRows=async table=>table==='trips'?[{id:'newer'}]:[];`,c);await vm.runInContext('loadData()',c);for(const {table,resolve}of waits)resolve(table==='trips'?[{id:'older'}]:[]);await old;assert.equal(vm.runInContext('state.trips[0].id',c),'newer');});
test('network failure after session reset cannot enqueue a stale mutation',async()=>{const c=boot();let reject;c.response=()=>new Promise((_,r)=>{reject=r;});c.queued=[];vm.runInContext(`currentSession=async()=>({user:{id:'owner'},access_token:'QA'});fetch=response;persistOfflineOperation=(...args)=>queued.push(args);state.productEdition='sync';`,c);const task=vm.runInContext(`request('trips',{method:'PATCH',query:{id:'eq.t'},body:{is_completed:true}})`,c);await new Promise(r=>setImmediate(r));vm.runInContext(`resetAccountWorkspace();state.user={id:'owner'};`,c);reject(new TypeError('offline'));await assert.rejects(task,/会话已变化/);assert.equal(c.queued.length,0);});
test('network timeout aborts the transport and is recoverable as offline',async()=>{const c=boot();c.setTimeout=setTimeout;c.clearTimeout=clearTimeout;c.makeFailure=()=>Object.assign(new Error('timed out'),{name:'AbortError'});vm.runInContext(`fetch=(url,options)=>new Promise((_,reject)=>options.signal.addEventListener('abort',()=>reject(makeFailure())));`,c);await assert.rejects(vm.runInContext(`networkFetch('https://qa.example.invalid',{},5)`,c),/timed out/);assert.equal(vm.runInContext(`isNetworkFailure({name:'AbortError'})`,c),true);});
test('account reset also removes old account drafts and picker DOM',()=>{const c=boot();c.removed=[];vm.runInContext(`document.getElementById=id=>({remove:()=>removed.push(id)});resetAccountWorkspace();`,c);assert.deepEqual(c.removed,['modal-root','picker-backdrop']);});
test('legacy fixed-path image queue upgrades each chronological reference independently',async()=>{const c=boot();c.envelope={operations:[{id:'u1',owner_id:'owner',kind:'storage-upload',path:'object/account-assets/owner/business-card/portrait.jpg',base64:btoa('first')},{id:'s1',owner_id:'owner',table:'user_settings',method:'POST',body:{business_card_data:{portraitPath:'owner/business-card/portrait.jpg'}}},{id:'u2',owner_id:'owner',kind:'storage-upload',path:'object/account-assets/owner/business-card/portrait.jpg',base64:btoa('second')},{id:'s2',owner_id:'owner',table:'user_settings',method:'POST',body:{business_card_data:{portraitPath:'owner/business-card/portrait.jpg'}}}]};vm.runInContext(`localStorage.setItem(offlineQueueKey('owner'),JSON.stringify(envelope));`,c);await vm.runInContext(`upgradeOfflineAssetQueue('owner')`,c);const ops=vm.runInContext(`readOfflineQueue('owner').operations`,c);const first=ops[0].path.replace('object/account-assets/',''),second=ops[2].path.replace('object/account-assets/','');assert.notEqual(first,second);assert.equal(ops[1].body.business_card_data.portraitPath,first);assert.equal(ops[3].body.business_card_data.portraitPath,second);assert.equal(ops[0].id,'u1');});
test('legacy queue owner mismatch fails without changing persisted queue',async()=>{const c=boot();c.envelope={operations:[{id:'x',owner_id:'other',kind:'storage-upload',path:'object/account-assets/other/portrait.jpg',base64:btoa('image')}]};vm.runInContext(`localStorage.setItem(offlineQueueKey('owner'),JSON.stringify(envelope));`,c);await assert.rejects(vm.runInContext(`upgradeOfflineAssetQueue('owner')`,c),/账号标记异常/);assert.equal(vm.runInContext(`readOfflineQueue('owner').operations[0].path`,c),'object/account-assets/other/portrait.jpg');});
function restoreAdmission(c){vm.runInContext(source.slice(source.indexOf('async function ensureAccountDevice()'),source.indexOf('let workspaceGeneration = 0;')),c);}
test('browser device identity persists across account resets',()=>{const c=boot();const first=vm.runInContext('accountDeviceID()',c);vm.runInContext('resetAccountWorkspace();state.user={id:"owner"};',c);assert.equal(vm.runInContext('accountDeviceID()',c),first);});
test('parallel business loads coalesce device registration and registration does not invalidate snapshot sequence',async()=>{const c=boot();restoreAdmission(c);c.calls=[];let release;c.register=()=>new Promise(r=>{release=r;});vm.runInContext(`request=async(path,options)=>{calls.push({path,...options});await register();};loadSequence=4;`,c);const a=vm.runInContext('ensureAccountDevice()',c),b=vm.runInContext('ensureAccountDevice()',c);assert.equal(c.calls.length,1);release({active_devices:1,max_devices:4});await Promise.all([a,b]);await vm.runInContext('ensureAccountDevice()',c);assert.equal(c.calls.length,1);assert.equal(c.calls[0].body.p_device_type,'Web');assert.equal(c.calls[0].queueOffline,false);assert.equal(vm.runInContext('loadSequence',c),4);});
test('device limit failure is visible and is never treated as empty data or admitted',async()=>{const c=boot();restoreAdmission(c);c.calls=[];vm.runInContext(`request=async(path)=>{calls.push(path);throw Error('ACCOUNT_DEVICE_LIMIT_REACHED');};`,c);await assert.rejects(vm.runInContext('ensureAccountDevice()',c),/ACCOUNT_DEVICE_LIMIT_REACHED/);assert.equal(vm.runInContext('deviceAdmission',c),null);assert.match(vm.runInContext(`friendlyError({message:'ACCOUNT_DEVICE_LIMIT_REACHED'})`,c),/设备名额已满/);});
test('REST and private Storage requests carry the same persistent device header',async()=>{const c=boot();c.calls=[];vm.runInContext(`currentSession=async()=>({user:{id:'owner'},access_token:'QA'});fetch=async(url,options)=>{calls.push({url:String(url),options});return {ok:true,text:async()=>'[]'};};`,c);await vm.runInContext(`request('trips')`,c);await vm.runInContext(`storageRequest('object/authenticated/account-assets/owner/test.jpg')`,c);assert.equal(c.calls.length,2);const id=vm.runInContext('accountDeviceID()',c);assert.equal(c.calls[0].options.headers['x-account-device-id'],id);assert.equal(c.calls[1].options.headers['x-account-device-id'],id);});
test('late registration cannot admit a new session of the same account',async()=>{const c=boot();restoreAdmission(c);let release;c.register=()=>new Promise(r=>{release=r;});vm.runInContext(`request=register;`,c);const task=vm.runInContext('ensureAccountDevice()',c);vm.runInContext(`resetAccountWorkspace();state.user={id:'owner'};`,c);release({});await assert.rejects(task,/会话已变化/);assert.equal(vm.runInContext('deviceAdmission',c),null);});

test('finance snapshots use selected date range, exclude cancelled rows and sort deterministically',()=>{
 const c=boot();vm.runInContext(`showModal=(title,html)=>{globalThis.snapshotHTML=html;};state.trips=[
 {id:'b',appointment_date:'2026-10-27T12:00:00Z',appointment_time:'2026-10-27T08:00:00Z',customer_name:'Second',price:0},
 {id:'a',appointment_date:'2026-10-27T12:00:00Z',appointment_time:'2026-10-27T08:00:00Z',customer_name:'First',price:90},
 {id:'c',appointment_date:'2026-10-28T00:00:00Z',customer_name:'Outside'},
 {id:'d',appointment_date:'2026-10-27T12:00:00Z',is_cancelled:true,customer_name:'Cancelled'}];
 openFinanceSnapshots('2026-10-27T00:00:00Z','2026-10-28T00:00:00Z');`,c);
 const html=c.snapshotHTML;assert.ok(html.indexOf('First')<html.indexOf('Second'));assert.doesNotMatch(html,/Outside|Cancelled/);assert.equal((html.match(/<details class="finance-trip-snapshot">/g)||[]).length,2);assert.match(html,/\$0\.00/);
});
test('finance snapshot summaries contain only date/time guest and fare; expanded content is escaped and read-only',()=>{
 const c=boot();vm.runInContext(`showModal=(title,html)=>{globalThis.snapshotHTML=html;};state.trips=[{id:'a',appointment_date:'2026-10-27T12:00:00Z',appointment_time:'2026-10-27T08:00:00Z',customer_name:'<img src=x onerror=bad()>',price:90,location_start:'Private start',memo:'<script>bad()</script>',expenses:[]}];openFinanceSnapshots('2026-10-27','2026-10-28');`,c);
 const html=c.snapshotHTML,summary=html.match(/<summary>(.*?)<\/summary>/s)[1];assert.doesNotMatch(summary,/Private start|script|行程状态/);assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>|data-action="(?:edit|delete|toggle|refresh)/);assert.match(html,/>关闭<\/button>/);
});
test('empty finance snapshots remain dismissible and do not write to backend',()=>{
 const c=boot();c.calls=[];vm.runInContext(`request=(...args)=>calls.push(args);showModal=(title,html)=>{globalThis.snapshotHTML=html;};state.trips=[];openFinanceSnapshots('2026-10-27','2026-10-28');`,c);assert.equal(c.calls.length,0);assert.match(c.snapshotHTML,/所选日期内没有行程/);assert.match(c.snapshotHTML,/close-modal/);
});

test('finance cards reuse trip-list presentation without editing, navigation or flight refresh controls',()=>{
 const c=boot();c.trip={id:'t',customer_name:'QA',appointment_date:'2026-10-27',appointment_time:'2026-10-27T08:00:00Z',price:90,tip:0,flight_info:'UA1743',stops:[],expenses:[]};
 const html=vm.runInContext('renderTripCard(trip,{readOnly:true})',c);assert.match(html,/trip-card trip-card-full/);assert.match(html,/trip-route-full/);assert.match(html,/trip-status-row/);assert.doesNotMatch(html,/data-action=/);
});
test('finance record animation completes and rapid reversal keeps the requested final state',()=>{
 const c=boot();c.animations=[];
 c.window.getComputedStyle=()=>({paddingTop:'10',paddingBottom:'10',borderTopWidth:'1',borderBottomWidth:'1'});
 c.details={open:false,style:{overflow:''},querySelector:()=>({getBoundingClientRect:()=>({height:40})}),getBoundingClientRect:()=>({height:c.details.open?300:62}),animate:(frames,options)=>{const a={frames,options,cancel(){this.cancelled=true;}};c.animations.push(a);return a;}};
 vm.runInContext('toggleFinanceRecord(details)',c);assert.equal(c.animations[0].options.duration,440);assert.equal(c.details.open,true);
 vm.runInContext('toggleFinanceRecord(details)',c);assert.equal(c.animations[0].cancelled,true);c.animations[0].onfinish();assert.equal(c.details.open,true);c.animations[1].onfinish();assert.equal(c.details.open,false);assert.equal(c.details.style.overflow,'');
});
test('finance record respects reduced motion without measuring or animating',()=>{
 const c=boot();c.window.matchMedia=()=>({matches:true});c.details={open:false};vm.runInContext('toggleFinanceRecord(details)',c);assert.equal(c.details.open,true);vm.runInContext('toggleFinanceRecord(details)',c);assert.equal(c.details.open,false);
});
test('normal trip list cards keep their existing actions when used as Array.map callback',()=>{
 const c=boot();c.trips=[{id:'t',appointment_date:'2026-10-27',appointment_time:'2026-10-27T08:00:00Z',price:90,tip:0,stops:[],expenses:[]}];
 const html=vm.runInContext('trips.map(renderTripCard).join("")',c);assert.match(html,/data-action="view-trip"/);assert.match(html,/data-action="edit-trip"/);assert.match(html,/data-action="toggle-paid"/);
});

test('App-style finance layout preserves fare/tip/addition/expense totals within the selected date',()=>{
 const c=boot();vm.runInContext(`location.hash='period=day&anchor=2026-10-27';renderPaymentMethods=()=>'';state.trips=[{id:'t',appointment_date:new Date(2026,9,27,12).toISOString(),price:90,tip:10,expenses:[{title:'Extra',amount:5,is_addition:true},{title:'Toll',amount:7,is_addition:false}]},{id:'outside',appointment_date:new Date(2026,9,28,12).toISOString(),price:999},{id:'cancelled',is_cancelled:true,appointment_date:new Date(2026,9,27,12).toISOString(),price:999}];`,c);
 const html=vm.runInContext('renderWallet()',c);assert.match(html,/finance-summary/);assert.match(html,/finance-category-list/);assert.match(html,/finance-totals/);assert.match(html,/1 条行程/);assert.match(html,/105\.00/);assert.match(html,/98\.00/);assert.match(html,/7\.00/);assert.doesNotMatch(html,/wallet-total|999\.00/);
});
test('App-style finance empty period keeps zero totals, date controls and snapshot entry',()=>{
 const c=boot();vm.runInContext(`location.hash='period=month&anchor=2026-10-27';renderPaymentMethods=()=>'';state.trips=[];`,c);const html=vm.runInContext('renderWallet()',c);assert.match(html,/暂无收支/);assert.match(html,/0 条行程/);assert.match(html,/2026年10月/);assert.match(html,/data-action="finance-snapshots"/);assert.match(html,/0\.00/);
});

test('flight result card uses App schedule/airport layout and escapes provider strings',()=>{
 const c=boot();c.flight={airlineName:'<script>bad()</script>',departureAirport:'IAH',arrivalAirport:'LAX',departureTime:'16:30',estimatedArrivalTime:'18:07',departureTerminal:'C',arrivalTerminal:'7'};
 const html=vm.runInContext("flightResultHTML('UA1743',flight)",c);assert.match(html,/app-flight-schedule/);assert.match(html,/app-flight-airports/);assert.match(html,/16:30/);assert.match(html,/18:07/);assert.match(html,/出发航站楼 C/);assert.match(html,/到达航站楼 7/);assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>|flight-details/);
});
test('flight card missing departure terminal does not borrow arrival terminal and uses explicit fallbacks',()=>{
 const c=boot();const html=vm.runInContext("flightResultHTML('JX2',{arrivalAirport:'LAX',arrivalTerminal:'B'},{departureTime:'23:40',estimatedArrivalTime:'19:00'})",c);assert.match(html,/出发航站楼 —/);assert.match(html,/到达航站楼 B/);assert.match(html,/23:40/);assert.match(html,/19:00/);
});
test('flight card offset label uses only explicit timestamp offset, never browser timezone',()=>{
 const c=boot();assert.equal(vm.runInContext("flightOffsetLabel('16:30')",c),'');assert.equal(vm.runInContext("flightOffsetLabel('2026-10-24T16:30:00-05:00')",c),'GMT-5');assert.equal(vm.runInContext("flightOffsetLabel('2026-10-24T16:30:00+05:30')",c),'GMT+5:30');
});
test('flight candidates keep separate indexed segments and App-style direction/time rows',()=>{
 const c=boot();c.flights=[{departureAirport:'TPE',arrivalAirport:'SFO',departureTime:'23:40',estimatedArrivalTime:'18:30'},{departureAirport:'TPE',arrivalAirport:'LAX',departureTime:'23:40',estimatedArrivalTime:'19:05'}];const html=vm.runInContext("flightCandidateRows('JX2', flights)",c);assert.match(html,/data-index="0"/);assert.match(html,/data-index="1"/);assert.match(html,/app-flight-schedule/);assert.ok(html.indexOf('SFO')<html.indexOf('LAX'));
});
test('date-only flight date is a calendar date and never shifts to previous day',()=>{
 const c=boot();assert.equal(vm.runInContext("dateInput('2026-11-25')",c),'2026-11-25');assert.equal(vm.runInContext("dateInput('2026-01-01')",c),'2026-01-01');
});

test('actual lookup selection rejects wrong airport, preserves old snapshot, and renders the accepted result without saving',async()=>{
 const c=boot();c.calls=[];c.result={innerHTML:'old-result',classList:{remove(){}}};c.lookupButton={disabled:false,textContent:'查询航班'};
 c.form={isConnected:true,elements:Object.fromEntries(Object.entries({flight_info:'JX2',flight_date:'2026-11-25',service_type:'接机',location_start:'LAX',location_end:'Pasadena',flight_selection_snapshot:'old-snapshot',flight_departure_time:'',flight_estimated_arrival_time:'',flight_arrival_terminal:'',flight_baggage_carousel:''}).map(([k,v])=>[k,{value:v}])),querySelector:s=>s.includes('lookup-flight')?c.lookupButton:s.includes('data-flight-result')?c.result:null};
 vm.runInContext(`queryTripFlights=async()=>[{departureAirport:'TPE',arrivalAirport:'SFO',departureTime:'23:40',estimatedArrivalTime:'18:30'},{departureAirport:'TPE',arrivalAirport:'LAX',departureTime:'23:40',estimatedArrivalTime:'19:05',departureTerminal:'2',arrivalTerminal:'B'}];chooseFlight=(number,candidates,select)=>{globalThis.qaCandidates=candidates;globalThis.qaSelect=select;};request=(...args)=>calls.push(args);`,c);
 await vm.runInContext('lookupFlight(form)',c);assert.throws(()=>vm.runInContext('qaSelect(qaCandidates[0])',c),/机场不符/);assert.equal(c.form.elements.flight_selection_snapshot.value,'old-snapshot');assert.equal(c.result.innerHTML,'old-result');vm.runInContext('qaSelect(qaCandidates[1])',c);assert.equal(c.form.elements.flight_arrival_terminal.value,'B');assert.match(c.result.innerHTML,/app-flight-result/);assert.match(c.result.innerHTML,/19:05/);assert.equal(JSON.parse(c.form.elements.flight_selection_snapshot.value).selected.arrivalAirport,'LAX');assert.equal(c.calls.length,0);assert.equal(c.lookupButton.disabled,false);
});
test('late flight selection after changing the form context cannot replace the displayed result',async()=>{
 const c=boot();c.result={innerHTML:'keep',classList:{remove(){}}};c.lookupButton={};c.form={isConnected:true,elements:Object.fromEntries(Object.entries({flight_info:'JX2',flight_date:'2026-11-25',service_type:'接机',location_start:'LAX',location_end:'Pasadena'}).map(([k,v])=>[k,{value:v}])),querySelector:s=>s.includes('lookup-flight')?c.lookupButton:null};vm.runInContext(`queryFlights=async()=>[{arrivalAirport:'LAX'}];chooseFlight=(number,candidates,select)=>{globalThis.qaSelect=select;};`,c);await vm.runInContext('lookupFlight(form)',c);c.form.elements.flight_info.value='UA1743';assert.throws(()=>vm.runInContext('qaSelect({})',c),/行程已变化/);assert.equal(c.result.innerHTML,'keep');
});

test('trip detail uses stacked read-only sections instead of nested two-column form grids',()=>{
 const c=boot();c.trip={id:'t',customer_name:'QA',appointment_date:'2026-11-25',appointment_time:'2026-11-25T19:00:00-08:00',order_source:'旅行社订单',travel_agency_code:'QA01',travel_agency_name:'QA Agency',flight_info:'JX2',flight_date:'2026-11-25',price:90,tip:0,stops:[],expenses:[]};const before=JSON.stringify(c.trip);c.calls=[];vm.runInContext(`showModal=(title,html)=>{globalThis.detailHTML=html;};request=(...args)=>calls.push(args);openTripDetail(trip);`,c);assert.equal((c.detailHTML.match(/class="detail-section-body"/g)||[]).length,3);assert.doesNotMatch(c.detailHTML,/class="form-grid"/);assert.match(c.detailHTML,/detail-flight-actions/);assert.match(c.detailHTML,/QA Agency/);assert.match(c.detailHTML,/QA01/);assert.equal(c.calls.length,0);assert.equal(JSON.stringify(c.trip),before);
});
test('missing stored departure airport remains unknown rather than inferred from flight number',()=>{
 const c=boot();const html=vm.runInContext("flightResultHTML('CX882',{arrivalAirport:'洛杉矶',departureTerminal:'T1',arrivalTerminal:'TBIT'})",c);assert.match(html,/<small>起飞机场<\/small><strong>—<\/strong>/);assert.match(html,/出发航站楼 T1/);assert.match(html,/到达航站楼 TBIT/);assert.doesNotMatch(html,/HKG|香港/);
});

test('new trip flight section shows App input pair and keeps query-derived fields hidden for saving',()=>{
 const c=boot();const empty=vm.runInContext("tripFlightSection(null,false,'2026-11-25')",c);assert.match(empty,/app-trip-flight-inputs/);assert.match(empty,/查询航班信息/);assert.match(empty,/data-action="lookup-flight" disabled/);assert.equal((empty.match(/type="hidden"/g)||[]).length,4);for(const name of ['flight_departure_time','flight_estimated_arrival_time','flight_arrival_terminal','flight_baggage_carousel'])assert.match(empty,new RegExp('type="hidden" name="'+name+'"'));assert.doesNotMatch(empty,/手动填写航班详情|航班起飞日期/);
 c.trip={flight_info:'JX2',flight_date:'2026-11-25',flight_arrival_terminal:'B'};const html=vm.runInContext("tripFlightSection(trip,false,'2026-11-26')",c);assert.match(html,/value="2026-11-25"/);assert.match(html,/name="flight_arrival_terminal" value="B"/);assert.doesNotMatch(html,/data-action="lookup-flight" disabled/);
});
test('lookup failure appears inline, reenables query and preserves unsaved flight data',async()=>{
 const c=boot();c.feedback={textContent:'',classList:{add(){},remove(){}}};c.button={};c.form={isConnected:true,elements:Object.fromEntries(Object.entries({flight_info:'JX2',flight_date:'2026-11-25',service_type:'接机',location_start:'LAX',location_end:'Pasadena',flight_selection_snapshot:'keep'}).map(([k,v])=>[k,{value:v}])),querySelector:s=>s.includes('lookup-flight')?c.button:s.includes('data-flight-feedback')?c.feedback:null};vm.runInContext("queryFlights=async()=>{throw Error('QA network failed');}",c);await assert.rejects(vm.runInContext('lookupFlight(form)',c),/QA network failed/);assert.equal(c.feedback.textContent,'QA network failed');assert.equal(c.form.elements.flight_selection_snapshot.value,'keep');assert.equal(c.button.disabled,false);assert.match(c.button.textContent,/查询航班信息/);
});
test('flight context invalidation updates empty/nonempty query availability and clears derived fields',()=>{
 const c=boot();c.button={disabled:true};c.form={elements:Object.fromEntries(Object.entries({flight_info:'JX2',flight_selection_snapshot:'old',flight_departure_time:'23:40',flight_estimated_arrival_time:'19:05',flight_arrival_terminal:'B',flight_baggage_carousel:'1'}).map(([k,v])=>[k,{value:v}])),querySelector:s=>s.includes('lookup-flight')?c.button:{classList:{add(){}}}};vm.runInContext('invalidateFormFlight(form)',c);assert.equal(c.button.disabled,false);assert.equal(c.form.elements.flight_selection_snapshot.value,'null');assert.equal(c.form.elements.flight_arrival_terminal.value,'');c.form.elements.flight_info.value='';vm.runInContext('invalidateFormFlight(form)',c);assert.equal(c.button.disabled,true);
});

test('trip route markup places indexed stops between start and destination without changing stop data',()=>{
 const c=boot();c.trip={location_start:'Start',location_end:'End',stops:[{address:'First stop'},{address:'Second stop'}]};const before=JSON.stringify(c.trip);const html=vm.runInContext('tripRouteFields(trip)',c);assert.ok(html.indexOf('name="location_start"')<html.indexOf('name="stop_address"'));assert.ok(html.lastIndexOf('name="stop_address"')<html.indexOf('name="location_end"'));assert.ok(html.indexOf('First stop')<html.indexOf('Second stop'));assert.match(html,/data-action="swap-route"/);assert.match(html,/data-action="add-stop"/);assert.equal(JSON.stringify(c.trip),before);
});
test('trip editor toolbar associates one save button with the existing form and keeps cancel available',()=>{
 const c=boot();c.document.body.insertAdjacentHTML=(_position,html)=>{c.modalHTML=html;};vm.runInContext(`showModal('新增行程','<form id="tripForm"></form>','editor-modal trip-editor-modal')`,c);assert.match(c.modalHTML,/data-action="close-modal">取消/);assert.equal((c.modalHTML.match(/type="submit" form="tripForm"/g)||[]).length,1);assert.match(c.modalHTML,/>保存<\/button>/);assert.doesNotMatch(c.modalHTML,/aria-label="关闭"/);
});

test('reordered trip editor keeps one customer/date/route field and preserves existing tip as hidden data',()=>{
 const c=boot();c.trip={id:'t',customer_name:'QA',appointment_date:'2026-11-25T12:00:00Z',appointment_time:'2026-11-25T19:00:00Z',price:90,tip:12,is_paid:false,stops:[],expenses:[]};const before=JSON.stringify(c.trip);vm.runInContext(`showModal=(title,html)=>{globalThis.editorHTML=html;};openTripForm(trip);`,c);for(const name of ['customer_name','appointment_date','appointment_time','location_start','location_end','tip'])assert.equal((c.editorHTML.match(new RegExp('name="'+name+'"','g'))||[]).length,1,name);assert.match(c.editorHTML,/type="hidden" name="tip" value="12"/);assert.doesNotMatch(c.editorHTML,/form-actions|创建行程<\/button>/);assert.ok(c.editorHTML.indexOf('行程类型')<c.editorHTML.indexOf('智能输入'));assert.ok(c.editorHTML.indexOf('订单来源')<c.editorHTML.indexOf('客户名称'));assert.ok(c.editorHTML.indexOf('费用与备注')<c.editorHTML.indexOf('状态信息'));assert.equal(JSON.stringify(c.trip),before);
});
test('payment segmented control submits the same boolean strings as the previous selector',()=>{
 const c=boot();const unpaid=vm.runInContext('tripPaidSelector(false)',c),paid=vm.runInContext('tripPaidSelector(true)',c);assert.match(unpaid,/name="is_paid" value="false" checked/);assert.match(paid,/name="is_paid" value="true" checked/);assert.equal((paid.match(/name="is_paid"/g)||[]).length,2);
});

test('trip input Enter and IME confirmation block implicit submit without cancelling native datalist handling',()=>{
 const c=boot();c.form={id:'tripForm',dataset:{}};c.event={key:'Enter',isComposing:true,target:{tagName:'INPUT',type:'text',form:c.form},preventDefault(){throw Error('Native IME/datalist must not be cancelled');}};vm.runInContext('handleTripFormEnter(event)',c);assert.equal(c.form.dataset.blockEnterSubmit,'true');c.event.target.tagName='TEXTAREA';vm.runInContext('handleTripFormEnter(event)',c);assert.equal(c.form.dataset.blockEnterSubmit,undefined);
});
test('trip implicit Enter submission never reaches save, while explicit Save still does',async()=>{
 const c=boot();c.HTMLFormElement=class QAForm{};c.form=new c.HTMLFormElement();Object.assign(c.form,{id:'tripForm',dataset:{blockEnterSubmit:'true'},querySelectorAll:()=>[]});c.calls=[];vm.runInContext('submitTrip=async()=>{calls.push("save");}',c);let prevented=false;await c.listeners.submit({target:c.form,preventDefault(){prevented=true;}});assert.equal(prevented,true);assert.equal(c.calls.length,0);vm.runInContext('handleTripFormEnter({key:"Enter",target:{tagName:"BUTTON",form}})',c);await c.listeners.submit({target:c.form,preventDefault(){}});assert.equal(c.calls.length,1);assert.equal(c.form.dataset.submitting,'false');
});
test('Enter guard leaves other forms untouched',()=>{
 const c=boot();c.form={id:'loginForm',dataset:{}};vm.runInContext('handleTripFormEnter({key:"Enter",target:{tagName:"INPUT",type:"text",form}})',c);assert.equal(c.form.dataset.blockEnterSubmit,undefined);
});


test('native symbol assets are packaged locally and untrusted names cannot select paths',()=>{
 const c=boot();
 assert.match(c.appIcon('../../outside'),/data-symbol="questionmark.circle"/);
 const manifest=JSON.parse(fs.readFileSync(new URL('../assets/icons/manifest.json',import.meta.url)));
 for(const name of manifest.symbols){
  const data=fs.readFileSync(new URL(`../assets/icons/${name.replaceAll('.','-')}.png`,import.meta.url));
  assert.equal(data.subarray(1,4).toString(),'PNG');assert.ok(data.length>100);
  assert.match(c.appIcon(name),/aria-hidden="true"/);
 }
 assert.equal(c.serviceSymbol('接机'),'airplane.arrival');
 assert.equal(c.serviceSymbol('送机'),'airplane.departure');
 assert.equal(c.serviceSymbol('接机','picker'),'airplane.departure');
 assert.equal(c.serviceSymbol('送机','picker'),'airplane.arrival');
 assert.match(c.serviceTypePicker('送机'),/data-symbol="checkmark.circle.fill"/);
 assert.doesNotMatch(c.serviceTypePicker('送机'),/service-type-check/);
});

test('completion asks before writing and second prompt appears only after successful narrow status update',async()=>{
 const c=boot();c.writes=[];vm.runInContext(`state.trips=[{id:'qa',price:90,is_paid:true,location_start:'Keep'}];showModal=(title,html)=>{globalThis.prompt={title,html};};markTrip=async(id,updates)=>{writes.push({id,updates});};requestTripCompletion('qa');`,c);
 assert.equal(c.writes.length,0);assert.equal(c.prompt.title,'确认完成行程？');assert.match(c.prompt.html,/取消/);
 await c.confirmTripCompletion({disabled:false});assert.equal(c.writes.length,1);assert.deepEqual(JSON.parse(JSON.stringify(c.writes[0].updates)),{is_completed:true,is_cancelled:false});assert.equal(c.prompt.title,'行程已结束');assert.match(c.prompt.html,/completion-settlement/);
});
test('completion blocks duplicate clicks and account changes; failed update keeps confirmation retryable',async()=>{
 const c=boot();c.writes=[];vm.runInContext(`state.trips=[{id:'qa'}];showModal=(title)=>{globalThis.promptTitle=title;};markTrip=async()=>{writes.push('write');throw Error('offline');};requestTripCompletion('qa');`,c);
 const button={disabled:false};await assert.rejects(c.confirmTripCompletion(button),/offline/);assert.equal(button.disabled,false);assert.equal(c.promptTitle,'确认完成行程？');
 vm.runInContext(`state.user={id:'other'};`,c);await c.confirmTripCompletion(button);assert.equal(c.writes.length,1);
 vm.runInContext(`state.user={id:'owner'};markTrip=()=>new Promise(resolve=>{globalThis.finish=resolve;});`,c);
 const first=c.confirmTripCompletion(button);await c.confirmTripCompletion(button);assert.equal(button.disabled,true);c.finish();await first;assert.equal(c.promptTitle,'行程已结束');
});

function locationFixture(){
 const c=boot();const input={value:'LAX'},form={isConnected:true,elements:{location_start:input}};
 const button={disabled:false,dataset:{target:'start'},closest:()=>form};
 c.document.getElementById=id=>id==='tripForm'?form:null;
 c.navigator.geolocation={getCurrentPosition:(ok,fail)=>{c.positionOK=ok;c.positionFail=fail;}};
 c.invalidations=0;vm.runInContext('invalidateFormFlight=()=>{invalidations++;};',c);
 return {c,input,form,button};
}
test('location success invalidates old flight and does not duplicate a pending request',()=>{
 const {c,input,button}=locationFixture();let calls=0;const original=c.navigator.geolocation.getCurrentPosition;c.navigator.geolocation.getCurrentPosition=(...args)=>{calls++;original(...args);};c.locateTripAddress(button);c.locateTripAddress(button);assert.equal(calls,1);c.positionOK({coords:{latitude:34,longitude:-118}});assert.equal(input.value,'34.000000, -118.000000');assert.equal(c.invalidations,1);assert.equal(button.disabled,false);
});
for(const reason of ['edited','closed','account','generation','replaced'])test(`late location ignored after ${reason}`,()=>{
 const {c,input,form,button}=locationFixture();c.locateTripAddress(button);
 if(reason==='edited')input.value='My new address';if(reason==='closed')form.isConnected=false;if(reason==='account')vm.runInContext("state.user={id:'other'}",c);if(reason==='generation')vm.runInContext('workspaceGeneration++',c);if(reason==='replaced')form.elements.location_start={value:'Other'};
 const before=input.value;c.positionOK({coords:{latitude:34,longitude:-118}});assert.equal(input.value,before);assert.equal(c.invalidations,0);assert.equal(button.disabled,false);
});
test('invalid coordinates and failed location preserve address and snapshot',()=>{
 for(const failure of [true,false]){const {c,input,button}=locationFixture();c.locateTripAddress(button);if(failure)c.positionFail({message:'denied'});else c.positionOK({coords:{latitude:NaN,longitude:999}});assert.equal(input.value,'LAX');assert.equal(c.invalidations,0);assert.equal(button.disabled,false);}
});

test('copy resets hidden tip and settlement/completion/snapshot identity while edit preserves original tip',()=>{
 const c=boot();c.trip={id:'source',customer_name:'QA',price:90,tip:12,is_paid:true,is_completed:true,is_cancelled:false,appointment_date:'2026-11-25',appointment_time:'2026-11-25T19:00:00Z',travel_agency_order_number:'C-0000000-US',stops:[],expenses:[],flight_selection_snapshot:{version:1}};
 const original=JSON.stringify(c.trip);vm.runInContext(`showModal=(title,html)=>{globalThis.formHTML=html;globalThis.formTitle=title;};openTripForm(trip,true);`,c);
 assert.equal(c.formTitle,'复制行程');assert.match(c.formHTML,/name="tip" value="0"/);assert.match(c.formHTML,/value="false" checked/);assert.match(c.formHTML,/readonly-status">待执行/);assert.doesNotMatch(c.formHTML,/data-id="source"|value="C-0000000-US"/);assert.match(c.formHTML,/name="flight_selection_snapshot" value="null"/);assert.equal(JSON.stringify(c.trip),original);
 vm.runInContext('openTripForm(trip);',c);assert.match(c.formHTML,/name="tip" value="12"/);
});

test('calendar-only labels retain their day while timestamps retain local formatting',()=>{
 const c=boot();for(const day of ['2026-11-25','2027-01-01','2028-02-29'])assert.equal(c.dateOnly(day),day.slice(5).replace('-','/'));assert.equal(c.dateOnly('2026-02-30'),'—');assert.equal(c.dateOnly('bad'),'—');const timestamp='2026-11-25T00:00:00Z';assert.equal(c.dateOnly(timestamp),new Intl.DateTimeFormat('zh-CN',{month:'2-digit',day:'2-digit'}).format(new Date(timestamp)));
});

test('finance snapshots order equivalent offset dates by actual clock and stable ID, not timestamp text',()=>{
 const c=boot();vm.runInContext(`showModal=(title,html)=>{globalThis.snapshotHTML=html;};state.trips=[
 {id:'z',customer_name:'LaterClock',appointment_date:'2026-10-28T00:00:00-07:00',appointment_time:'2026-10-28T12:00:00-07:00'},
 {id:'b',customer_name:'EarlyB',appointment_date:'2026-10-28T07:00:00Z',appointment_time:'2026-10-28T09:00:00-07:00'},
 {id:'a',customer_name:'EarlyA',appointment_date:'2026-10-28T00:00:00-07:00',appointment_time:'2026-10-28T16:00:00Z'},
 {id:'outside',customer_name:'EndBoundary',appointment_date:'2026-10-29T07:00:00Z',appointment_time:'2026-10-29T07:00:00Z'}];openFinanceSnapshots('2026-10-28T07:00:00Z','2026-10-29T07:00:00Z');`,c);
 assert.ok(c.snapshotHTML.indexOf('EarlyA')<c.snapshotHTML.indexOf('EarlyB'));assert.ok(c.snapshotHTML.indexOf('EarlyB')<c.snapshotHTML.indexOf('LaterClock'));assert.doesNotMatch(c.snapshotHTML,/EndBoundary/);
});

test('finance month and year navigation clamps month-end and leap days without skipping periods',()=>{
 const c=boot();for(const [day,period,step,expected] of [['2027-01-31','month',1,'2027-02-28'],['2028-01-31','month',1,'2028-02-29'],['2027-03-31','month',-1,'2027-02-28'],['2028-02-29','year',1,'2029-02-28'],['2027-12-31','month',1,'2028-01-31'],['2027-03-13','day',1,'2027-03-14'],['2027-03-13','week',1,'2027-03-20']]){
  const original=new Date(`${day}T12:00:00`),before=+original;assert.equal(c.dateInput(c.shiftFinanceAnchor(original,period,step)),expected);assert.equal(+original,before);
 }
});

test('cancelled financial record contributes neither fare, tip, expenses, count nor snapshot',()=>{
 const c=boot();c.location.hash='#period=day&anchor=2026-10-28';vm.runInContext(`state.settings={currency_code:'USD'};state.trips=[
 {id:'normal',customer_name:'Normal QA',appointment_date:'2026-10-28T12:00:00-07:00',appointment_time:'2026-10-28T12:00:00-07:00',price:90,tip:10,expenses:[{title:'Normal toll',amount:5,is_addition:false}],stops:[]},
 {id:'cancelled',customer_name:'Cancelled QA',is_cancelled:true,appointment_date:'2026-10-28T12:00:00-07:00',appointment_time:'2026-10-28T12:00:00-07:00',price:50,tip:20,expenses:[{title:'Cancelled toll',amount:8,is_addition:false}],stops:[]}];globalThis.walletHTML=renderWallet();showModal=(title,html)=>{globalThis.snapshotHTML=html;};openFinanceSnapshots('2026-10-28T00:00:00-07:00','2026-10-29T00:00:00-07:00');`,c);
 assert.match(c.walletHTML,/1 条行程/);assert.match(c.walletHTML,/100\.00/);assert.match(c.walletHTML,/95\.00/);assert.doesNotMatch(c.walletHTML,/Cancelled toll/);assert.match(c.snapshotHTML,/Normal QA/);assert.doesNotMatch(c.snapshotHTML,/Cancelled QA/);
});

test('home monthly net excludes next month, prior month and cancelled trips',()=>{
 const c=boot();const now=new Date(),month=new Date(now.getFullYear(),now.getMonth(),1,12),next=new Date(now.getFullYear(),now.getMonth()+1,1,12),prior=new Date(now.getFullYear(),now.getMonth(),0,12);
 c.records=[{id:'normal',appointment_date:month.toISOString(),price:90,tip:10,expenses:[{amount:5,is_addition:false}]},{id:'future',appointment_date:next.toISOString(),price:500},{id:'prior',appointment_date:prior.toISOString(),price:300},{id:'cancelled',appointment_date:month.toISOString(),price:200,is_cancelled:true}];
 vm.runInContext('state.trips=records;globalThis.homeHTML=renderHome();',c);const card=c.homeHTML.match(/<article class="stat-card">(?:(?!<article).)*本月净收入(?:(?!<article).)*?<\/article>/s)?.[0];assert.ok(card);assert.match(card,/95\.00/);assert.doesNotMatch(card,/595\.00|895\.00/);
});
test('customer financial summary counts only noncancelled trips while preserving cancelled history',()=>{
 const c=boot();vm.runInContext(`state.customers=[{id:'qa',name:'QA'}];state.trips=[{id:'ok',customer_id:'qa',customer_name:'Normal',appointment_date:'2026-10-28',appointment_time:'2026-10-28T12:00:00Z',price:90,tip:0,expenses:[]},{id:'cancel',customer_id:'qa',customer_name:'CancelledHistory',is_cancelled:true,appointment_date:'2026-10-28',appointment_time:'2026-10-28T12:00:00Z',price:50,tip:20,expenses:[]}];showModal=(title,html)=>{globalThis.customerHTML=html;};openCustomerDetail(state.customers[0]);`,c);
 assert.equal(c.customerStats({id:'qa',name:'QA'}).trips,1);assert.match(c.customerHTML,/1 次出行 · 总收入/);assert.match(c.customerHTML,/data-id="cancel"/);
});

test('overlapping foreground events share one load and retain an unsaved draft',async()=>{
 const c=boot();c.resolveProductEdition=async()=>{};c.counts={load:0,render:0,status:0};c.draft={value:'Unsaved QA address'};let finish;
 c.loadData=()=>{c.counts.load++;return new Promise(resolve=>finish=resolve);};c.document.getElementById=()=>c.draft;c.renderApp=()=>c.counts.render++;c.renderConnectionStatus=()=>c.counts.status++;
 const first=c.refreshOnForeground();await c.refreshOnForeground();assert.equal(c.counts.load,1);finish();await first;assert.equal(c.counts.render,0);assert.equal(c.draft.value,'Unsaved QA address');assert.equal(c.counts.status,1);
});
test('failed foreground load preserves draft and releases refresh so next attempt succeeds',async()=>{
 const c=boot();c.resolveProductEdition=async()=>{};c.counts={load:0,render:0};c.draft={value:'QA not saved'};c.document.getElementById=()=>c.draft;c.renderConnectionStatus=()=>{};c.renderApp=()=>c.counts.render++;let fail=true;c.loadData=async()=>{c.counts.load++;if(fail)throw new TypeError('Failed to fetch');};
 await c.refreshOnForeground();assert.equal(c.draft.value,'QA not saved');assert.equal(c.counts.render,0);fail=false;await c.refreshOnForeground();assert.equal(c.counts.load,2);assert.equal(c.counts.render,0);assert.equal(c.draft.value,'QA not saved');
});

for(const [label,values] of [['negative fare',{price:'-1',tip:'0'}],['negative tip',{price:'0',tip:'-1'}],['zero expense',{price:'0',tip:'0',expense_title_0:'Toll',expense_amount_0:'0'}],['missing expense name',{price:'0',tip:'0',expense_title_0:'',expense_amount_0:'5'}],['infinite expense',{price:'0',tip:'0',expense_title_0:'Toll',expense_amount_0:'Infinity'}]])test(`settlement ${label} performs no request`,async()=>{
 const c=boot();c.calls=[];vm.runInContext(`state.trips=[{id:'qa'}];state.settlementDraft={tripID:'qa',expenses:[]};request=async(...args)=>calls.push(args);`,c);const form={values,querySelectorAll:()=>Object.hasOwn(values,'expense_amount_0')?[{}]:[]};await assert.rejects(c.submitSettlement(form));assert.equal(c.calls.length,0);
});
test('zero fare and tip are valid and settle once without changing execution state or route',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`state.trips=[{id:'qa',is_completed:false,location_start:'Keep'}];state.settlementDraft={tripID:'qa',expenses:[]};request=async(path,options)=>calls.push({path,...options});`,c);await c.submitSettlement({values:{price:'0',tip:'0'},querySelectorAll:()=>[]});assert.equal(c.calls.length,1);assert.equal(c.calls[0].body.p_fare,0);assert.equal(c.calls[0].body.p_tip,0);assert.equal(Object.hasOwn(c.calls[0].body,'is_completed'),false);
});
test('settlement form blocks duplicate submits and releases buttons after failure for retry',async()=>{
 const c=boot();c.HTMLFormElement=class QAForm{};const form=new c.HTMLFormElement(),button={disabled:false};Object.assign(form,{id:'settlementForm',dataset:{},querySelectorAll:()=>[button]});let reject,calls=0;c.submitSettlement=()=>{calls++;return new Promise((_,fail)=>reject=fail);};const event={target:form,preventDefault(){}};const first=c.listeners.submit(event);await c.listeners.submit(event);assert.equal(calls,1);assert.equal(button.disabled,true);reject(Error('QA offline'));await first;assert.equal(button.disabled,false);assert.equal(form.dataset.submitting,'false');c.submitSettlement=async()=>{calls++;};await c.listeners.submit(event);assert.equal(calls,2);
});

test('trip filters retain status semantics and cancelled restoration preserves amounts',()=>{
 const c=boot();const day=c.dateInput(new Date());c.records=[{id:'pending',appointment_date:day,appointment_time:new Date().toISOString(),price:90,tip:10,expenses:[]},{id:'completed',appointment_date:day,appointment_time:new Date().toISOString(),is_completed:true,is_paid:true,price:20},{id:'cancelled',appointment_date:day,appointment_time:new Date().toISOString(),is_cancelled:true,price:50,tip:0,expenses:[]}];
 vm.runInContext('state.trips=records;state.tripFilter="pending";',c);assert.deepEqual(Array.from(c.filteredTrips(),t=>t.id),['pending']);vm.runInContext('state.tripFilter="all"',c);assert.equal(c.filteredTrips().length,3);
 vm.runInContext('state.tripFilter="unpaid"',c);assert.deepEqual(Array.from(c.filteredTrips(),t=>t.id).sort(),['cancelled','pending']);
 const before=JSON.stringify(c.records[2]);c.records[2].is_cancelled=false;c.records[2].is_completed=false;vm.runInContext('state.tripFilter="pending"',c);assert.equal(c.filteredTrips().length,2);assert.equal(c.records[2].price,JSON.parse(before).price);assert.equal(c.records[2].tip,0);
});

for(const paid of [false,true])test(`save-only offline overlay preserves paid=${paid} and unrelated trip fields`,()=>{
 const c=boot();c.snapshot={trips:[{id:'qa',is_paid:paid,is_completed:true,location_start:'Keep'}],expenses:[{trip_id:'qa',id:'old'}]};c.applyQueuedOperation(c.snapshot,{table:'rpc/save_online_trip_finances',body:{p_trip_id:'qa',p_fare:120,p_tip:8,p_expenses:[{id:'new',title:'Toll',amount:5}]}});assert.equal(c.snapshot.trips[0].is_paid,paid);assert.equal(c.snapshot.trips[0].is_completed,true);assert.equal(c.snapshot.trips[0].location_start,'Keep');assert.equal(c.snapshot.trips[0].price,120);assert.equal(c.snapshot.expenses[0].id,'new');
});
test('save-only uses one narrow RPC with no client payment status and keeps stable expense IDs',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`state.trips=[{id:'qa',is_paid:false}];state.settlementDraft={tripID:'qa',expenses:[{id:'stable'}]};request=async(path,options)=>calls.push({path,...options});`,c);await c.submitSettlement({values:{price:'120',tip:'8',expense_title_0:'Toll',expense_amount_0:'5'},querySelectorAll:()=>[{}]},false);assert.equal(c.calls.length,1);assert.equal(c.calls[0].path,'rpc/save_online_trip_finances');assert.equal(Object.hasOwn(c.calls[0].body,'is_paid'),false);assert.equal(c.calls[0].body.p_expenses[0].id,'stable');assert.equal(c.calls[0].queueOffline,false);
});
test('settlement form submits distinct save-only and settle actions',async()=>{
 const c=boot();c.HTMLFormElement=class QAForm{};const form=new c.HTMLFormElement();Object.assign(form,{id:'settlementForm',dataset:{},querySelectorAll:()=>[]});const modes=[];c.submitSettlement=async(_,markPaid)=>modes.push(markPaid);for(const mode of ['save','settle'])await c.listeners.submit({target:form,submitter:{dataset:{settlementMode:mode}},preventDefault(){}});assert.deepEqual(modes,[false,true]);
});

test('save-only replay keeps failed job for retry, then replays before settle without changing payload semantics',async()=>{
 const c=boot();c.navigator.onLine=false;c.renderConnectionStatus=()=>{};vm.runInContext(`state.productEdition='sync';`,c);
 const body={p_trip_id:'qa',p_fare:120,p_tip:8,p_expenses:[{id:'stable',title:'Toll',amount:5}]};
 c.persistOfflineOperation({table:'rpc/save_online_trip_finances',method:'POST',body});c.persistOfflineOperation({table:'rpc/settle_online_trip',method:'POST',body});assert.equal(c.queuedOperationCount(),2);
 const calls=[];let reject=true;c.request=async(table,options)=>{calls.push({table,...options});if(reject)throw Error('QA server rejected');};c.navigator.onLine=true;await c.replayOfflineQueue();assert.equal(c.queuedOperationCount(),2);reject=false;await c.replayOfflineQueue();assert.equal(c.queuedOperationCount(),0);
 assert.deepEqual(calls.map(x=>x.table),['rpc/save_online_trip_finances','rpc/save_online_trip_finances','rpc/settle_online_trip']);for(const call of calls){assert.equal(call.queueOffline,false);assert.equal(call.body.p_expenses[0].id,'stable');assert.equal(Object.hasOwn(call.body,'is_paid'),false);}
});
test('sync-mode save-only uses the dedicated queued RPC and never falls back to settling',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`state.productEdition='sync';state.trips=[{id:'qa',is_paid:true}];state.settlementDraft={tripID:'qa',expenses:[]};request=async(path,options)=>calls.push({path,...options});`,c);await c.submitSettlement({values:{price:'90',tip:'0'},querySelectorAll:()=>[]},false);assert.equal(c.calls[0].path,'rpc/save_online_trip_finances');assert.equal(c.calls[0].queueOffline,true);assert.equal(c.calls.length,1);
});
test('save-only failure retains draft amounts and expense identity so retry can save the same values',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`state.trips=[{id:'qa',is_paid:false}];state.settlementDraft={tripID:'qa',expenses:[{id:'keep-id'}]};request=async(path,options)=>{calls.push({path,...options});throw Error('QA rejected');};`,c);const form={values:{price:'120',tip:'8',expense_title_0:'Toll',expense_amount_0:'5'},querySelectorAll:()=>[{}]};await assert.rejects(c.submitSettlement(form,false),/QA rejected/);assert.equal(vm.runInContext('state.settlementDraft.expenses[0].id',c),'keep-id');assert.equal(vm.runInContext('state.settlementDraft.price',c),120);c.request=async(path,options)=>c.calls.push({path,...options});await c.submitSettlement(form,false);assert.equal(c.calls[1].body.p_expenses[0].id,'keep-id');assert.equal(c.calls[1].path,'rpc/save_online_trip_finances');
});

for (const paid of [false, true]) test(`save-only readback keeps paid=${paid} while finance excludes cancelled fees and restores them on recovery`, () => {
 const c = boot();
 c.snapshot = { trips: [{ id:'qa-finance', customer_name:'QA Finance Readback', is_paid:paid, is_completed:false, is_cancelled:false, appointment_date:'2026-10-29T12:00:00', appointment_time:'2026-10-29T12:00:00', price:90, tip:0, stops:[] }], expenses:[] };
 c.applyQueuedOperation(c.snapshot, { table:'rpc/save_online_trip_finances', body:{ p_trip_id:'qa-finance', p_fare:120, p_tip:8, p_expenses:[{id:'qa-toll',title:'QA Toll',amount:5,is_addition:false}] } });
 vm.runInContext(`location.hash='period=day&anchor=2026-10-29';renderPaymentMethods=()=>'';state.trips=snapshot.trips.map(trip=>({...trip,expenses:snapshot.expenses.filter(item=>item.trip_id===trip.id)}));showModal=(title,html)=>{globalThis.snapshotHTML=html;};`,c);
 assert.equal(c.snapshot.trips[0].is_paid,paid);
 assert.equal(c.snapshot.trips[0].is_completed,false);
 let html = vm.runInContext('renderWallet()',c);
 assert.match(html,/1 条行程/); assert.match(html,/128\.00/); assert.match(html,/123\.00/); assert.match(html,/5\.00/);
 vm.runInContext(`state.trips[0].is_cancelled=true;openFinanceSnapshots('2026-10-29T00:00:00','2026-10-30T00:00:00');`,c);
 html = vm.runInContext('renderWallet()',c);
 assert.match(html,/0 条行程/); assert.doesNotMatch(html,/128\.00|123\.00|QA Toll/); assert.doesNotMatch(c.snapshotHTML,/QA Finance Readback/);
 vm.runInContext(`state.trips[0].is_cancelled=false;openFinanceSnapshots('2026-10-29T00:00:00','2026-10-30T00:00:00');`,c);
 html = vm.runInContext('renderWallet()',c);
 assert.match(html,/1 条行程/); assert.match(html,/123\.00/); assert.match(c.snapshotHTML,/QA Finance Readback/);
 assert.equal(vm.runInContext('state.trips[0].is_paid',c),paid);
});

test('Web reminder clock excludes expired, disabled and terminal trips but keeps paid pending trips', () => {
 const c=boot(),timers=new Map(),notifications=[];
 let nextID=0,now=Date.parse('2026-10-29T12:00:00Z');
 class ClockDate extends Date {constructor(...args){super(...(args.length?args:[now]));}static now(){return now;}}
 class NotificationMock {static permission='granted';constructor(title,options){notifications.push({title,...options});}}
 c.Date=ClockDate;c.Notification=NotificationMock;c.window.Notification=NotificationMock;
 c.setTimeout=(fn,delay)=>{const id=++nextID;timers.set(id,{fn,delay});return id;};c.clearTimeout=id=>timers.delete(id);
 vm.runInContext(`state.trips=[
 {id:'paid',customer_name:'QA Paid',is_paid:true,reminder_enabled:true,has_second_reminder:true,reminder_at:'2026-10-29T12:01:00Z',second_reminder_at:'2026-10-29T12:02:00Z'},
 {id:'expired',reminder_enabled:true,reminder_at:'2026-10-29T11:59:00Z'},
 {id:'disabled',reminder_enabled:false,reminder_at:'2026-10-29T12:01:00Z'},
 {id:'cancelled',is_cancelled:true,reminder_enabled:true,reminder_at:'2026-10-29T12:01:00Z'},
 {id:'completed',is_completed:true,reminder_enabled:true,reminder_at:'2026-10-29T12:01:00Z'}];scheduleWebReminders();`,c);
 assert.equal(timers.size,2);assert.deepEqual([...timers.values()].map(t=>t.delay),[60000,120000]);
 for(const {fn,delay} of [...timers.values()]){now=Date.parse('2026-10-29T12:00:00Z')+delay;fn();}
 assert.deepEqual(notifications.map(n=>n.tag),['paid:first','paid:second']);
});

test('Web reminder rescheduling clears pending timers on cancellation and restores only future reminders', () => {
 const c=boot(),timers=new Map();let nextID=0,now=Date.parse('2026-10-29T12:00:00Z');
 class ClockDate extends Date {constructor(...args){super(...(args.length?args:[now]));}static now(){return now;}}
 class NotificationMock {static permission='granted';}
 c.Date=ClockDate;c.Notification=NotificationMock;c.window.Notification=NotificationMock;
 c.setTimeout=(fn,delay)=>{const id=++nextID;timers.set(id,{fn,delay});return id;};c.clearTimeout=id=>timers.delete(id);
 vm.runInContext(`state.trips=[{id:'qa',reminder_enabled:true,has_second_reminder:true,reminder_at:'2026-10-29T12:01:00Z',second_reminder_at:'2026-10-29T12:03:00Z'}];scheduleWebReminders();`,c);
 assert.equal(timers.size,2);
 vm.runInContext('state.trips[0].is_cancelled=true;scheduleWebReminders()',c);assert.equal(timers.size,0);
 now=Date.parse('2026-10-29T12:02:00Z');
 vm.runInContext('state.trips[0].is_cancelled=false;scheduleWebReminders()',c);assert.equal(timers.size,1);assert.equal([...timers.values()][0].delay,60000);
 vm.runInContext('state.trips[0].reminder_enabled=false;scheduleWebReminders()',c);assert.equal(timers.size,0);
});

test('rich reminder uses validated flight terminals and pickup clock without substituting flight arrival',()=>{
 const c=boot();c.trip={service_type:'接机',flight_info:'CX882',flight_date:'2026-11-25',appointment_date:'2026-11-25T00:00:00',appointment_time:'2026-11-25T16:30:00',location_start:'LAX',location_end:'QA Hotel',customer_name:'QA Guest',flight_selection_snapshot:parity.makeFlightSnapshot('CX882','2026-11-25',{departureAirport:'HKG',arrivalAirport:'LAX',departureTerminal:'1',arrivalTerminal:'TBIT',estimatedArrivalTime:'17:30'})};
 const message=c.tripReminderMessage(c.trip,'2026-11-25T15:38:00');assert.equal(message.title,'[接机] CX882 HKG T1 → LAX TBIT');assert.match(message.body,/11\/25 16:30/);assert.match(message.body,/52 分钟/);assert.doesNotMatch(message.body,/17:30/);
 c.trip.location_start='SFO';assert.doesNotMatch(c.tripReminderMessage(c.trip,'2026-11-25T15:38:00').title,/HKG|TBIT/);
});

test('rich reminder keeps long address in body, missing terminals distinct, and stale flight data out',()=>{
 const c=boot(),address='QA Hotel, 928 E Colorado Blvd #101, Pasadena, CA 91106';
 c.trip={service_type:'接机',flight_info:'CX882',flight_date:'2026-11-25',appointment_date:'2026-11-25',appointment_time:'2026-11-25T16:30:00',location_start:'LAX\nTerminal B',location_end:address,customer_name:' QA\nGuest ',flight_selection_snapshot:parity.makeFlightSnapshot('CX882','2026-11-25',{departureAirport:'HKG',arrivalAirport:'LAX',departureTerminal:null,arrivalTerminal:'TBIT'})};
 let message=c.tripReminderMessage(c.trip,'2026-11-25T16:40:00');assert.equal(message.title,'[接机] CX882 HKG → LAX TBIT');assert.ok(message.body.includes(address));assert.match(message.body,/QA Guest/);assert.doesNotMatch(message.body,/\n|距接客/);assert.ok(!message.title.includes(address));
 c.trip.flight_info='JX2';message=c.tripReminderMessage(c.trip,'2026-11-25T15:00:00');assert.equal(message.title,'[接机] JX2');assert.doesNotMatch(message.title,/TBIT|HKG/);
});

test('registration normalizes email, keeps signup tokens out of session, and accepts optional phone',async()=>{
 const c=boot();c.calls=[];vm.runInContext(`renderLogin=()=>{};authScreen='register';state.user=null;state.session=null;authRequest=async(path,body)=>{calls.push({path,body});return {access_token:'fixture-access',refresh_token:'fixture-refresh',user:{id:'qa'}};};`,c);
 await c.submitAuthForm({values:{email:' QA@EXAMPLE.INVALID ',password:'fixture-strong',confirm_password:'fixture-strong',salutation:'QA',phone:''}});
 assert.match(c.calls[0].path,/^signup\?redirect_to=/);assert.equal(c.calls[0].body.email,'qa@example.invalid');assert.equal(vm.runInContext('authScreen',c),'login');assert.equal(vm.runInContext('state.session',c),null);assert.equal(c.localStorage.getItem('yunsheng.web.session.v1'),null);
});
test('registration mismatched passwords never reach auth endpoint',async()=>{
 const c=boot();let calls=0;c.authRequest=async()=>{calls++;};vm.runInContext(`authScreen='register';`,c);
 await assert.rejects(c.submitAuthForm({values:{email:'qa@example.invalid',password:'fixture-strong',confirm_password:'different'}}),/两次输入/);assert.equal(calls,0);
});
test('verified recovery link is removed from URL and password reset uses memory-only credential',async()=>{
 const c=boot();c.paths=[];c.sent=[];c.history={replaceState:(_s,_t,path)=>c.paths.push(path)};c.location.pathname='/';c.location.search='';c.location.hash='#type=recovery&access_token=fixture-recovery';
 vm.runInContext(`renderLogin=()=>{};networkFetch=async()=>({ok:true,json:async()=>({id:'qa',email:'qa@example.invalid',email_confirmed_at:'2026-10-30T00:00:00Z'})});authRequest=async(path,body,options)=>{sent.push({path,body,options});return {};};`,c);
 assert.equal(await c.consumeAuthLink(),true);assert.deepEqual(c.paths,['/']);assert.equal(vm.runInContext('authScreen',c),'reset');assert.equal(c.localStorage.getItem('yunsheng.web.session.v1'),null);
 await c.submitAuthForm({values:{password:'fixture-new-password',confirm_password:'fixture-new-password'}});
 assert.equal(c.sent[0].path,'user');assert.equal(c.sent[0].options.method,'PUT');assert.equal(c.sent[0].options.accessToken,'fixture-recovery');assert.equal(vm.runInContext('recoveryCredentials',c),null);assert.equal(vm.runInContext('authScreen',c),'login');
});
test('expired recovery link never opens password reset form or retains credential',async()=>{
 const c=boot();c.history={replaceState:()=>{}};c.location.pathname='/';c.location.search='';c.location.hash='#type=recovery&access_token=fixture-expired';vm.runInContext(`renderLogin=()=>{};networkFetch=async()=>({ok:false});`,c);
 await c.consumeAuthLink();assert.equal(vm.runInContext('authScreen',c),'login');assert.equal(vm.runInContext('recoveryCredentials',c),null);assert.match(vm.runInContext('state.error',c),/已失效/);
});

test('trip amount privacy masks all card money without changing orders or financial snapshots',()=>{
 const c=boot();c.trip={id:'qa-privacy',customer_name:'QA Privacy',appointment_date:'2026-11-25',appointment_time:'2026-11-25T16:30:00',price:123.45,tip:7.89,expenses:[{title:'QA Toll',amount:4.56,is_addition:false}],stops:[]};
 const original=JSON.stringify(c.trip);let html=c.renderTripCard(c.trip);assert.match(html,/123\.45/);assert.match(html,/隐藏金额/);assert.match(html,/data-symbol="eye"/);
 c.toggleTripAmounts(c.trip.id);html=c.renderTripCard(c.trip);assert.doesNotMatch(html,/123\.45|7\.89|4\.56|126\.78/);assert.match(html,/••••/);assert.match(html,/显示金额/);assert.match(html,/data-symbol="eye.slash"/);assert.equal(JSON.stringify(c.trip),original);
 const financial=c.renderTripCard(c.trip,{readOnly:true});assert.match(financial,/123\.45/);assert.doesNotMatch(financial,/toggle-trip-amounts/);
 c.toggleTripAmounts(c.trip.id);assert.match(c.renderTripCard(c.trip),/123\.45/);assert.equal(JSON.stringify(c.trip),original);
});
test('trip amount visibility is per record and retained across page renders',()=>{
 const c=boot();assert.equal(c.tripAmountsHidden('qa-a'),false);c.toggleTripAmounts('qa-a');assert.equal(c.tripAmountsHidden('qa-a'),true);assert.equal(c.tripAmountsHidden('qa-b'),false);
 vm.runInContext("state.page='home'",c);assert.equal(c.tripAmountsHidden('qa-a'),true);vm.runInContext("state.page='trips'",c);assert.equal(c.tripAmountsHidden('qa-a'),true);
 c.localStorage.setItem('yunsheng.web.trip-amounts-hidden.v1','true');assert.equal(c.tripAmountsHidden('qa-b'),false);
 const next=boot();next.localStorage.setItem('yunsheng.web.trip-amounts-hidden.v2.qa-a','true');assert.equal(next.tripAmountsHidden('qa-a'),true);assert.equal(next.tripAmountsHidden('qa-b'),false);
 c.toggleTripAmounts('qa-b');c.toggleTripAmounts('qa-a');assert.equal(c.tripAmountsHidden('qa-a'),false);assert.equal(c.tripAmountsHidden('qa-b'),true);
});

test('account validity uses actual expiry and hides absent or malformed values',()=>{
 const c=boot();const now=Date.parse('2026-10-31T12:00:00Z');assert.match(c.accountValidityHTML('2026-11-14T12:00:00Z',now),/剩余 14 天/);assert.match(c.accountValidityHTML('2026-10-31T13:00:00Z',now),/剩余 1 天/);assert.match(c.accountValidityHTML('2026-10-30T12:00:00Z',now),/已到期/);assert.equal(c.accountValidityHTML(null,now),'');assert.equal(c.accountValidityHTML('bad',now),'');
});
test('password eye toggles only targeted input without changing value or submitting',()=>{
 const c=boot();const input={type:'password',value:'qa-fixture-only',name:'password',autocomplete:'current-password'};const attrs={};const button={closest:()=>({querySelector:()=>input}),setAttribute:(k,v)=>attrs[k]=v,innerHTML:''};
 c.toggleAuthPassword(button);assert.equal(input.type,'text');assert.equal(input.value,'qa-fixture-only');assert.equal(attrs['aria-label'],'隐藏密码');assert.equal(attrs['aria-pressed'],'true');c.toggleAuthPassword(button);assert.equal(input.type,'password');assert.equal(input.value,'qa-fixture-only');assert.equal(attrs['aria-label'],'显示密码');
});
test('expired archive blocks ordinary cloud writes before device admission or network',async()=>{
 const c=boot();vm.runInContext("state.user={id:'qa-archive'};state.archiveMode=true;currentSession=async()=>({user:{id:'qa-archive'},access_token:'QA'});",c);
 await assert.rejects(c.request('trips',{method:'POST',body:{},queueOffline:false}),/仅可查看和导出/);
});
test('expired record view labels business fields and never renders internal owner ids',()=>{
 const c=boot();const html=c.archiveRecordDetails({customer_name:'QA Archive',price:90,owner_id:'secret-owner',id:'private-id'});assert.match(html,/QA Archive/);assert.match(html,/金额/);assert.doesNotMatch(html,/secret-owner|private-id/);
});
test('expired entitlement enters archive route while revoked entitlement remains blocked',async()=>{
 const c=boot();vm.runInContext("state.user={id:'qa-owner'};request=async()=>[{edition:'cloud',status:'active',expires_at:'2020-01-01T00:00:00Z',max_devices:4}]",c);
 await c.resolveProductEdition();assert.equal(vm.runInContext('state.archiveMode',c),true);assert.equal(vm.runInContext('state.archiveData',c),null);
 vm.runInContext("request=async()=>[{edition:'cloud',status:'revoked',expires_at:'2020-01-01T00:00:00Z',max_devices:4}]",c);await assert.rejects(c.resolveProductEdition(),/过期或暂停/);assert.equal(vm.runInContext('state.archiveMode',c),false);
});
test('late archive response cannot replace another account workspace',async()=>{
 const c=boot();let resolve;c.archiveResponse=new Promise(r=>{resolve=r});vm.runInContext("state.user={id:'qa-old'};state.archiveMode=true;request=async()=>await archiveResponse",c);const job=c.loadExpiredArchive();vm.runInContext("resetAccountWorkspace();state.user={id:'qa-new'}",c);resolve({read_only:true,trips:[{id:'old'}]});await job;assert.equal(vm.runInContext('state.archiveData',c),null);
});

test('agency reconciliation UI selects only eligible trips and preview is escaped and read-only',()=>{
 const c=boot();vm.runInContext(`showModal=(title,html)=>{globalThis.statementHTML=html;};state.trips=[{id:'a',order_source:'旅行社订单',travel_agency_code:'A',travel_agency_name:'Agency',customer_name:'<script>x</script>',appointment_date:'2026-11-01T00:00:00Z',appointment_time:'2026-11-01T10:00:00Z',price:90,expenses:[{title:'停车费',is_addition:true,amount:11}]},{id:'paid',order_source:'旅行社订单',travel_agency_code:'A',is_paid:true}];renderAgencyStatementEntry();statementAgency='code:A';statementSelection.add('a');globalThis.entry=renderAgencyStatementEntry();openAgencyStatement();`,c);
 assert.match(c.entry,/type="checkbox"/);assert.match(c.entry,/对账单（1 条）/);assert.doesNotMatch(c.entry,/data-statement-trip="paid"/);
 assert.match(c.statementHTML,/停车费/);assert.match(c.statementHTML,/101.00/);assert.match(c.statementHTML,/&lt;script&gt;/);assert.doesNotMatch(c.statementHTML,/<script>|data-action="(?:settle|edit|delete)/);
});

test('statement selector formats dates and groups actions without exposing raw timestamps',()=>{
 const c=boot();vm.runInContext(`state.trips=[{id:'a',order_source:'旅行社订单',travel_agency_code:'A',travel_agency_name:'QA',customer_name:'Test',appointment_date:'2026-11-25T20:00:00Z',appointment_time:'2026-11-25T20:00:00Z'}];renderAgencyStatementEntry();statementAgency='code:A';globalThis.entry=renderAgencyStatementEntry();`,c);
 assert.match(c.entry,/statement-selection-actions/);assert.match(c.entry,/statement-agency-field/);
 assert.doesNotMatch(c.entry,/2026-11-25T20:00:00Z/);assert.match(c.entry,/2026\/11\/25/);
});

test('finance merges same fee title across signs and spaces while retaining signed summary totals',()=>{
 const c=boot();vm.runInContext(`location.hash='#period=year&anchor=2026-11-02';state.trips=[{id:'qa',appointment_date:'2026-11-02T12:00:00',price:100,tip:5,expenses:[{title:'停车费',amount:11,is_addition:false},{title:' 停车费 ',amount:3,is_addition:true},{title:'停车费',amount:2,is_addition:false}]}];globalThis.html=renderWallet();`,c);
 assert.equal((c.html.match(/<span>停车费<\/span>/g)||[]).length,1);
 assert.match(c.html,/108\.00/);assert.match(c.html,/13\.00/);assert.match(c.html,/95\.00/);
});

test('six-language expiry and archive labels preserve customer text and raw export data',()=>{
 for(const language of ['zh-Hans','zh-Hant','en','es','ja','ko']){
  const c=boot(); c.language=language; c.localized=localized;
  vm.runInContext(`state.settings={language_code:language};state.entitlementExpiresAt='2026-11-16T12:00:00Z';`,c);
  const badge=vm.runInContext(`accountValidityHTML(state.entitlementExpiresAt,Date.parse('2026-11-02T12:00:00Z'))`,c);
  assert.ok(badge.includes(localized('剩余 %ld 天',language,14)));
  c.output={innerHTML:''};vm.runInContext(`document.getElementById=()=>output;state.archiveData={trips:[{customer_name:'原文 Guest <safe>',travel_agency_order_number:'C-123',price:90}],customers:[]};renderExpiredArchive();`,c);
  assert.ok(c.output.innerHTML.includes(localized('账号已到期 · 资料只读',language)));
  assert.ok(c.output.innerHTML.includes('原文 Guest &lt;safe&gt;'));
  assert.ok(c.output.innerHTML.includes('C-123'));
  assert.equal(vm.runInContext('state.archiveData.trips[0].price',c),90);
 }
});
test('six-language account deletion keeps password input and literal DELETE contract',()=>{
 for(const language of ['zh-Hans','zh-Hant','en','es','ja','ko']){
  const c=boot();c.language=language;c.dialog={};
  vm.runInContext(`state.settings={language_code:language};showModal=(title,body)=>{dialog={title,body};};showAccountDeletion();`,c);
  const dialog=vm.runInContext('dialog',c);
  assert.equal(dialog.title,localized('删除云端账号',language));
  assert.ok(dialog.body.includes('pattern="DELETE"'));
  assert.ok(dialog.body.includes('type="password"'));
  assert.ok(dialog.body.includes(localized('永久删除此云端账号',language)));
 }
});

test('expired account uses archive language preferences without enabling the writable workspace',()=>{
 const c=boot();c.output={innerHTML:''};
 vm.runInContext(`state.settings=null;state.archiveMode=true;state.archiveData={user_settings:[{language_code:'es'}],trips:[{customer_name:'QA Original'}]};document.getElementById=()=>output;renderExpiredArchive();`,c);
 assert.ok(c.output.innerHTML.includes(localized('账号已到期 · 资料只读','es')));
 assert.ok(!c.output.innerHTML.includes('账号已到期 · 资料只读'));
 assert.ok(c.output.innerHTML.includes('QA Original'));
 assert.equal(vm.runInContext('state.settings',c),null);
 assert.equal(vm.runInContext('state.archiveMode',c),true);
});

test('all four auth screens render six languages with translated eye labels and unchanged form contracts',()=>{
 for(const language of ['zh-Hans','zh-Hant','en','es','ja','ko'])for(const mode of ['login','register','recover','reset']){
  const c=boot();c.language=language;c.mode=mode;c.output={innerHTML:''};
  vm.runInContext(`state.user=null;state.session=null;state.settings=null;localStorage.setItem(INTERFACE_LANGUAGE_KEY,language);document.getElementById=()=>output;authScreen=mode;authDraft={email:'qa@example.invalid',salutation:'QA 原文',phone:''};renderLogin();`,c);
  const html=c.output.innerHTML;
  assert.ok(html.includes(localized(mode==='register'?'注册云端账号':mode==='recover'?'找回密码':mode==='reset'?'设置新密码':'欢迎回来',language)));
  assert.ok(html.includes('id="authLanguage"'));
  assert.equal(c.document.documentElement.lang,language);
  if(mode==='register') {assert.ok(html.includes('QA 原文'));assert.ok(html.includes('name="confirm_password"'));assert.ok(html.includes('minlength="8"'));assert.ok(html.includes(localized('邮箱验证后，自动开始 14 天云端版试用，最多 4 台设备。',language)));}
  if(mode==='recover')assert.ok(!html.includes('name="password"'));
  else assert.ok(html.includes(localized(mode==='reset'?'显示新密码':'显示密码',language)));
 }
});
test('auth language switch preserves typed drafts in memory, not storage or generated HTML',()=>{
 const c=boot();const controls={email:{value:'qa@example.invalid'},salutation:{value:'QA 原文'},phone:{value:''},password:{value:'fixture-only-secret'},confirm_password:{value:'fixture-only-secret'}};
 c.controls=controls;c.output={innerHTML:''};
 vm.runInContext(`state.settings=null;state.user=null;state.session=null;authScreen='register';document.getElementById=id=>id==='authForm'?{elements:controls}:id==='app'?output:controls[id];changeAuthLanguage('es');`,c);
 assert.equal(c.controls.password.value,'fixture-only-secret');
 assert.equal(c.controls.confirm_password.value,'fixture-only-secret');
 assert.ok(c.output.innerHTML.includes('QA 原文'));
 assert.ok(!c.output.innerHTML.includes('fixture-only-secret'));
 assert.equal(c.localStorage.getItem('yunsheng.web.ui-language.v1'),'es');
 assert.equal(c.localStorage.getItem('yunsheng.web.session.v1'),null);
 assert.ok(!vm.runInContext('JSON.stringify(authDraft)',c).includes('fixture-only-secret'));
});
test('language switch stays usable with blocked storage and cannot run during auth submission',()=>{
 const c=boot();c.output={innerHTML:''};vm.runInContext(`state.settings=null;document.getElementById=()=>output;localStorage.setItem=()=>{throw Error('storage blocked')};changeAuthLanguage('ja');`,c);
 assert.equal(vm.runInContext('uiLanguage()',c),'ja');
 vm.runInContext(`state.busy=true;changeAuthLanguage('ko');`,c);
 assert.equal(vm.runInContext('uiLanguage()',c),'ja');
});
test('auth notices and validation errors change language without changing their original keys',()=>{
 const c=boot();c.output={innerHTML:''};vm.runInContext(`state.settings=null;document.getElementById=()=>output;authNotice='密码已更新，请使用新密码登录。';state.error='密码至少 8 位，且两次输入必须一致。';changeAuthLanguage('en');`,c);
 assert.ok(c.output.innerHTML.includes('Your password has been updated.'));
 assert.ok(c.output.innerHTML.includes('make sure both passwords match'));
 assert.equal(vm.runInContext('authNotice',c),'密码已更新，请使用新密码登录。');
});

test('settings render six languages while preserving custom fees, email and stable choice codes',()=>{
 for(const language of ['zh-Hans','zh-Hant','en','es','ja','ko']){
  const c=boot();c.language=language;
  vm.runInContext(`state.settings={language_code:language,currency_country_code:'US',currency_code:'USD',expense_catalog:['QA 停车费 <x>'],navigation_provider:'appleMaps'};state.user.email='qa@example.invalid';`,c);
  const before=vm.runInContext('JSON.stringify(state.settings)',c),html=c.renderSettings();
  for(const key of ['账户偏好','语言偏好','默认导航','保存设置','费用项目','保存费用项目','云端账户'])assert.ok(html.includes(localized(key,language)),`${language}: ${key}`);
  assert.ok(html.includes('QA 停车费 &lt;x&gt;'));
  assert.ok(html.includes('qa@example.invalid'));
  assert.ok(html.includes('value="US" selected'));
  assert.ok(html.includes('value="appleMaps" selected'));
  assert.ok(html.includes('name="language_code"'));
  assert.equal(vm.runInContext('JSON.stringify(state.settings)',c),before);
 }
 const c=boot();vm.runInContext(`state.settings={language_code:'en'};`,c);
 assert.equal(c.settingsCurrencyLabel('US','USD','$','美国','美元'),'United States · $ US Dollar (USD)');
});
test('localized settings save keeps storage enums, owner and currency semantics unchanged',async()=>{
 const c=boot();c.saved=[];c.notices=[];
 vm.runInContext(`upsert=async(table,row,key)=>saved.push({table,row,key});showToast=message=>notices.push(message);state.settings={language_code:'zh-Hans',expense_catalog:['停车费']};`,c);
 const form={values:{language_code:'es',currency_country_code:'JP',navigation_provider:'googleMaps'}};
 await c.submitSettings(form);
 assert.equal(c.saved.length,1);
 assert.equal(c.saved[0].row.owner_id,'owner');
 assert.equal(c.saved[0].row.currency_code,'JPY');
 assert.equal(c.saved[0].row.currency_symbol,'¥');
 assert.equal(c.saved[0].row.currency_name,'日元');
 assert.equal(c.saved[0].row.navigation_provider,'googleMaps');
 assert.equal(c.saved[0].row.expense_catalog[0],'停车费');
 assert.equal(c.notices[0],localized('设置已保存。','es'));
});
test('connection badge translates offline and queued counts without changing queued records',()=>{
 const c=boot();c.badge={textContent:'',attrs:{},classes:{},setAttribute(name,value){this.attrs[name]=value},classList:{toggle:(name,value)=>{c.badge.classes[name]=value}}};
 vm.runInContext(`document.querySelector=()=>badge;state.settings={language_code:'en'};queuedOperationCount=()=>2;state.offline=true;renderConnectionStatus();`,c);
 assert.equal(c.badge.textContent,'Offline · Pending sync: 2');
 assert.equal(c.badge.attrs['aria-label'],c.badge.textContent);
 assert.equal(c.badge.classes.offline,true);
 vm.runInContext(`state.offline=false;renderConnectionStatus();`,c);
 assert.equal(c.badge.classes.pending,true);
 assert.equal(c.badge.attrs.title,'Pending sync: 2');
 vm.runInContext(`state.offline=false;queuedOperationCount=()=>0;renderConnectionStatus();`,c);
 assert.equal(c.badge.textContent,'Cloud connected');
});

test('application shell localizes navigation and headings without translating account display names',()=>{
 for(const language of ['zh-Hans','zh-Hant','en','es','ja','ko']){
  const c=boot();c.language=language;c.output={innerHTML:''};
  vm.runInContext(`state.page='settings';state.settings={language_code:language,currency_country_code:'US',expense_catalog:[]};state.user.user_metadata={salutation:'原文 QA'};document.getElementById=()=>output;`,c);
  c.productionRenderApp();
  for(const key of ['总览','行程','客户','名片','旅行社','财务','设置','工作台','账户偏好和本位币','刷新'])assert.ok(c.output.innerHTML.includes(localized(key,language)),`${language}: ${key}`);
  assert.ok(c.output.innerHTML.includes('原文 QA'));
  const header=c.output.innerHTML.split('<header')[1].split('</header>')[0];
  assert.ok(header.includes('class="topbar-user"'));
  assert.ok(header.includes('原文 QA'));
  assert.ok(header.includes('rectangle.portrait.and.arrow.right'));
  assert.ok(header.includes(`aria-label="${localized('退出登录',language)}"`));
  assert.ok(!c.output.innerHTML.split('</aside>')[0].includes('原文 QA'));
  assert.ok(c.output.innerHTML.includes('data-page="wallet"'));
  assert.equal(c.document.documentElement.lang,language);
 }
});

test('ordinary logout releases this device before revoking only its session',async()=>{
 const c=boot();c.calls=[];
 vm.runInContext(`renderLogin=()=>{};request=async(path,options)=>{calls.push({path,...options});};`,c);
 const device=vm.runInContext('accountDeviceID()',c);
 await vm.runInContext('logout()',c);
 assert.equal(c.calls[0].path,'rpc/release_account_device');
 assert.equal(c.calls[0].body.p_device_id,device);
 assert.equal(c.calls[0].queueOffline,false);
 assert.equal(c.calls[1].path,'/auth/v1/logout');
 assert.equal(c.calls[1].query.scope,'local');
 assert.equal(vm.runInContext('state.user',c),null);
});
test('failed device release still revokes only current session and clears local workspace',async()=>{
 const c=boot();c.calls=[];
 vm.runInContext(`renderLogin=()=>{};request=async(path,options)=>{calls.push({path,...options});if(path==='rpc/release_account_device')throw Error('offline');};state.trips=[{id:'private-demo'}];`,c);
 await vm.runInContext('logout()',c);
 assert.equal(c.calls[1].query.scope,'local');
 assert.equal(vm.runInContext('state.trips.length',c),0);
 assert.equal(vm.runInContext('state.session',c),null);
});

test('financial snapshot summary shows net income including tip and signed adjustments',()=>{
 const c=boot();vm.runInContext(`showModal=(title,html)=>{globalThis.snapshotHTML=html;};state.trips=[{id:'qa-net',appointment_date:'2026-11-10T12:00:00Z',appointment_time:'2026-11-10T08:00:00Z',customer_name:'Net QA',price:90,tip:10,expenses:[{title:'Extra',amount:5,is_addition:true},{title:'Parking',amount:8,is_addition:false}]}];openFinanceSnapshots('2026-11-10T00:00:00Z','2026-11-11T00:00:00Z');`,c);
 const html=vm.runInContext('snapshotHTML',c);assert.match(html.split('</summary>')[0],/97\.00/);assert.doesNotMatch(html.split('</summary>')[0],/90\.00/);
});
test('trip contact dropdown and detail expose SMS and telephone for typed phone only',()=>{
 const c=boot();vm.runInContext(`state.customers=[{id:'qa'}];state.contacts=[{customer_id:'qa',contact_type:'微信',value:'12345678'},{customer_id:'qa',contact_type:'电话',value:'+1 (555) 000-0100'}];`,c);
 const html=vm.runInContext(`tripContactActionsHTML({customer_id:'qa',customer_contact:'WeChat-QA'})`,c);
 assert.match(html,/href="sms:\+15550000100"/);assert.match(html,/href="tel:\+15550000100"/);assert.doesNotMatch(html,/12345678|WeChat-QA/);assert.match(html,/data-symbol="phone.fill"/);assert.match(html,/data-symbol="message.fill"/);
});

test('detail contact shows phone once with actions and preserves other contact text',()=>{
 const c=boot();
 vm.runInContext(`state.customers=[{id:'qa'}];state.contacts=[{customer_id:'qa',contact_type:'电话',value:'+1 (555) 000-0100'}];`,c);
 const html=vm.runInContext(`tripDetailContactHTML({customer_id:'qa',customer_contact:'+15550000100'})`,c);
 assert.equal((html.match(/<span>\+1 \(555\) 000-0100<\/span>/g)||[]).length,1);
 assert.doesNotMatch(html,/<strong>/);
 assert.match(html,/href="sms:\+15550000100"/);assert.match(html,/href="tel:\+15550000100"/);
 const mixed=vm.runInContext(`tripDetailContactHTML({customer_id:'qa',customer_contact:'WeChat-QA'})`,c);
 assert.match(mixed,/<strong>WeChat-QA<\/strong>/);assert.match(mixed,/href="tel:/);
 const empty=vm.runInContext(`tripDetailContactHTML({customer_contact:''})`,c);
 assert.match(empty,/未填写/);
});

test('home next-trip card uses earliest eligible trip and escapes customer and route text',()=>{
 const c=boot();
 vm.runInContext(`state.trips=[
 {id:'later',customer_name:'Later',appointment_date:'2099-01-02T12:00:00Z',appointment_time:'2099-01-02T12:00:00Z'},
 {id:'cancelled',customer_name:'Cancelled',is_cancelled:true,appointment_date:'2099-01-01T08:00:00Z'},
 {id:'completed',customer_name:'Completed',is_completed:true,appointment_date:'2099-01-01T09:00:00Z'},
 {id:'earliest',customer_name:'<script>QA</script>',location_start:'<img src=x>',location_end:'A & B',appointment_date:'2099-01-01T12:00:00Z',appointment_time:'2099-01-01T12:00:00Z'}
 ];`,c);
 const html=vm.runInContext('renderHome()',c),side=html.slice(html.indexOf('<aside class="panel home-next-trip"'));
 assert.ok(side.includes('data-id="earliest"'));
 assert.ok(side.includes('&lt;script&gt;QA&lt;/script&gt;'));
 assert.ok(side.includes('&lt;img src=x&gt;'));
 assert.ok(side.includes('A &amp; B'));
 assert.ok(!side.includes('data-id="cancelled"'));
 assert.ok(!side.includes('data-id="completed"'));
 assert.ok(!side.includes('data-id="later"'));
});
test('empty home retains new-trip action without a fabricated next-trip card',()=>{
 const c=boot();vm.runInContext('state.trips=[]',c);
 const html=vm.runInContext('renderHome()',c);
 assert.ok(html.includes('data-action="new-trip"'));
 assert.ok(!html.includes('<aside class="panel home-next-trip"'));
});

test('flight result follows language and provider status without fabricating scheduled state',()=>{
 const c=boot();vm.runInContext("state.settings={language_code:'en'}",c);
 const html=vm.runInContext(`flightResultHTML('BR15',{airlineName:'长荣航空股份有限公司',departureAirport:'TPE',arrivalAirport:'LAX',status:'延误'})`,c);
 assert.match(html,/EVA Air/);assert.match(html,/Delayed/);assert.match(html,/Departure Time/);assert.match(html,/Los Angeles International Airport \(LAX\)/);
 assert.doesNotMatch(html,/>计划</);
 assert.match(vm.runInContext("flightResultHTML('BR15',{})",c),/Status unavailable/);
 vm.runInContext("state.settings.language_code='ja'",c);
 assert.match(vm.runInContext("flightResultHTML('BR15',{status:'落地'})",c),/到着済み/);
});

test('finance expanded snapshot uses the same flight result as a read-only trip card',()=>{
 const c=boot();c.trip={id:'finance-flight',appointment_date:'2026-11-16T20:00:00Z',appointment_time:'2026-11-16T20:00:00Z',flight_info:'BR15',flight_date:'2026-11-16',service_type:'接机',location_start:'LAX',location_end:'QA Hotel',price:100,is_completed:true,is_paid:true,expenses:[],flight_selection_snapshot:parity.makeFlightSnapshot('BR15','2026-11-16',{airlineName:'EVA Air',departureAirport:'TPE',arrivalAirport:'LAX',departureTime:'2026-11-16 13:50:00',estimatedArrivalTime:'2026-11-16 16:35:00',status:'落地'})};
 vm.runInContext(`state.trips=[trip];showModal=(title,html)=>{globalThis.snapshotHTML=html};openFinanceSnapshots('2026-11-16','2026-11-17')`,c);
 const flightHTML=vm.runInContext('flightDetailsHTML(trip)',c);
 assert.ok(c.snapshotHTML.includes(flightHTML));assert.match(c.snapshotHTML,/app-flight-schedule/);assert.match(c.snapshotHTML,/13:50/);assert.match(c.snapshotHTML,/已落地/);
 assert.doesNotMatch(c.snapshotHTML,/data-action="(?:refresh-flight|edit-trip|delete-trip)"/);
});

test('statement share creates one PDF file directly and cancel does not download extra files',async()=>{
 const c=boot();c.files=[];c.downloads=[];
 c.File=class extends Blob {constructor(parts,name,options){super(parts,options);this.name=name;}};
 vm.runInContext(`statementOwner='owner';statementSnapshot={title:'QA statement',headers:['日期','行程','合计'],rows:Array.from({length:20},()=>['2026-11-16','QA route','$100.00']),totals:{USD:2000}};
 navigator.canShare=()=>true;navigator.share=async({files})=>{globalThis.shared=files;const error=new Error('cancel');error.name='AbortError';throw error;};
 document.createElement=tag=>tag==='canvas'?{width:0,height:0,getContext:()=>({measureText:v=>({width:String(v).length*8}),scale(){},fillRect(){},fillText(){},beginPath(){},moveTo(){},lineTo(){},stroke(){}}),toDataURL:()=>'data:image/jpeg;base64,/9j/2Q=='}:{click:()=>downloads.push('download')};`,c);
 await vm.runInContext('shareAgencyStatement()',c);
 assert.equal(c.shared.length,1);assert.equal(c.shared[0].type,'application/pdf');assert.match(c.shared[0].name,/\.pdf$/);
 assert.match(await c.shared[0].text(),/^%PDF-1.4/);assert.equal(c.downloads.length,0);
});
test('payment QR has an explicit share action only when an image is available',()=>{
 const c=boot();vm.runInContext(`state.paymentMethods=[{id:'with',name:'QA',qrImageData:'AQ=='},{id:'without',name:'Empty'}]`,c);
 const html=vm.runInContext('renderPaymentMethods()',c);assert.match(html,/data-action="share-qr" data-kind="payment" data-id="with"/);
 assert.doesNotMatch(html,/data-action="share-qr" data-kind="payment" data-id="without"/);
});

test('trip periods default to all with current-day anchor; quick ranges compose with search and status',()=>{
 const c=boot();
 assert.equal(vm.runInContext('state.tripDateMode',c),'all');
 c.fixture=[
  {id:'a',appointment_date:'2026-11-16T12:00:00',customer_name:'QA guest',is_completed:false,is_paid:false},
  {id:'b',appointment_date:'2026-11-22T12:00:00',customer_name:'QA guest',is_completed:true,is_paid:false},
  {id:'c',appointment_date:'2026-11-23T12:00:00',customer_name:'QA guest',is_paid:true},
  {id:'d',appointment_date:'2026-12-01T12:00:00',customer_name:'QA guest'},
  {id:'e',appointment_date:'2027-01-01T12:00:00',customer_name:'QA guest'}
 ];
 vm.runInContext(`state.trips=fixture;state.tripPeriodAnchor=new Date(2026,10,16);`,c);
 const ids=()=>Array.from(vm.runInContext('filteredTrips().map(t=>t.id)',c)).sort();
 assert.deepEqual(ids(),['a','b','c','d','e']);
 vm.runInContext(`state.tripDateMode='day'`,c);assert.deepEqual(ids(),['a']);
 vm.runInContext(`state.tripDateMode='week'`,c);assert.deepEqual(ids(),['a','b']);
 vm.runInContext(`state.tripFilter='pending'`,c);assert.deepEqual(ids(),['a']);
 vm.runInContext(`state.tripFilter='all';state.tripDateMode='month'`,c);assert.deepEqual(ids(),['a','b','c']);
 vm.runInContext(`state.tripDateMode='year'`,c);assert.deepEqual(ids(),['a','b','c','d']);
 vm.runInContext(`state.search='missing'`,c);assert.deepEqual(ids(),[]);
 vm.runInContext(`state.search='QA';state.tripFilter='unpaid'`,c);assert.deepEqual(ids(),['a','b','d']);
});
test('trip calendar ranges cross years, include leap day, and exclude the next boundary',()=>{
 const c=boot();
 const parts=expr=>Array.from(vm.runInContext(expr,c));
 assert.deepEqual(parts(`(()=>{const r=tripPeriodInterval('week',new Date(2027,0,3));return [r.start.getFullYear(),r.start.getMonth(),r.start.getDate(),r.end.getFullYear(),r.end.getMonth(),r.end.getDate()]})()`),[2026,11,28,2027,0,4]);
 assert.deepEqual(parts(`(()=>{const r=tripPeriodInterval('month',new Date(2028,1,29));return [r.start.getDate(),r.end.getMonth(),r.end.getDate()]})()`),[1,2,1]);
});
test('trip period actions reset to current period, navigate, and preserve status/search without changing Home',async()=>{
 const c=boot();vm.runInContext(`updatePageContent=()=>{};state.homeDate='2026-10-01';state.tripFilter='unpaid';state.search='QA';`,c);
 const click=async dataset=>c.listeners.click({target:{closest:s=>s==='[data-action]'?{dataset}:null}});
 await click({action:'trip-date-mode',mode:'month'});
 assert.equal(vm.runInContext('state.tripDateMode',c),'month');
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),vm.runInContext('dateInput(new Date())',c));
 vm.runInContext(`state.tripPeriodAnchor=new Date(2028,0,31)`,c);
 await click({action:'trip-period-shift',step:'1'});
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),'2028-02-29');
 assert.equal(vm.runInContext('state.tripFilter',c),'unpaid');assert.equal(vm.runInContext('state.search',c),'QA');
 assert.equal(vm.runInContext('state.homeDate',c),'2026-10-01');
});

test('Existing All entry clears quick ranges and keeps today as its date anchor',async()=>{
 const c=boot();vm.runInContext(`updatePageContent=()=>{};state.tripDateMode='month';state.tripPeriodAnchor=new Date(2020,0,1);`,c);
 await c.listeners.click({target:{closest:s=>s==='[data-action]'?{dataset:{action:'trip-filter',filter:'all'}}:null}});
 assert.equal(vm.runInContext('state.tripDateMode',c),'all');
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),vm.runInContext('dateInput(new Date())',c));
 assert.doesNotMatch(vm.runInContext('renderTripPeriodSelector()',c),/data-mode="all"/);
});

test('original date strip remains above list and a date click activates a single-day range',async()=>{
 const c=boot();vm.runInContext(`updatePageContent=()=>{};state.page='trips';state.trips=[];`,c);
 const html=vm.runInContext('renderTrips()',c);
 assert.match(html,/data-trip-calendar/);assert.match(html,/data-action="trip-date"/);
 assert.ok(html.indexOf('data-trip-calendar')<html.indexOf('data-search="trips"'));
 assert.doesNotMatch(vm.runInContext('renderTripPeriodSelector()',c),/data-mode="all"/);
 await c.listeners.click({target:{closest:s=>s==='[data-action]'?{dataset:{action:'trip-date',date:'2026-12-01'}}:null}});
 assert.equal(vm.runInContext('state.tripDateMode',c),'day');
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),'2026-12-01');
 await c.listeners.click({target:{closest:s=>s==='[data-action]'?{dataset:{action:'trip-date-mode',mode:'month'}}:null}});
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),'2026-12-01');
});

test('date navigator and original date cards both remain; arrows apply the active quick period',async()=>{
 const c=boot();vm.runInContext(`updatePageContent=()=>{};state.page='trips';state.trips=[];state.tripPeriodAnchor=new Date(2026,10,16);`,c);
 const html=vm.runInContext('renderTrips()',c);
 assert.match(html,/data-trip-date-navigator/);assert.match(html,/data-trip-calendar/);
 assert.ok(html.indexOf('data-trip-date-navigator')<html.indexOf('data-trip-calendar'));
 const click=async data=>c.listeners.click({target:{closest:s=>s==='[data-action]'?{dataset:data}:null}});
 await click({action:'trip-period-shift',step:'1'});
 assert.equal(vm.runInContext('state.tripDateMode',c),'day');
 assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),'2026-11-17');
 for(const [period,expected] of [['week','2026-11-24'],['month','2026-12-24'],['year','2027-12-24']]){
  await click({action:'trip-date-mode',mode:period});await click({action:'trip-period-shift',step:'1'});
  assert.equal(vm.runInContext('dateInput(state.tripPeriodAnchor)',c),expected);
 }
 await click({action:'trip-filter',filter:'all'});
 assert.equal(vm.runInContext('state.tripDateMode',c),'all');
});

test('business card preview hides registered name, uses nickname fallback and retains image tools',()=>{
 const c=boot();
 vm.runInContext(`state.user={id:'owner',email:'long.address@example.com',user_metadata:{salutation:'PRIVATE REAL NAME',phone:'555'}};state.businessCard={nickname:' ',style:1,qrCodes:[{id:'q',name:'Keep image',imageData:null}]}`,c);
 const html=vm.runInContext('renderBusinessCard()',c);
 const preview=html.slice(html.indexOf('class="business-card-preview'));
 assert.ok(preview.includes('请填写昵称'));
 assert.ok(!preview.includes('PRIVATE REAL NAME'));
 assert.ok(preview.includes('long.address@example.com'));
 assert.ok(html.includes('data-action="save-card-image"'));
 assert.ok(html.includes('data-action="share-card-image"'));
 assert.ok(html.includes('data-action="add-card-qr"'));
 assert.ok(html.includes('data-card-qr-name="q"'));
 assert.ok(html.includes('<h2>其他资料</h2>'));
});

test('card PNG export wraps full email and never draws registered name',async()=>{
 const c=boot(),drawn=[];let download=false;
 c.drawn=drawn;c.ctx={font:'',measureText:t=>({width:t.length*25}),createLinearGradient:()=>({addColorStop(){}}),fillRect(){},fillText:t=>drawn.push(t)};
 c.canvas={width:0,height:0,getContext:()=>c.ctx,toBlob:fn=>fn(new Blob(['image'],{type:'image/png'}))};
 c.document.createElement=tag=>tag==='canvas'?c.canvas:{click(){download=true}};
 c.URL={createObjectURL:()=> 'blob:card',revokeObjectURL(){}};c.File=class{constructor(parts,name,options){this.name=name;this.type=options.type}};
 vm.runInContext(`state.user={id:'owner',email:'very.long.complete.email.address.for.wrapping@example.com',user_metadata:{salutation:'PRIVATE REAL NAME',phone:'555'}};state.businessCard={nickname:'Card nickname',style:1};`,c);
 await vm.runInContext('exportBusinessCardImage(false)',c);
 assert.equal(download,true);
 assert.ok(!drawn.includes('PRIVATE REAL NAME'));
 assert.ok(drawn.includes('Card nickname'));
 assert.ok(drawn.join('').includes('very.long.complete.email.address.for.wrapping@example.com'));
 assert.ok(c.canvas.height>=670);
});

test('customer history rows show net income including tips and both expense directions',()=>{
 const c=boot();vm.runInContext(`state.customers=[{id:'qa',name:'QA'}];state.trips=[{id:'net',customer_id:'qa',customer_name:'QA',appointment_date:'2026-11-17',appointment_time:'2026-11-17T12:00:00Z',price:100,tip:20,expenses:[{is_addition:true,amount:10},{is_addition:false,amount:25}]}];showModal=(title,html)=>{globalThis.customerHTML=html;};openCustomerDetail(state.customers[0]);`,c);
 assert.match(c.customerHTML,/<small>净收入<\/small><strong>[^<]*105\.00/);
 assert.doesNotMatch(c.customerHTML,/<small>车费<\/small>/);
});

test('agency initials appear beside service type in live and finance snapshot cards only for agency orders', () => {
  const c = boot();
  c.trip = {id:'qa', service_type:'接机', order_source:'旅行社订单', travel_agency_name:' 云盛 & 合作'};
  for (const options of ['{}','{readOnly:true}']) {
    const html = vm.runInContext(`renderTripCard(trip,${options})`,c);
    assert.match(html, /接机<span class="trip-agency-badge"[^>]*>云<\/span>/);
    assert.match(html, /云盛 &amp; 合作/);
  }
  c.trip.order_source = '普通客户';
  assert.doesNotMatch(vm.runInContext('renderTripCard(trip)', c), /trip-agency-badge/);
});

test('automatic flight settings save independently; invalid minutes cause no write', async () => {
  const c = boot();
  c.calls = [];
  c.form = {values:{flight_international:'70', flight_domestic:'42', flight_followup:'4'}};
  vm.runInContext(`request=async(path,options)=>{calls.push({path,...options}); return {international:70,domestic:42,followup:4};};`,c);
  await vm.runInContext('submitFlightAutoSettings(form)',c);
  assert.equal(c.calls.length,1);
  assert.equal(c.calls[0].path,'rpc/flight_auto_preferences');
  assert.equal(c.calls[0].queueOffline,false);
  assert.equal(vm.runInContext('state.settings.flight_followup_delay',c),4);
  c.form.values.flight_followup = '';
  await assert.rejects(vm.runInContext('submitFlightAutoSettings(form)',c));
  assert.equal(c.calls.length,1);
});

test('a forced refresh makes one upstream lookup for the selected flight leg', async () => {
  const c = boot();
  c.calls = [];
  c.trip = {flight_info:'JX2',flight_date:'2026-11-25',service_type:'接机',location_start:'LAX',
    flight_selection_snapshot:parity.makeFlightSnapshot('JX2','2026-11-25',
      {departureAirport:'TPE',arrivalAirport:'LAX',departureAirportCode:'TPE',arrivalAirportCode:'LAX'})};
  vm.runInContext(`queryFlights=async(...args)=>{calls.push(args);return [{departureAirport:'TPE',arrivalAirport:'LAX'}];};`,c);
  await vm.runInContext("queryTripFlights('JX2','2026-11-25',trip,{forceRefresh:true})",c);
  assert.equal(c.calls.length,1);
  assert.equal(c.calls[0][2].arrivalAirport,'LAX');
  assert.equal(c.calls[0][2].departureAirport,'TPE');
  assert.equal(c.calls[0][3],true);
});
