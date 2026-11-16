// Shared-domain rules matching the iOS client. No network or account state.
export const LA = 'America/Los_Angeles';
export function partsInZone(value, zone = LA) {
  return Object.fromEntries(new Intl.DateTimeFormat('en-CA', {timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date(value)).filter(x=>x.type!=='literal').map(x=>[x.type,x.value]));
}
export function zonedISO(day, clock = '00:00', zone = LA) {
  const target = `${day}T${clock}:00`;
  let guess = Date.parse(`${target}Z`);
  if (!Number.isFinite(guess)) throw Error('日期或时间无效。');
  for(let i=0;i<4;i++) {
    const p=partsInZone(guess,zone);
    const delta=Date.parse(`${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}Z`)-Date.parse(`${target}Z`);
    if(!delta) return new Date(guess).toISOString();
    guess-=delta;
  }
  throw Error('该日期或时间不存在，请检查夏令时。');
}
export function laDay(now = new Date()) {const p=partsInZone(now);return `${p.year}-${p.month}-${p.day}`;}
const agencyAliases = new Set(['途风','途风旅行','途风旅游','途风旅行社','tours4fun','途风tours4fun','tours4fun途风','途风旅游tours4fun','tours4fun途风旅游','途风旅行社tours4fun','tours4fun途风旅行社','途风旅行tours4fun','tours4fun途风旅行']);
export function isTours4Fun(name) {return agencyAliases.has(String(name||'').normalize('NFKC').toLowerCase().replaceAll('風','风').replaceAll('遊','游').replace(/[^\p{L}\p{N}]/gu,''));}
export function matchPickupAgency(agencies) {const found=agencies.filter(a=>!a.deleted_at && isTours4Fun(a.name)&&a.agency_code?.trim());return found.length===1 ? found[0] : null;}
export function pickupReminders(iso, now = new Date()) {
  const pickup=new Date(iso), p=partsInZone(pickup);
  const prev=new Date(`${p.year}-${p.month}-${p.day}T12:00:00Z`);prev.setUTCDate(prev.getUTCDate()-1);
  let previousDay;try {previousDay=new Date(zonedISO(prev.toISOString().slice(0,10),`${p.hour}:${p.minute}`));}catch {/* Skip a nonexistent previous-day clock during the spring DST transition. */}
  const preferred=[...(previousDay?[previousDay]:[]), ...[120,60,30,15,5,1].map(m=>new Date(+pickup-m*60000)),new Date(Math.floor(+now/60000)*60000+60000),new Date(Math.floor(+pickup/60000)*60000-60000)];
  const dates=[];
  for(const value of preferred){const t=Math.floor(+value/60000)*60000;if(t>+now&&t<+pickup&&!dates.includes(t))dates.push(t);if(dates.length===2)return dates.sort((a,b)=>a-b).map(t=>new Date(t).toISOString());}
  return [];
}
export function recognizePickup(raw, now = new Date()) {
  const text=raw.replaceAll('\u00a0',' ').replaceAll('\r\n','\n');
  const get=(labels)=>text.match(new RegExp(`(?:${labels})[^\\S\\r\\n]*[：:][^\\S\\r\\n]*([^\\r\\n]+)`,'i'))?.[1]?.trim();
  const number=text.match(/(?:订单号|訂單號)\s*[：:]\s*(C-\d+-US)\b/i)?.[1];
  const dateLine=get('接机日期|接機日期'),flight=text.match(/(?:航班号|航班號)\s*[：:]\s*([A-Z0-9]{2}\s*\d{1,4})\b/i)?.[1],airport=text.match(/(?:抵达机场|抵達機場)\s*[：:]\s*([A-Z]{3})\b/i)?.[1];
  const guest=get('联络人|聯絡人|联系人|聯繫人'),addressLine=get('客人地址'),type=get('类型|類型');
  if(!number||!dateLine||!flight||airport?.toUpperCase()!=='LAX'||!guest||!addressLine||(type&&!/^(接机|接機)/.test(type)))throw Error('请粘贴完整的途风 LAX 接机订单（订单号、日期、航班、联系人和地址）。');
  const end=dateLine.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?=$|[\s，,;；])/);
  const start=dateLine.match(/^(?:(\d{4})[年/.-])?(\d{1,2})[月/.-](\d{1,2})(?:日)?(?=$|[\s，,;；])/);
  const [explicit,month,day]=end?[end[3],end[1],end[2]]:start?start.slice(1):[];
  const today=laDay(now),md=`${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
  const year=explicit?Number(explicit):Number(today.slice(0,4))+(md<today.slice(5)?1:0);
  const date=`${year}-${md}`;
  if(!month||!day||!Number.isFinite(Date.parse(`${date}T12:00Z`))||new Date(`${date}T12:00Z`).toISOString().slice(0,10)!==date)throw Error('订单接机日期无效，请修改后重试。');
  const tm=text.match(/(?:接机时间|接機時間|抵达时间|抵達時間)[^\S\r\n]*[：:][^\S\r\n]*[^\d\r\n]{0,12}(\d{1,2})[:：](\d{2})(?!\d)/);
  if(!tm||+tm[1]>23||+tm[2]>59)throw Error('订单预计抵达时间无效，请修改后重试。');
  const time=`${tm[1].padStart(2,'0')}:${tm[2]}`,iso=zonedISO(date,time);
  const phoneText=get('联络电话|聯絡電話|联系电话|聯繫電話')?.match(/^\+?\d[\d ()（）-]*/)?.[0]||'',digits=phoneText.replace(/\D/g,'');
  const address=addressLine.match(/^(.*?)\s*(?:住址|地址)\s*[：:]\s*(.+)$/);
  return {number:number.toUpperCase(),date,time,iso,inferredYear:!explicit,flight:flight.replaceAll(' ','').toUpperCase(),airport:'LAX',contact:guest.split(/[（(]/)[0].trim(),phone:digits?((phoneText.startsWith('+')||digits.startsWith('886')?'+':'')+digits):'',passengers:text.match(/(?:人数|人數)\s*[：:]\s*(\d+)\s*人/)?.[1]||guest.match(/[（(]\s*(\d+)\s*人/)?.[1]||'',luggage:text.match(/(\d+)\s*件\s*行李/)?.[1]||'',destination:address?[address[1],address[2]].filter(Boolean).join(', '):addressLine,reminders:pickupReminders(iso,now),rawText:raw};
}
const aliases={
 status:["flightstate","flightstatus","status","航班状态","航班狀態"],
 airlineName:['airline','airlinename','carrier','carriername','airlinetitle','flightcompany'],
 departureAirport:['departureairport','departureairportname','depairport','depairportname','departurestation','depname','dep','flightdept','起飞机场','出发机场','origin','from'],
 arrivalAirport:['arrivalairport','arrivalairportname','arrairport','arrairportname','arrivalstation','arrname','arr','flightarr','到达机场','目的机场','destination','to'],
 departureTime:['flightdeptimeplandate','flightdeptimereadydate','departuretime','departuredatetime','scheduleddeparture','scheduleddeparturetime','std','deptime','depttime'],
 estimatedArrivalTime:['flightarrtimeplandate','flightarrtimereadydate','estimatedarrivaltime','arrivalestimatedtime','arrivaldatetime','arrivaltime','scheduledarrival','scheduledarrivaltime','sta','eta','arrtime'],
 departureTerminal:['flighthterminal','flightdeptterminal','flightdeptterminalname','departureterminal','departureterminalname','depterminal','depterminalname','deptterminal','terminaldeparture','terminal','出发航站楼','起飞航站楼'],
 arrivalTerminal:['flightterminal','flightarrterminal','flightarrterminalname','arrivalterminal','arrivalterminalname','arrterminal','arrterminalname','terminalarrival','terminalarr','arriveterminal','到达航站楼','到达航站区'],
 baggageCarousel:['baggagecarousel','flightarrbaggagecarousel','carousel','baggageclaim','baggageclaimbelt','luggagecarousel']
};
const fieldFor=new Map(Object.entries(aliases).flatMap(([field,names])=>names.map(n=>[n,field])));
const normalizedKey=k=>k.toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
export function flightID(f){return [f.airlineName,f.departureAirport,f.arrivalAirport,f.departureTime,f.estimatedArrivalTime].map(x=>(x||'').trim().toLowerCase()).join('|');}
export function parseFlights(payload) {
  function extract(v){
    if(typeof v==='string'){
      try{return extract(JSON.parse(v));}catch{}
      const fields={};for(const [field,names] of Object.entries(aliases)){const regex=new RegExp(`(?<![A-Za-z])(?:${names.sort((a,b)=>b.length-a.length).join('|')})["']?\\s*[:：]\\s*["']?([^"'\\n,，;；}]+)`,'i');const match=v.match(regex);if(match)fields[field]=match[1].trim();}
      return fields.departureAirport||fields.arrivalAirport||fields.departureTime||fields.estimatedArrivalTime?[fields]:[];
    }
    if(Array.isArray(v))return v.flatMap(extract);
    if(!v||typeof v!=='object')return [];
    if(v.isError||v.error)throw Error(typeof v.error==='string'?v.error:'航班服务返回错误，请稍后重试。');
    const explicitLegs=Object.entries(v).filter(([k,c])=>Array.isArray(c)&&/flight|leg|segment|航段/i.test(k)).flatMap(([,c])=>extract(c));
    if(explicitLegs.length)return explicitLegs;
    const nested=Object.values(v).filter(c=>c&&typeof c==='object'||typeof c==='string'&&/^[\[{]/.test(c.trim())).flatMap(extract);
    // MCP text blocks are wrappers, not records.
    if(!nested.length&&Array.isArray(v.content))return v.content.flatMap(c=>extract(c.text||''));
    if(nested.length)return nested;
    if(v.type==='text'&&typeof v.text==='string')return extract(v.text);
    const fields={};for(const [k,value]of Object.entries(v)){const field=fieldFor.get(normalizedKey(k));if(!field)continue;if(typeof value==='string'&&value.trim())fields[field]=value.trim();else if(field.endsWith('Terminal')&&Number.isInteger(value)&&value>=0)fields[field]=String(value);}
    return fields.departureAirport||fields.arrivalAirport||fields.departureTime||fields.estimatedArrivalTime||fields.airlineName?[fields]:[];
  }
  const unique=new Map();for(const f of extract(payload)){const id=flightID(f);unique.set(id,{...unique.get(id),...f});}return [...unique.values()];
}
export function makeFlightSnapshot(number,date,selected,now=new Date()){return {flightNumber:number.trim().toUpperCase(),flightDate:date,selected,fetchedAt:+now/1000-978307200,formatVersion:2};}
export function airportCodes(label,airports=[]){
  const original=String(label||'').normalize('NFKC').trim();
  if(/^[A-Za-z]{3}$/.test(original))return new Set([original.toUpperCase()]);
  const text=original.toLowerCase();
  const explicit=(String(label||'').trim().match(/^[A-Za-z]{3}$/) || String(label||'').match(/\b[A-Z]{3}\b/g))?.map(x=>x.toUpperCase()).filter(x=>['LAX','IAH','TPE','SFO','JFK','EWR','LGA','HOU','ONT','SNA','BUR','LGB'].includes(x)||airports.some(a=>a.iata_code===x))||[];
  if(explicit.length)return new Set(explicit);
  const common=[[/洛杉矶|洛杉磯|los angeles/,'LAX'],[/乔治布什|喬治布什|george bush/,'IAH'],[/台北|臺北|桃园|桃園|taoyuan/,'TPE'],[/旧金山|舊金山|san francisco/,'SFO']];
  const hits=common.filter(([r])=>r.test(text)).map(([,code])=>code);
  const matches=airports.flatMap(a=>[a.name,a.municipality,...a.keywords||[]].filter(n=>n&&text.includes(n.toLowerCase())).map(n=>({length:n.length,code:a.iata_code})));
  const longest=Math.max(0,...matches.map(m=>m.length));
  return new Set(longest?matches.filter(m=>m.length===longest).map(m=>m.code):hits);
}
export function routeMatches(f,trip,airports=[]){const label=trip.service_type==='接机'?trip.location_start:trip.service_type==='送机'?trip.location_end:'';const streetAddress=/\d/.test(label||'')&&!/airport|terminal|机场|機場|航站/i.test(label||'')&&!/^[A-Z]{3}\b/.test(label||'');const expected=streetAddress?new Set():airportCodes(label,airports);if(!expected.size)return true;const actual=airportCodes(trip.service_type==='接机'?f.arrivalAirport:f.departureAirport,airports);return !actual.size||[...actual].some(c=>expected.has(c));}
export function readFlightSnapshot(trip,airports=[]){let s=trip.flight_selection_snapshot;try{if(typeof s==='string')s=JSON.parse(s);}catch{return null;}if(!s||s.formatVersion!==2||s.flightNumber!==String(trip.flight_info||'').trim().toUpperCase()||s.flightDate!==String(trip.flight_date||'').slice(0,10)||!s.selected||!routeMatches(s.selected,trip,airports))return null;return s.selected;}
export function compareTrips(a,b){const clock=v=>{const d=new Date(v);return d.getHours()*3600+d.getMinutes()*60+d.getSeconds();};const day=v=>{const d=new Date(v);d.setHours(0,0,0,0);return +d;};return day(a.appointment_date)-day(b.appointment_date)||clock(a.appointment_time)-clock(b.appointment_time)||Math.floor(Date.parse(a.created_at)/1000)-Math.floor(Date.parse(b.created_at)/1000)||String(a.id).toLowerCase().localeCompare(String(b.id).toLowerCase());}
export function settlementPayload(draft){if(!Number.isFinite(draft.price)||!Number.isFinite(draft.tip)||draft.price<0||draft.tip<0||draft.expenses.some(e=>!e.title?.trim()||!Number.isFinite(e.amount)||e.amount<=0))throw Error('费用和小费必须为非负数，每条费用需有名称和正金额。');return {p_trip_id:draft.tripID,p_fare:draft.price,p_tip:draft.tip,p_expenses:draft.expenses.map((e,position)=>({id:e.id,is_addition:!!e.is_addition,title:e.title.trim(),amount:e.amount,position}))};}

// Read-only reconciliation: deliberately independent of financial period filters.
export function agencyStatementTrips(trips, agencyKey) {
  return trips.filter(t => t.order_source === '旅行社订单' && !t.is_paid && !t.is_cancelled && statementAgencyKey(t) === agencyKey)
    .sort((a,b) => String(a.appointment_date).localeCompare(String(b.appointment_date)) || String(a.appointment_time).localeCompare(String(b.appointment_time)) || String(a.id).localeCompare(String(b.id)));
}
export function statementAgencyKey(t) { return t.travel_agency_code ? `code:${t.travel_agency_code}` : `name:${t.travel_agency_name || ''}`; }
export function statementMoney(amount, currency) { return new Intl.NumberFormat('en-US', {style:'currency',currency,minimumFractionDigits:2,maximumFractionDigits:2}).format(amount); }
export function buildAgencyStatement(trips, translate = key => key, language = "en-US") {
  const feeKey = f => String(f.title || '').trim();
  const fees = [...new Set(trips.flatMap(t => (t.expenses || []).map(feeKey)))].sort();
  const totals = {};
  const rows = trips.map(t => {
    const currency = t.currency_code || 'USD';
    const total = Number(t.price || 0) + (t.expenses || []).reduce((n,f) => n + Math.abs(Number(f.amount || 0)),0);
    totals[currency] = (totals[currency] || 0) + total;
    return [new Date(t.appointment_date).toLocaleDateString(language), t.travel_agency_order_number || '', translate(t.service_type), t.customer_name,
      [t.location_start, ...(t.stops || []).map(s => s.address), t.location_end].filter(Boolean).join(' → ') + (t.customer_contact ? `\n${translate('联系方式')}：${t.customer_contact}` : ''),
      t.memo || '', t.customer_count || '', statementMoney(Number(t.price || 0), currency),
      ...fees.map(key => statementMoney((t.expenses || []).filter(f => feeKey(f) === key).reduce((n,f) => n + Math.abs(Number(f.amount || 0)),0), currency)), statementMoney(total, currency)];
  });
  return { headers: [...['日期','订单号','行程类型','客人','行程','备注','人数','团费'].map((key,i) => translate(i === 4 && language !== 'en-US' ? 'statement.route' : key)),...fees,translate('合计')], rows, totals };
}


export function financialCategoryGroups(entries, fallback='其他') {
  const groups=new Map();
  for(const entry of entries) {
    const amount=Math.abs(Number(entry.amount));
    if(!Number.isFinite(amount) || amount<=0.0001) continue;
    const name=String(entry.title || '').normalize('NFC').trim().replace(/\s+/gu,' ') || fallback;
    const row=groups.get(name) || {name,amount:0,incomeAmount:0,expenseAmount:0,expense:false};
    if(entry.isAddition) row.incomeAmount+=amount; else row.expenseAmount+=amount;
    row.amount=row.incomeAmount+row.expenseAmount;row.expense=row.incomeAmount===0 && row.expenseAmount>0;groups.set(name,row);
  }
  return [...groups.values()].sort((a,b)=>Number(a.expense)-Number(b.expense)||b.amount-a.amount||(a.name<b.name?-1:a.name>b.name?1:0));
}

export function telephoneNumber(value) {
  const text = String(value || '').trim();
  if (!text || !/^[0-9+() .-]+$/.test(text)) return null;
  const number = text.replace(/[^0-9+]/g, '');
  const digits = number.replace(/\D/g, '');
  if (digits.length < 6 || digits.length > 20 || (number.match(/\+/g) || []).length > 1 || (number.includes('+') && !number.startsWith('+'))) return null;
  return number;
}
export function tripTelephoneContacts(trip, contacts, customerIDs = []) {
  const linked = trip.customer_id && customerIDs.includes(trip.customer_id);
  const candidates = linked ? contacts.filter(c => c.customer_id === trip.customer_id && ['电话','電話','phone','telephone','tel'].includes(String(c.label || c.contact_type || '').toLowerCase())).map(c => c.value) : [trip.customer_contact];
  const seen = new Set();
  return candidates.filter(value => { const n = telephoneNumber(value); if (!n || seen.has(n)) return false; seen.add(n); return true; }).map(value => String(value).trim());
}

// Presentation only. Keep original provider fields and persisted snapshots unchanged.
const flightNames = [["airport", ["LAX", "洛杉矶", "洛杉磯", "Los Angeles International Airport"], ["洛杉矶国际机场", "洛杉磯國際機場", "Los Angeles International Airport", "Aeropuerto Internacional de Los Ángeles", "ロサンゼルス国際空港", "로스앤젤레스 국제공항"]], ["airport", ["SFO", "旧金山", "舊金山", "San Francisco International Airport"], ["旧金山国际机场", "舊金山國際機場", "San Francisco International Airport", "Aeropuerto Internacional de San Francisco", "サンフランシスコ国際空港", "샌프란시스코 국제공항"]], ["airport", ["TPE", "桃园", "桃園", "台北桃园", "台北桃園", "台湾桃园国际机场", "Taiwan Taoyuan International Airport"], ["台湾桃园国际机场", "臺灣桃園國際機場", "Taiwan Taoyuan International Airport", "Aeropuerto Internacional de Taiwán Taoyuan", "台湾桃園国際空港", "타이완 타오위안 국제공항"]], ["airport", ["HKG", "香港", "香港国际机场", "Hong Kong International Airport"], ["香港国际机场", "香港國際機場", "Hong Kong International Airport", "Aeropuerto Internacional de Hong Kong", "香港国際空港", "홍콩 국제공항"]], ["airport", ["PVG", "浦东", "浦東", "浦东机场", "Shanghai Pudong International Airport"], ["上海浦东国际机场", "上海浦東國際機場", "Shanghai Pudong International Airport", "Aeropuerto Internacional de Shanghái Pudong", "上海浦東国際空港", "상하이 푸둥 국제공항"]], ["airport", ["NRT", "成田", "成田国际机场", "Narita International Airport"], ["成田国际机场", "成田國際機場", "Narita International Airport", "Aeropuerto Internacional de Narita", "成田国際空港", "나리타 국제공항"]], ["airport", ["HND", "羽田", "Tokyo Haneda International Airport", "Tokyo Haneda Airport"], ["东京羽田机场", "東京羽田機場", "Tokyo Haneda Airport", "Aeropuerto de Tokio Haneda", "東京国際空港（羽田）", "도쿄 하네다 공항"]], ["airline", ["BR", "长荣航空", "長榮航空", "长荣航空股份有限公司", "EVA Air"], ["长荣航空", "長榮航空", "EVA Air", "EVA Air", "エバー航空", "에바항공"]], ["airline", ["CI", "中华航空", "中華航空", "China Airlines"], ["中华航空", "中華航空", "China Airlines", "China Airlines", "チャイナ エアライン", "중화항공"]], ["airline", ["CX", "国泰航空", "國泰航空", "香港国泰航空有限公司", "Cathay Pacific"], ["国泰航空", "國泰航空", "Cathay Pacific", "Cathay Pacific", "キャセイパシフィック航空", "캐세이퍼시픽항공"]], ["airline", ["JX", "星宇航空", "STARLUX Airlines"], ["星宇航空", "星宇航空", "STARLUX Airlines", "STARLUX Airlines", "スターラックス航空", "스타룩스항공"]], ["airline", ["UA", "美国联合航空", "美國聯合航空", "United Airlines", "United"], ["美国联合航空", "美國聯合航空", "United Airlines", "United Airlines", "ユナイテッド航空", "유나이티드항공"]], ["airline", ["MU", "中国东方航空", "中國東方航空", "China Eastern Airlines"], ["中国东方航空", "中國東方航空", "China Eastern Airlines", "China Eastern Airlines", "中国東方航空", "중국동방항공"]]];
const flightStatuses = [[["计划", "計劃", "scheduled", "planned"], ["计划", "計劃", "Scheduled", "Programado", "定刻予定", "예정"]], [["延误", "延誤", "delayed", "delay"], ["延误", "延誤", "Delayed", "Retrasado", "遅延", "지연"]], [["起飞", "起飛", "已起飞", "已起飛", "departed", "airborne", "en route", "enroute"], ["已起飞", "已起飛", "Departed", "Despegado", "出発済み", "출발"]], [["到达", "到達", "抵达", "抵達", "落地", "已落地", "arrived", "landed"], ["已落地", "已降落", "Landed", "Aterrizado", "到着済み", "도착"]], [["取消", "已取消", "cancelled", "canceled"], ["已取消", "已取消", "Cancelled", "Cancelado", "欠航", "취소"]], [["备降", "備降", "diverted"], ["备降", "備降", "Diverted", "Desviado", "目的地変更", "회항"]], [["返航", "returned"], ["返航", "返航", "Returned", "Regresado", "引き返し", "귀항"]]];
const unknownFlightStatus = ["状态待确认", "狀態待確認", "Status unavailable", "Estado no disponible", "状況未確認", "상태 미확인"];
function flightLanguageIndex(language) {
 const id=String(language||'en').toLowerCase().replaceAll('_','-');
 if(id.startsWith('zh'))return /hant|tw|hk/.test(id)?1:0;
 return id.startsWith('es')?3:id.startsWith('ja')?4:id.startsWith('ko')?5:2;
}
export function flightDisplayName(raw,kind,language) {
 const original=String(raw||'').trim();if(!original)return '—';
 const match=flightNames.find(([type,aliases,names])=>type===kind&&[...aliases,...names].some(v=>v.toLowerCase()===original.toLowerCase()));
 if(!match)return original;
 const display=match[2][flightLanguageIndex(language)];
 return kind==='airport'?`${display} (${match[1][0]})`:display;
}
export function flightStatusLabel(raw,language) {
 const original=String(raw||'').trim(),value=original.toLowerCase(),index=flightLanguageIndex(language);
 const match=flightStatuses.find(([aliases,names])=>[...aliases,...names].some(v=>v.toLowerCase()===value));
 return match?match[1][index]:(!value||Number.isFinite(Number(value)))?unknownFlightStatus[index]:original;
}
