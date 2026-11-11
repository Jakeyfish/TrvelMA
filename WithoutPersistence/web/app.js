import { localized } from "./localization.mjs?v=20261111-ui-v3";
const uiLanguage = () => normalizedLanguageCode((state.archiveMode ? state.archiveData?.user_settings?.[0]?.language_code : null) || state.settings?.language_code || readInterfaceLanguage());
const ui = (key, ...args) => localized(key, uiLanguage(), ...args);
import { telephoneNumber, tripTelephoneContacts, financialCategoryGroups, statementMoney, agencyStatementTrips, statementAgencyKey, buildAgencyStatement, pickupReminders, recognizePickup, matchPickupAgency, partsInZone, zonedISO, parseFlights, flightID, makeFlightSnapshot, readFlightSnapshot, routeMatches, compareTrips, settlementPayload } from './parity.mjs?v=20261111-ui-v3';
let airportCrosswalk = [];
const airportCrosswalkReady = fetch('./assets/airport-crosswalk.json').then(r => { if (!r.ok) throw Error('机场对照表不可用'); return r.json(); }).then(data => { airportCrosswalk = data.airports; }).catch(() => {});
const SUPABASE_URL = "https://lbdfqzeiweqbsklklcqr.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_d4tmuPirsf8-wUDO0Frd7w_PcXME6rs";
const WEB_BUILD = "20261111-ui-v3";
const SESSION_KEY = "yunsheng.web.session.v1";
const OFFLINE_CACHE_PREFIX = "yunsheng.web.offline-cache.v1.";
const OFFLINE_QUEUE_PREFIX = "yunsheng.web.offline-queue.v1.";
const ACCOUNT_PREFERENCE_PREFIX = "yunsheng.web.account-preference.v1.";
// These legacy keys were shared by every browser account and have no reliable
// owner. Discard them instead of exposing one account's settings to another.
["yunsheng.web.navigation", "yunsheng.web.variflight-key", "yunsheng.web.expense-catalog"]
  .forEach(key => localStorage.removeItem(key));
const WEB_DEVICE_KEY = 'yunsheng.web.device-id.v1';
let deviceAdmission = null;
let deviceAdmissionTask = null;
function accountDeviceID() {
  let value=localStorage.getItem(WEB_DEVICE_KEY);
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value||'')) {
    value=crypto.randomUUID();localStorage.setItem(WEB_DEVICE_KEY,value);
  }
  return value;
}
async function ensureAccountDevice() {
  const ownerID=state.user?.id,generation=workspaceGeneration,id=accountDeviceID();
  if(!ownerID)throw Error('请先登录云端账号。');
  if(deviceAdmission?.ownerID===ownerID&&deviceAdmission.generation===generation&&deviceAdmission.id===id)return;
  if(deviceAdmissionTask?.ownerID===ownerID&&deviceAdmissionTask.generation===generation)return deviceAdmissionTask.promise;
  const task={ownerID,generation,promise:null};
  task.promise=(async()=>{
    try {
      await request('rpc/register_account_device',{method:'POST',body:{p_device_id:id,p_device_type:'Web'},queueOffline:false});
      if(state.user?.id!==ownerID||workspaceGeneration!==generation)throw Error('账号会话已变化，请重新加载。');
      deviceAdmission={ownerID,generation,id};
    } finally {if(deviceAdmissionTask===task)deviceAdmissionTask=null;}
  })();
  deviceAdmissionTask=task;
  return task.promise;
}
let workspaceGeneration = 0;
let loadSequence = 0;
let sessionRefreshTask = null;
let offlineReplayTask = null;
let offlineRetryTimer = null;
let offlineRetryCount = 0;
let networkToastShownForCurrentOutage = false;
const webReminderTimers = new Map();

const state = {
  session: readSession(),
  user: null,
  productEdition: "sync",
  entitlementExpiresAt: null,
  archiveMode: false,
  archiveData: null,
  entitlementResolved: false,
  page: "home",
  tripFilter: "all",
  homeDate: "",
  tripDate: "",
  tripDateMode: "seven",
  tripCalendarMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  expandedFlights: new Set(),
  settlementDraft: null,
  search: "",
  customers: [],
  contacts: [],
  addresses: [],
  trips: [],
  agencies: [],
  stops: [],
  expenses: [],
  settings: null,
  paymentMethods: [],
  businessCard: { nickname: "", style: 0, portraitData: null, qrCodes: [] },
  busy: false,
  error: "",
  offline: !navigator.onLine,
};

const pageNames = {
  home: ["总览", "查看近期行程和经营概况"],
  trips: ["行程", "管理接载安排、状态和结算"],
  customers: ["客户", "管理客户资料和出行记录"],
  businessCard: ["名片", "管理名片头像、样式和二维码"],
  agencies: ["旅行社", "管理合作旅行社资料"],
  wallet: ["财务", "查看收入、费用和净收入"],
  settings: ["设置", "账户偏好和本位币"],
};

function readSession() {
  try { return JSON.parse(localStorage.getItem(SESSION_KEY) || "null"); }
  catch { return null; }
}

function writeSession(session) {
  state.session = session;
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
}

function clearSession() {
  state.session = null;
  state.user = null;
  localStorage.removeItem(SESSION_KEY);
  clearTimeout(offlineRetryTimer);
  offlineRetryTimer = null;
  resetAccountWorkspace();
}

function resetAccountWorkspace() {
  workspaceGeneration++;
  loadSequence++;
  deviceAdmission=null;
  deviceAdmissionTask=null;
  for (const timer of webReminderTimers.values()) clearTimeout(timer);
  webReminderTimers.clear();
  state.page = "home";
  state.productEdition = "sync";
  state.entitlementExpiresAt = null;
  state.archiveMode = false;
  state.archiveData = null;
  state.entitlementResolved = false;
  state.customers = [];
  state.contacts = [];
  state.addresses = [];
  state.trips = [];
  state.agencies = [];
  state.stops = [];
  state.expenses = [];
  state.settings = null;
  state.assetImageCache = new Map();
  state.assetReadTokens = {};
  state.pickupPreview = null;
  state.flightPicker = null;
  document.getElementById('modal-root')?.remove();
  document.getElementById('picker-backdrop')?.remove();
  state.paymentMethods = [];
  state.businessCard = { nickname: "", style: 0, portraitData: null, qrCodes: [] };
}

function accountPreferenceKey(name, userID = state.user?.id) {
  return userID ? `${ACCOUNT_PREFERENCE_PREFIX}${userID}.${name}` : null;
}

function getAccountPreference(name, fallback = "") {
  const key = accountPreferenceKey(name);
  return key ? localStorage.getItem(key) ?? fallback : fallback;
}

function setAccountPreference(name, value) {
  const key = accountPreferenceKey(name);
  if (key) localStorage.setItem(key, value);
}

function removeAccountPreference(name) {
  const key = accountPreferenceKey(name);
  if (key) localStorage.removeItem(key);
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>"']/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char]);
}

function apiURL(path, query = {}) {
  const url = new URL(`${SUPABASE_URL}${path}`);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  return url;
}

async function networkFetch(url, options = {}, timeoutMs = 45000) {
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),timeoutMs);
  try {return await fetch(url,{...options,signal:controller.signal});}
  finally {clearTimeout(timer);}
}

async function authRequest(path, body, {method = "POST", accessToken = null} = {}) {
  const response = await networkFetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method,
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json", ...(accessToken ? {Authorization: `Bearer ${accessToken}`} : {}) },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(friendlyError(payload));
    error.status = response.status;
    error.code = payload.code || payload.error_code || payload.error || "";
    throw error;
  }
  networkToastShownForCurrentOutage = false;
  return payload;
}

function friendlyError(payload) {
  const message = payload.msg || payload.message || payload.error_description || payload.error || "连接云端失败，请稍后重试。";
  const lower = String(message).toLowerCase();
  if (String(message).includes('ACCOUNT_DEVICE_LIMIT_REACHED')) return '此账号的设备名额已满，当前浏览器尚未获得数据访问权限。请先在设备管理中释放不再使用的设备；原数据未删除。';
  if (lower.includes("invalid login credentials")) return "邮箱或密码不正确。";
  if (lower.includes("email not confirmed")) return "请先完成邮箱验证，再登录。";
  if (lower.includes("email address not authorized") || lower.includes("error sending confirmation email")) return "验证邮件服务暂未就绪，请稍后重试或联系管理员。";
  if (lower.includes("rate limit")) return "操作过于频繁，请稍后再试。";
  if (lower.includes("failed to fetch")) return "无法连接云端，请检查网络后重试。";
  return String(message);
}

async function currentSession() {
  if (!state.session?.access_token) return null;
  if (state.session.expires_at && Date.now() < state.session.expires_at - 60_000) return state.session;
  if (!state.session.refresh_token) { clearSession(); return null; }
  const sessionBeingRefreshed = state.session;
  if (!sessionRefreshTask) {
    sessionRefreshTask = (async () => {
      try {
        const fresh = await authRequest("token?grant_type=refresh_token", { refresh_token: sessionBeingRefreshed.refresh_token });
        if (state.session !== sessionBeingRefreshed) return state.session;
        writeSession({ ...fresh, expires_at: Date.now() + (fresh.expires_in || 3600) * 1000 });
        return state.session;
      } catch (error) {
        if (state.session !== sessionBeingRefreshed) return state.session;
        if (error instanceof TypeError && state.session?.user) return state.session;
        if (error.status === 429 || error.status >= 500) {
          error.message = "云端暂时无法验证登录状态，离线修改仍保存在本机；请稍后重新同步。";
          throw error;
        }
        const hadQueuedChanges = readOfflineQueue(sessionBeingRefreshed.user?.id).operations.length > 0;
        clearSession();
        state.error = hadQueuedChanges
          ? "云端登录凭证已失效，离线修改仍保存在本机。请重新登录原云端账号，登录后会继续同步。"
          : "云端登录凭证已失效，请重新登录。";
        renderLogin();
        return null;
      } finally {
        sessionRefreshTask = null;
      }
    })();
  }
  return sessionRefreshTask;
}

function offlineQueueKey(userID = state.user?.id) { return `${OFFLINE_QUEUE_PREFIX}${userID || ""}`; }
function offlineCacheKey(userID = state.user?.id) { return `${OFFLINE_CACHE_PREFIX}${userID || ""}`; }
function readOfflineQueue(userID = state.user?.id) {
  if (!userID) return { operations: [], retryCount: 0 };
  try {
    const value = JSON.parse(localStorage.getItem(offlineQueueKey(userID)) || "null");
    if (Array.isArray(value)) return { operations: value, retryCount: 0 };
    return value && Array.isArray(value.operations) ? value : { operations: [], retryCount: 0 };
  } catch { return { operations: [], retryCount: 0 }; }
}

function queuedOperationCount() { return readOfflineQueue().operations.length; }

function renderConnectionStatus() {
  const badge = document.querySelector(".connection");
  if (!badge) return;
  const count = queuedOperationCount();
  const offline = state.offline || !navigator.onLine;
  badge.classList.toggle("offline", offline);
  badge.classList.toggle("pending", !offline && count > 0);
  const pending = count ? ui('%ld 项待同步', count) : '';
  badge.textContent = offline ? ui('离线') + (pending ? ` · ${pending}` : '') : pending || ui('云端已连接');
  badge.setAttribute('title', badge.textContent);
  badge.setAttribute('aria-label', badge.textContent);
}

function writeOfflineCache(snapshot, userID = state.user?.id) {
  if (!userID || state.productEdition === "cloud") return;
  const compact = structuredClone(snapshot);
  const settings = compact.settings?.[0];
  for (const key of ["business_card_data", "wallet_payment_methods"]) {
    const value = settings?.[key];
    if (!value || typeof value !== "object") continue;
    delete value.portraitData;
    for (const item of value.qrCodes || []) delete item.imageData;
    for (const item of value.methods || []) delete item.qrImageData;
  }
  try { localStorage.setItem(offlineCacheKey(userID), JSON.stringify(compact)); }
  catch { /* Keep the in-memory workspace usable if browser storage is full. */ }
}

function readOfflineCache(userID = state.user?.id) {
  if (!userID) return null;
  try { return JSON.parse(localStorage.getItem(offlineCacheKey(userID)) || "null"); }
  catch { return null; }
}

function matchesQueuedFilters(row, query) {
  return Object.entries(query).every(([key, filter]) => {
    if (["select", "order", "limit", "on_conflict"].includes(key)) return true;
    if (typeof filter !== "string") return String(row[key] ?? "") === String(filter ?? "");
    if (filter.startsWith("eq.")) return String(row[key] ?? "") === filter.slice(3);
    if (filter === "is.null") return row[key] == null;
    return true;
  });
}

function applyQueuedOperation(snapshot, operation) {
  if (['rpc/settle_online_trip','rpc/save_online_trip_finances'].includes(operation.table)) {
    const b = operation.body;
    const trip = snapshot.trips?.find(t => t.id === b.p_trip_id && !t.deleted_at);
    if (trip) {
      Object.assign(trip, { price: b.p_fare, tip: b.p_tip });
      if (operation.table === 'rpc/settle_online_trip') trip.is_paid = true;
      snapshot.expenses = (snapshot.expenses || []).filter(e => e.trip_id !== trip.id);
      snapshot.expenses.push(...b.p_expenses.map(e => ({ ...e, trip_id: trip.id, owner_id: operation.owner_id || trip.owner_id })));
    }
    return;
  }
  const rows = snapshot[operation.table];
  if (!Array.isArray(rows)) return;
  if (operation.method === "POST") {
    const conflictField = operation.query?.on_conflict || "id";
    for (const incoming of (Array.isArray(operation.body) ? operation.body : [operation.body])) {
      if (!incoming || typeof incoming !== "object") continue;
      const index = rows.findIndex(row => row[conflictField] === incoming[conflictField]);
      if (index >= 0) rows[index] = { ...rows[index], ...incoming };
      else rows.push(incoming);
    }
  } else if (operation.method === "PATCH") {
    for (const row of rows) if (matchesQueuedFilters(row, operation.query || {})) Object.assign(row, operation.body || {});
  } else if (operation.method === "DELETE") {
    snapshot[operation.table] = rows.filter(row => !matchesQueuedFilters(row, operation.query || {}));
  }
}

function restoreQueuedStorageImages(snapshot, operations, userID) {
  const settings=snapshot.settings?.[0]; if(!settings)return;
  for(const operation of operations) {
    if(operation.kind!=='storage-upload'||operation.owner_id!==userID)continue;
    const path=operation.path?.replace(/^object\/account-assets\//,'');
    if(!isOwnedAccountAssetPath(path,userID))continue;
    const card=settings.business_card_data;
    if(card?.portraitPath===path)card.portraitData=operation.base64;
    for(const qr of card?.qrCodes||[])if(qr.imagePath===path)qr.imageData=operation.base64;
    for(const method of settings.wallet_payment_methods?.methods||[])if(method.qrImagePath===path)method.qrImageData=operation.base64;
  }
}

function persistOfflineOperation(operation, userID = state.user?.id) {
  if (state.productEdition === "cloud") throw new Error("云端版需要联网保存，请恢复网络后重试。");
  if (!userID) throw new Error("离线保存需要先登录云端账号。");
  const envelope = readOfflineQueue(userID);
  envelope.operations.push({ ...operation, id: crypto.randomUUID(), owner_id: userID, created_at: new Date().toISOString() });
  const encoded = JSON.stringify(envelope);
  if (encoded.length > 3_500_000) throw new Error("离线修改队列空间不足，请联网同步后再继续保存。");
  localStorage.setItem(offlineQueueKey(userID), encoded);
  const cache = readOfflineCache(userID);
  if (cache) {
    applyQueuedOperation(cache, operation);
    writeOfflineCache(cache, userID);
  }
  renderConnectionStatus();
  if (state.user?.id === userID && navigator.onLine && !offlineReplayTask && !offlineRetryTimer) scheduleOfflineQueueRetry();
}

function scheduleOfflineQueueRetry() {
  const envelope = readOfflineQueue();
  envelope.retryCount = Math.min((envelope.retryCount || 0) + 1, 6);
  const delays = [5_000, 15_000, 30_000, 60_000, 180_000, 300_000];
  const delay = delays[envelope.retryCount - 1];
  envelope.nextRetryAt = Date.now() + delay;
  try { localStorage.setItem(offlineQueueKey(), JSON.stringify(envelope)); } catch { /* Queue remains available in its previous saved form. */ }
  clearTimeout(offlineRetryTimer);
  offlineRetryTimer = setTimeout(() => { void replayOfflineQueue(); }, delay);
}

async function upgradeOfflineAssetQueue(ownerID) {
  const generation=workspaceGeneration,envelope=readOfflineQueue(ownerID);
  const pathMap=new Map();let changed=false;
  const replacePaths=value=>{
    if(typeof value==='string')return pathMap.get(value)||value;
    if(Array.isArray(value))return value.map(replacePaths);
    if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,replacePaths(v)]));
    return value;
  };
  for(const operation of envelope.operations) {
    if(operation.owner_id!==ownerID)throw Error('离线操作的账号标记异常，已停止同步。');
    if(operation.kind==='storage-upload') {
      const oldPath=operation.path?.replace(/^object\/account-assets\//,'');
      if(!isOwnedAccountAssetPath(oldPath,ownerID))throw Error('离线图片路径异常，已停止同步。');
      if(!/[-/][a-f0-9]{64}\.jpg$/i.test(oldPath)) {
        const bytes=Uint8Array.from(atob(operation.base64),c=>c.charCodeAt(0));
        const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(n=>n.toString(16).padStart(2,'0')).join('');
        if(state.user?.id!==ownerID||workspaceGeneration!==generation)throw Error('账号会话已变化，已停止离线升级。');
        const next=oldPath.replace(/\.jpg$/i,'')+'-'+hash+'.jpg';
        pathMap.set(oldPath,next);operation.path='object/account-assets/'+next;changed=true;
      }
    } else if(operation.body) {
      const replacement=replacePaths(operation.body);
      if(JSON.stringify(replacement)!==JSON.stringify(operation.body)){operation.body=replacement;changed=true;}
    }
  }
  if(!changed)return;
  if(state.user?.id!==ownerID||workspaceGeneration!==generation)throw Error('账号会话已变化，已停止离线升级。');
  // Publish the complete ordered queue in one localStorage replacement. Each
  // settings write references the upload that precedes it, not the final image.
  localStorage.setItem(offlineQueueKey(ownerID),JSON.stringify(envelope));
  const cache=readOfflineCache(ownerID);if(cache)writeOfflineCache(replacePaths(cache),ownerID);
}

async function replayOfflineQueue() {
  if (state.archiveMode) return;
  if (!navigator.onLine || !state.user?.id || offlineReplayTask || queuedOperationCount() === 0) return;
  const replayUserID = state.user.id;
  const replayGeneration=workspaceGeneration;
  clearTimeout(offlineRetryTimer);
  offlineRetryTimer = null;
  offlineReplayTask = (async () => {
    let blockedByServer = false;
    try {
      await upgradeOfflineAssetQueue(replayUserID);
      while ((state.user?.id === replayUserID && workspaceGeneration === replayGeneration) && readOfflineQueue(replayUserID).operations.length > 0 && navigator.onLine) {
        const envelope = readOfflineQueue(replayUserID);
        const operation = envelope.operations[0];
        if (!operation) break;
        if (operation.owner_id !== replayUserID) {
          // Fail closed if a persisted queue entry does not belong to its account-scoped queue.
          blockedByServer = true;
          showToast("离线修改的账号标记异常，已暂停同步以保护账号资料。请联系支持人员处理。", true);
          break;
        }
        if (operation.kind === "storage-upload") {
          const assetPath = operation.path?.startsWith("object/account-assets/")
            ? operation.path.slice("object/account-assets/".length) : "";
          if (!isOwnedAccountAssetPath(assetPath, replayUserID)) {
            blockedByServer = true;
            showToast("离线图片路径不属于当前账号，已暂停同步以保护账号资料。请联系支持人员处理。", true);
            break;
          }
          const binary = atob(operation.base64);
          const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
          await storageRequest(operation.path, {
            method: "POST", body: new Blob([bytes], { type: operation.contentType || "image/jpeg" }),
            contentType: operation.contentType || "image/jpeg", queueOffline: false,
          });
        } else if (operation.kind === "storage-delete") {
          // Legacy eager cleanup is intentionally retired; references on other
          // devices may still be live. Removing the queue job does not delete data.
        } else {
          await request(operation.table, {
            method: operation.method, query: operation.query, body: operation.body,
            prefer: operation.prefer, queueOffline: false,
          });
        }
        if ((state.user?.id !== replayUserID || workspaceGeneration !== replayGeneration)) break;
        const latest = readOfflineQueue(replayUserID);
        latest.operations = latest.operations.filter(item => item.id !== operation.id);
        latest.retryCount = 0;
        latest.nextRetryAt = null;
        if (latest.operations.length) localStorage.setItem(offlineQueueKey(replayUserID), JSON.stringify(latest));
        else localStorage.removeItem(offlineQueueKey(replayUserID));
        renderConnectionStatus();
      }
      if ((state.user?.id !== replayUserID || workspaceGeneration !== replayGeneration)) return;
      offlineRetryCount = 0;
      if (readOfflineQueue(replayUserID).operations.length === 0) {
        localStorage.removeItem(offlineQueueKey(replayUserID));
        clearTimeout(offlineRetryTimer);
        try {
          await loadData();
          renderApp();
          showToast("离线修改已全部同步到云端。");
        } catch (error) {
          if (!isNetworkFailure(error)) throw error;
          state.offline = true;
          renderConnectionStatus();
          showToast("修改已同步，但暂时无法刷新最新云端资料。", true);
        }
      }
    } catch (error) {
      if ((state.user?.id !== replayUserID || workspaceGeneration !== replayGeneration)) return;
      if (isNetworkFailure(error) && queuedOperationCount() > 0) {
        scheduleOfflineQueueRetry();
      } else if (isNetworkFailure(error)) {
        state.offline = true;
        showToast("修改已同步，但暂时无法刷新最新云端资料。", true);
      } else {
        blockedByServer = true;
        showToast(`有一项离线修改未能同步，队列已保留：${error.message || "请检查数据后重试。"}`, true);
      }
    } finally {
      offlineReplayTask = null;
      renderConnectionStatus();
      if ((state.user?.id === replayUserID && workspaceGeneration === replayGeneration) && !blockedByServer && navigator.onLine && queuedOperationCount() > 0 && !offlineRetryTimer) scheduleOfflineQueueRetry();
    }
  })();
  return offlineReplayTask;
}

function isNetworkFailure(error) {
  return !navigator.onLine || ['AbortError','TimeoutError'].includes(error?.name) || error instanceof TypeError || error.status === 429 || error.status >= 500;
}

async function request(tableOrPath, { method = "GET", query = {}, body, prefer, queueOffline = true } = {}) {
  const requestUserID = state.user?.id;
  const requestGeneration = workspaceGeneration;
  const isAuthPath = tableOrPath.startsWith("/auth/");
  const session = await currentSession();
  if (!session) throw new Error("云端登录状态已失效，请重新登录。");
  if (!isAuthPath && (!requestUserID || (state.user?.id !== requestUserID || workspaceGeneration !== requestGeneration) || session.user?.id !== requestUserID)) {
    throw new Error("账号已切换，请重新加载当前账号资料。");
  }
  if (!isAuthPath && state.productEdition === "cloud" && method !== "GET" && queueOffline && queuedOperationCount() > 0) {
    throw new Error("还有未完成的离线修改，请先联网同步后再继续编辑。");
  }
  if (state.archiveMode && !isAuthPath && tableOrPath !== 'rpc/read_expired_account_archive' && tableOrPath !== 'account_entitlements') throw Error('账号已到期，仅可查看和导出已有资料。');
  const deviceBootstrap = ['account_entitlements','rpc/register_account_device','rpc/release_account_device','rpc/read_expired_account_archive'].includes(tableOrPath);
  if(!isAuthPath && !deviceBootstrap)await ensureAccountDevice();
  if(workspaceGeneration!==requestGeneration || state.user?.id!==requestUserID)throw Error('账号会话已变化，已停止旧请求。');
  if (method !== 'GET' && !isAuthPath && !deviceBootstrap) loadSequence++;
  const url = apiURL(isAuthPath ? tableOrPath : `/rest/v1/${tableOrPath}`, query);
  const headers = {
    apikey: SUPABASE_PUBLISHABLE_KEY,
    Authorization: `Bearer ${session.access_token}`,
    'x-account-device-id': accountDeviceID(),
    "Content-Type": "application/json",
  };
  if (prefer) headers.Prefer = prefer;
  if (queueOffline && method !== "GET" && !isAuthPath && queuedOperationCount() > 0) {
    persistOfflineOperation({ table: tableOrPath.replace(/^\/rest\/v1\//, ""), method, query, body, prefer }, requestUserID);
    return method === "POST" && prefer?.includes("return=representation")
      ? (Array.isArray(body) ? body : [body]) : null;
  }
  let response;
  try {
    response = await networkFetch(url, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      cache: state.productEdition === "cloud" ? "no-store" : "default",
    });
  } catch (error) {
    if(workspaceGeneration !== requestGeneration || state.user?.id !== requestUserID) throw Error('账号会话已变化，已停止旧请求。');
    if (!queueOffline || state.productEdition === "cloud" || method === "GET" || isAuthPath || !requestUserID || !isNetworkFailure(error)) throw error;
    const table = tableOrPath.replace(/^\/rest\/v1\//, "");
    const operation = { table, method, query, body, prefer };
    persistOfflineOperation(operation, requestUserID);
    return method === "POST" && prefer?.includes("return=representation")
      ? (Array.isArray(body) ? body : [body]) : null;
  }
  if (!isAuthPath && (state.user?.id !== requestUserID || workspaceGeneration !== requestGeneration)) throw new Error("账号已切换，请重新加载当前账号资料。");
  const text = await response.text();
  const payload = text ? (() => { try { return JSON.parse(text); } catch { return text; } })() : null;
  if (!response.ok) {
    const error = new Error(friendlyError(typeof payload === "object" && payload ? payload : { message: text }));
    error.status = response.status;
    throw error;
  }
  networkToastShownForCurrentOutage = false;
  return payload;
}

async function getRows(table, query = {}) {
  const softDeleteTables = new Set([
    "travel_agencies", "customers", "customer_contacts", "customer_addresses",
    "trips", "trip_stops", "trip_expenses",
  ]);
  const params = { select: "*", ...query };
  if (softDeleteTables.has(table) && params.deleted_at === undefined) params.deleted_at = "is.null";
  return await request(table, { query: params }) || [];
}

async function upsert(table, row, conflict = "id") {
  const rows = await request(table, {
    method: "POST", query: { on_conflict: conflict }, body: row,
    prefer: "resolution=merge-duplicates,return=representation",
  });
  return Array.isArray(rows) ? rows[0] : row;
}

async function callOnlineRPC(name, body) {
  return request(`rpc/${name}`, {
    method: "POST", body, prefer: "return=minimal", queueOffline: false,
  });
}

async function patch(table, filters, body) {
  return request(table, { method: "PATCH", query: filters, body, prefer: "return=minimal" });
}

async function loadData() {
  const userID = state.user?.id;
  const generation=workspaceGeneration, sequence=++loadSequence;
  if (!userID) return;
  let snapshot;
  try {
    const [customers, contacts, addresses, trips, agencies, settings, stops, expenses] = await Promise.all([
      getRows("customers", { order: "updated_at.desc" }),
      getRows("customer_contacts", { order: "created_at.asc" }),
      getRows("customer_addresses", { order: "created_at.asc" }),
      getRows("trips", { order: "appointment_date.asc" }),
      getRows("travel_agencies", { order: "updated_at.desc" }),
      getRows("user_settings", { owner_id: `eq.${userID}`, limit: "1" }),
      getRows("trip_stops", { order: "position.asc" }),
      getRows("trip_expenses", { order: "position.asc" }),
    ]);
    if ((state.user?.id !== userID || generation !== workspaceGeneration || sequence !== loadSequence)) return;
    snapshot = { customers, contacts, addresses, trips, agencies, settings, stops, expenses };
    const queued = readOfflineQueue().operations;
    for (const operation of queued) applyQueuedOperation(snapshot, operation);
    if (state.productEdition !== "cloud") writeOfflineCache(snapshot);
    restoreQueuedStorageImages(snapshot, queued, state.user.id);
    state.offline = false;
  } catch (error) {
    if ((state.user?.id !== userID || generation !== workspaceGeneration || sequence !== loadSequence)) return;
    const cached = state.productEdition !== "cloud" && isNetworkFailure(error) ? readOfflineCache() : null;
    if (!cached) throw error;
    snapshot = cached;
    const queued = readOfflineQueue().operations;
    for (const operation of queued) applyQueuedOperation(snapshot, operation);
    if (state.productEdition !== "cloud") writeOfflineCache(snapshot);
    restoreQueuedStorageImages(snapshot, queued, state.user.id);
    state.offline = true;
  }
  state.customers = (snapshot.customers || []).filter(row => !row.deleted_at);
  state.contacts = (snapshot.contacts || []).filter(row => !row.deleted_at);
  state.addresses = (snapshot.addresses || []).filter(row => !row.deleted_at);
  state.agencies = (snapshot.agencies || []).filter(row => !row.deleted_at);
  const settings = snapshot.settings || [];
  state.settings = settings[0] || defaultSettings();
  state.paymentMethods = Array.isArray(state.settings.wallet_payment_methods?.methods)
    ? state.settings.wallet_payment_methods.methods : [];
  state.businessCard = { nickname: "", style: 0, portraitData: null, qrCodes: [], ...(state.settings.business_card_data || {}) };
  if (!Array.isArray(state.businessCard.qrCodes)) state.businessCard.qrCodes = [];
  const migrateCardImages = !state.offline && (Boolean(state.businessCard.portraitData && !state.businessCard.portraitPath)
    || state.businessCard.qrCodes.some(item => item.imageData && !item.imagePath));
  const migratePaymentImages = !state.offline && state.paymentMethods.some(item => item.qrImageData && !item.qrImagePath);
  if (!state.offline && queuedOperationCount() === 0) {
    try {
      await hydrateAccountAssets();
      if ((state.user?.id !== userID || generation !== workspaceGeneration || sequence !== loadSequence)) return;
    }
    catch (error) {
      if ((state.user?.id !== userID || generation !== workspaceGeneration || sequence !== loadSequence)) return;
      if (!isNetworkFailure(error)) throw error;
      state.offline = true;
    }
  }
  state.stops = snapshot.stops || [];
  state.expenses = snapshot.expenses || [];
  state.trips = (snapshot.trips || []).filter(row => !row.deleted_at).map(trip => ({
    ...trip,
    stops: state.stops.filter(stop => stop.trip_id === trip.id && !stop.deleted_at).sort((a, b) => a.position - b.position),
    expenses: state.expenses.filter(expense => expense.trip_id === trip.id && !expense.deleted_at).sort((a, b) => a.position - b.position),
  }));
  scheduleWebReminders();
  // Migrate only after publishing the loaded snapshot. A migration is a write
  // and must invalidate older in-flight loads, not cancel its own initial load.
  if (migrateCardImages || migratePaymentImages) void (async () => {
    try {
      if(state.user?.id!==userID || generation!==workspaceGeneration)return;
      if(migrateCardImages)await saveBusinessCard(true);
      if(state.user?.id!==userID || generation!==workspaceGeneration)return;
      if(migratePaymentImages)await savePaymentMethods(true);
    } catch(error) {if(state.user?.id===userID && generation===workspaceGeneration)showToast('图片迁移尚未完成，请联网后重新保存。',true);}
  })();
}

async function resolveProductEdition() {
  const userID = state.user?.id;
  if (!userID) throw new Error("请先登录云端账号。");
  const cacheKey = `${ACCOUNT_PREFERENCE_PREFIX}${userID}.product-edition`;
  const cached = (() => { try { return JSON.parse(localStorage.getItem(cacheKey) || "null"); } catch { return null; } })();
  try {
    const rows = await request("account_entitlements", {
      query: { select: "edition,status,expires_at,max_devices", owner_id: `eq.${userID}`, limit: "1" },
      queueOffline: false,
    });
    if (state.user?.id !== userID) throw new Error("账号已切换，请重新加载当前账号资料。");
    const entitlement = rows?.[0];
    state.archiveMode = false;
    state.archiveData = null;
    if (!entitlement) {
      throw new Error("此云端账号尚未开通云端权益，资料没有删除；请联系管理员开通访问。");
    } else {
      const expiration = entitlement.expires_at ? Date.parse(entitlement.expires_at) : Infinity;
      if (["cloud","sync"].includes(entitlement.edition) && ["active","grace","expired"].includes(entitlement.status) && Number.isFinite(expiration) && expiration <= Date.now()) {
        state.productEdition = entitlement.edition;
        state.entitlementExpiresAt = entitlement.expires_at;
        state.archiveMode = true;
        state.entitlementResolved = true;
        return;
      }
      if (!(entitlement.status === "active" || entitlement.status === "grace")
          || (entitlement.expires_at && !Number.isFinite(expiration))
          || expiration <= Date.now()) {
        throw new Error("云端权益已过期或暂停，请联系支持人员恢复账户访问。");
      }
      if (!(["cloud", "sync"].includes(entitlement.edition))) {
        throw new Error("此账号当前没有 Web 云端访问权益。");
      }
      state.productEdition = entitlement.edition;
      state.entitlementExpiresAt = entitlement.expires_at || null;
      localStorage.setItem(cacheKey, JSON.stringify(entitlement));
      if (state.productEdition === "cloud") localStorage.removeItem(offlineCacheKey(userID));
    }
    state.entitlementResolved = true;
  } catch (error) {
    // A missing table is a rollout-compatible legacy state. Network failures
    // may use the last account-scoped edition; unknown accounts fail closed.
    if (error.status === 404) {
      state.productEdition = "sync";
      state.entitlementResolved = true;
      localStorage.setItem(cacheKey, JSON.stringify({ edition: "sync", status: "legacy" }));
    } else if (isNetworkFailure(error) && cached && ["cloud", "sync"].includes(cached.edition)) {
      const expiry = cached.expires_at ? Date.parse(cached.expires_at) : Infinity;
      if (expiry <= Date.now() || (cached.expires_at && !Number.isFinite(expiry))
          || !["active", "grace", "legacy"].includes(cached.status)) throw error;
      state.productEdition = cached.edition;
      state.entitlementExpiresAt = cached.expires_at || null;
      state.entitlementResolved = true;
      if (state.productEdition === "cloud") localStorage.removeItem(offlineCacheKey(userID));
    } else if (isNetworkFailure(error) && readOfflineCache(userID)) {
      // Before the entitlement service rollout, existing browser accounts had
      // no edition marker. Preserve their previously working sync behavior.
      state.productEdition = "sync";
      state.entitlementResolved = true;
    } else {
      throw error;
    }
  }
  if(navigator.onLine) {
    try {await ensureAccountDevice();}
    catch(error) {if(!isNetworkFailure(error)||state.productEdition==='cloud')throw error;state.offline=true;}
  }

}

function defaultSettings() {
  return {
    owner_id: state.user?.id, language_code: "zh-Hans", currency_country_code: "US",
    currency_name: "美元", currency_code: "USD", currency_symbol: "$",
    navigation_provider: "appleMaps", expense_catalog: ["居间费", "高速通行费"],
  };
}

function expenseCatalog() {
  if (Array.isArray(state.settings?.expense_catalog)) return state.settings.expense_catalog;
  try {
    const saved = JSON.parse(getAccountPreference("expense-catalog") || "null");
    return Array.isArray(saved) ? saved : ["居间费", "高速通行费"];
  } catch { return ["居间费", "高速通行费"]; }
}

function dateOnly(value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) {
    const date = new Date(`${value}T12:00:00Z`);
    return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0,10) === value ? value.slice(5).replace('-', '/') : "—";
  }
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "—";
  return new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit" }).format(date);
}

function timeOnly(value) {
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "—";
  return new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false }).format(date);
}

function timeDisplay(value) {
  if (!value) return "—";
  const text = String(value).trim();
  const match = text.match(/(?:^|T|\s)(\d{1,2}:\d{2})(?::\d{2})?/);
  return match ? match[1].padStart(5, "0") : timeOnly(value);
}

function dateInput(value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(value))) return String(value);
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

function timeInput(value) { return timeOnly(value); }
function dateAt(date, time = "00:00") { return new Date(`${date}T${time}:00`).toISOString(); }

function currency(value) {
  const currencyCode = state.settings?.currency_code || "USD";
  try { return new Intl.NumberFormat("zh-CN", { style: "currency", currency: currencyCode }).format(Number(value || 0)); }
  catch { return `${state.settings?.currency_symbol || "$"}${Number(value || 0).toFixed(2)}`; }
}

function netIncome(trip) {
  return Number(trip.price || 0) + Number(trip.tip || 0) + (trip.expenses || []).reduce((total, item) => total + (item.is_addition ? 1 : -1) * Number(item.amount || 0), 0);
}

function tripStatus(trip) {
  if (trip.is_cancelled) return `<span class="pill red">已取消</span>`;
  if (trip.is_completed) return `<span class="pill accent">已完成</span>`;
  return `<span class="pill">待执行</span>`;
}

function paymentStatus(trip) {
  return trip.is_paid ? `<span class="pill green">已结清</span>` : `<span class="pill orange">未收款</span>`;
}

function customerByID(id) { return state.customers.find(customer => customer.id === id); }
function contactRows(customerID) { return state.contacts.filter(contact => contact.customer_id === customerID); }
function addressRows(customerID) { return state.addresses.filter(address => address.customer_id === customerID); }
function normalizedLanguageCode(code) {
  const normalized = String(code || "").trim().replaceAll("_", "-").toLowerCase();
  if (normalized.startsWith("zh")) return /hant|tw|hk|mo|traditional/.test(normalized) ? "zh-Hant" : "zh-Hans";
  if (normalized.startsWith("en")) return "en";
  if (normalized.startsWith("es")) return "es";
  if (normalized.startsWith("ja")) return "ja";
  if (normalized.startsWith("ko")) return "ko";
  return "zh-Hans";
}
function languageName(code) {
  return ({
    "zh-Hans": "简体中文", "zh-Hant": "繁體中文",
    en: "English", es: "Español", ja: "日本語", ko: "한국어",
  })[normalizedLanguageCode(code)];
}

// Device UI preference only; never stores account details or authentication data.
const INTERFACE_LANGUAGE_KEY = "yunsheng.web.ui-language.v1";
let interfaceLanguageOverride = null;
function readInterfaceLanguage() {
  let saved;
  try { saved = localStorage.getItem(INTERFACE_LANGUAGE_KEY); } catch {}
  return normalizedLanguageCode(interfaceLanguageOverride || saved || navigator.language);
}
function changeAuthLanguage(language) {
  if (state.busy) return;
  const form = document.getElementById(authScreen === "login" ? "loginForm" : "authForm");
  const passwords = {};
  for (const name of ["email", "salutation", "phone"]) {
    if (form?.elements?.[name]) authDraft[name] = form.elements[name].value;
  }
  // Preserve typed passwords only in this synchronous call and the replacement DOM.
  for (const name of ["password", "confirm_password"]) {
    if (form?.elements?.[name]) passwords[name] = form.elements[name].value;
  }
  interfaceLanguageOverride = normalizedLanguageCode(language);
  try { localStorage.setItem(INTERFACE_LANGUAGE_KEY, interfaceLanguageOverride); } catch {}
  renderLogin(passwords);
}
let authScreen = "login";
let authNotice = "";
let authDraft = {email:"",salutation:"",phone:""};
let recoveryCredentials = null;
const AUTH_REDIRECT = "https://trvelma.pages.dev/";

function renderLogin(passwords = {}) {
  const signup = authScreen === "register", recover = authScreen === "recover", reset = authScreen === "reset";
  const title = signup ? "注册云端账号" : recover ? "找回密码" : reset ? "设置新密码" : "欢迎回来";
  const submit = signup ? "注册并发送验证邮件" : recover ? "发送重置邮件" : reset ? "确认重置密码" : "登录";
  const authField = (name,label,type,autocomplete,required=true) => {
    const input = `<input id="${name}" name="${name}" type="${type}" autocomplete="${autocomplete}" ${required?"required":""} ${type==="password" && (signup||reset)?'minlength="8"':""} value="${type==="password"?"":escapeHTML(authDraft[name]||"")}">`;
    return `<div class="field"><label for="${name}">${escapeHTML(ui(label))}</label>${type === "password" ? `<div class="auth-password-field">${input}<button type="button" class="auth-password-eye" data-action="auth-password-visibility" data-password-label="${escapeHTML(label)}" aria-label="${escapeHTML(ui('显示' + label))}" aria-pressed="false" aria-controls="${name}">${appIcon("eye")}</button></div>` : input}</div>`;
  };
  document.getElementById("app").innerHTML = `<main class="login-screen"><section class="login-brand"><div class="brand-lockup"><span class="brand-mark">云</span><span>${escapeHTML(ui('云盛行程管家'))}</span></div><div class="brand-copy"><h1>${escapeHTML(ui('每一段行程，都安排妥当。'))}</h1><p>${escapeHTML(ui('客户资料、行程安排与结算信息，在手机和浏览器之间保持同步。'))}</p></div><div class="brand-foot">${escapeHTML(ui('安全登录后，访问你的云端业务数据。'))}</div></section>
  <section class="login-panel"><form id="${authScreen === "login" ? "loginForm" : "authForm"}" class="login-card">
  <div class="auth-language field"><label for="authLanguage">${escapeHTML(ui('界面语言'))}</label><select id="authLanguage" ${state.busy?'disabled':''}>${['zh-Hans','zh-Hant','en','es','ja','ko'].map(code=>`<option value="${code}" ${code===uiLanguage()?'selected':''}>${languageName(code)}</option>`).join('')}</select></div>
  <h2>${escapeHTML(ui(title))}</h2><p>${escapeHTML(ui(signup ? "邮箱验证后，自动开始 14 天云端版试用，最多 4 台设备。" : reset ? "验证链接仅用于重置密码，完成后请重新登录。" : "使用行程管家云端账号"))}</p>
  ${state.error?`<div class="error" role="alert">${escapeHTML(ui(state.error))}</div>`:""}${authNotice?`<p role="status">${escapeHTML(ui(authNotice))}</p>`:""}
  ${signup?authField("salutation","称呼","text","nickname",false):""}
  ${reset?"":authField("email","邮箱","email","username")}
  ${signup?authField("phone","手机号（选填）","tel","tel",false):""}
  ${recover?"":authField("password",reset?"新密码":"密码","password",signup||reset?"new-password":"current-password")}
  ${signup||reset?authField("confirm_password","确认密码","password","new-password"):""}
  <button class="button primary full" type="submit" ${state.busy?"disabled":""}>${escapeHTML(ui(state.busy?"正在处理…":submit))}</button>
  <div class="form-actions">${authScreen!=="login"?`<button class="button" type="button" data-action="auth-screen" data-mode="login">${escapeHTML(ui('返回登录'))}</button>`:`<button class="button" type="button" data-action="auth-screen" data-mode="register">${escapeHTML(ui('注册账号'))}</button><button class="button" type="button" data-action="auth-screen" data-mode="recover">${escapeHTML(ui('忘记密码'))}</button><button class="button" type="button" data-action="auth-resend">${escapeHTML(ui('重发验证邮件'))}</button><button class="button" type="button" data-action="delete-cloud-account">${escapeHTML(ui('删除云端账号'))}</button>`}</div>
  </form></section></main>`;
  document.documentElement.lang = uiLanguage();
  for (const [name, value] of Object.entries(passwords)) {
    const input = document.getElementById(name);
    if (input && ["password", "confirm_password"].includes(name)) input.value = value;
  }
}

function toggleAuthPassword(button) {
  const input = button.closest(".auth-password-field")?.querySelector("input");
  if (!input) return;
  const visible = input.type === "password";
  input.type = visible ? "text" : "password";
  const label = button.dataset?.passwordLabel || (input.name === "confirm_password" ? "确认密码" : input.autocomplete === "new-password" ? "新密码" : "密码");
  button.setAttribute("aria-label", ui((visible ? "隐藏" : "显示") + label));
  button.setAttribute("aria-pressed", String(visible));
  button.innerHTML = appIcon(visible ? "eye.slash" : "eye");
}

async function submitAuthForm(form) {
  const mode = authScreen, data = Object.fromEntries(new FormData(form));
  if (state.busy) return;
  if (mode !== "reset" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(data.email||"").trim())) throw Error("请输入有效的邮箱地址。");
  if ((mode === "register" || mode === "reset") && (String(data.password||"").length<8 || data.password!==data.confirm_password)) throw Error("密码至少 8 位，且两次输入必须一致。");
  if (mode === "register" && data.phone && data.phone.replace(/\D/g,"").length<6) throw Error("请输入有效的手机号，或留空。");
  authDraft={email:String(data.email||authDraft.email).trim().toLowerCase(),salutation:String(data.salutation||"").trim(),phone:String(data.phone||"").trim()};
  const credentials = recoveryCredentials;
  state.busy=true;state.error="";authNotice="";
  try {
    if (mode === "register") {
      await authRequest(`signup?redirect_to=${encodeURIComponent(AUTH_REDIRECT)}`,{email:authDraft.email,password:data.password,data:{salutation:authDraft.salutation,phone:authDraft.phone}});
      authScreen="login";authNotice="请查收邮箱验证邮件，点击链接后返回登录；重复申请不会延长试用。";
    } else if (mode === "recover") {
      await authRequest(`recover?redirect_to=${encodeURIComponent(AUTH_REDIRECT)}`,{email:authDraft.email});
      authNotice="如果该邮箱可用于找回密码，将收到重置邮件。请留意垃圾邮件。";
    } else if (mode === "reset") {
      if (!credentials?.accessToken) throw Error("重置链接已失效，请重新申请。");
      await authRequest("user",{password:data.password},{method:"PUT",accessToken:credentials.accessToken});
      recoveryCredentials=null;authScreen="login";authNotice="密码已更新，请使用新密码登录。";
    }
  } catch(error) {state.error=error.message||"操作失败，请稍后重试。";}
  finally {state.busy=false;renderLogin();}
}

async function resendAuthEmail(form) {
  if(state.busy)return;
  const email=String(form?.elements.email?.value||authDraft.email||"").trim().toLowerCase();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw Error("请先填写有效的邮箱地址。");
  authDraft.email=email;state.busy=true;state.error="";
  try {await authRequest(`resend?redirect_to=${encodeURIComponent(AUTH_REDIRECT)}`,{type:"signup",email});authNotice="如果该邮箱需要验证，将收到验证邮件。请勿频繁重发。";}
  catch(error){state.error=error.message;}
  finally{state.busy=false;renderLogin();}
}

async function consumeAuthLink() {
  const hash=new URLSearchParams(location.hash.slice(1));
  const type=hash.get("type"),token=hash.get("access_token");
  if(!token)return false;
  history.replaceState(null,"",location.pathname+location.search);
  state.error="";authNotice="";
  try {
    if(!["signup","recovery"].includes(type))throw Error("不支持的验证链接，请返回登录。");
    const response=await networkFetch(`${SUPABASE_URL}/auth/v1/user`,{headers:{apikey:SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${token}`}});
    if(!response.ok)throw Error("验证或重置链接已失效，请重新申请邮件。");
    const user=await response.json();
    if(!user.id || !user.email_confirmed_at)throw Error("邮箱尚未验证完成，请重新申请验证邮件。");
    authDraft.email=user.email||"";
    if(type==="recovery"){recoveryCredentials={accessToken:token};authScreen="reset";}
    else {authScreen="login";authNotice="邮箱验证完成，请登录。";}
  }catch(error){recoveryCredentials=null;authScreen="login";state.error=error.message;}
  renderLogin();return true;
}

function renderPendingSyncBlocker() {
  const count = queuedOperationCount();
  const message = state.productEdition === "cloud"
    ? "云端版尚有同步版留下的待提交修改，当前同步未完成。"
    : "云端暂时没有接受全部待同步修改。";
  document.getElementById("app").innerHTML = `<main class="offline-start"><section class="panel"><h1>还有修改等待同步</h1><p>${escapeHTML(message)}队列中的 ${count} 项修改仍保存在本机；保持当前账号登录，联网后可以继续重试。</p><button class="button primary" data-action="retry-offline-load">重试同步</button><button class="button" data-action="signout">退出登录</button></section></main>`;
}

const appSymbolNames = new Set(["house.fill", "books.vertical", "person.text.rectangle.fill", "wallet.bifold.fill", "person.crop.rectangle.badge.plus.fill", "building.2.fill", "gearshape.fill", "airplane", "airplane.arrival", "airplane.departure", "car.fill", "clock.fill", "figure.wave", "ellipsis.circle.fill", "checkmark.circle.fill", "checkmark", "book.closed", "location.north.fill", "arrow.triangle.turn.up.right.diamond.fill", "arrow.up.arrow.down", "mappin.and.ellipse", "mappin", "flag.checkered", "person.fill", "suitcase.fill", "calendar", "magnifyingglass", "plus", "plus.circle", "minus.circle.fill", "xmark", "chevron.right", "chevron.down", "chevron.up", "chevron.left", "arrow.clockwise", "chart.pie.fill", "list.bullet.rectangle", "qrcode", "qrcode.viewfinder", "trash", "arrow.down.left", "arrow.up.right", "person.2", "tray.full", "t.square", "dollarsign.circle", "checkmark.circle", "bell.badge", "questionmark.circle", "eye", "eye.slash", "phone.fill", "message.fill", "rectangle.portrait.and.arrow.right"]);
function appIcon(name) {
  const symbol = appSymbolNames.has(name) ? name : "questionmark.circle";
  return `<span class="app-symbol" data-symbol="${symbol}" aria-hidden="true" style="--app-symbol-image:url('./assets/icons/${symbol.replaceAll('.', '-')}.png')"></span>`;
}
function serviceSymbol(type, context = "list") {
  const picker = {"接机":"airplane.departure","送机":"airplane.arrival","接送":"car.fill","包车":"clock.fill"};
  const list = {"接机":"airplane.arrival","送机":"airplane.departure","接送":"car.fill","包车":"car.fill"};
  return (context === "picker" ? picker : list)[type] || (context === "picker" ? "ellipsis.circle.fill" : "figure.wave");
}

const navItems = [
  ["home", "house.fill", "总览"], ["trips", "books.vertical", "行程"], ["customers", "person.crop.rectangle.badge.plus.fill", "客户"],
  ["businessCard", "person.text.rectangle.fill", "名片"], ["agencies", "building.2.fill", "旅行社"], ["wallet", "wallet.bifold.fill", "财务"], ["settings", "gearshape.fill", "设置"],
];

async function loadExpiredArchive() {
  const ownerID = state.user?.id;
  const data = await request('rpc/read_expired_account_archive', {method:'POST',body:{},queueOffline:false});
  if (state.user?.id !== ownerID || !state.archiveMode) return;
  state.archiveData = data;
  renderExpiredArchive();
}
function archiveRecordDetails(row) {
  const fields={customer_name:'客人',name:'名称',appointment_date:'接载日期',appointment_time:'接载时间',price:'金额',tip:'小费',location_start:'起始点',location_end:'目的地',customer_contact:'联系方式',phone:'电话',email:'邮箱',address:'地址',value:'内容',label:'类别',title:'项目',amount:'金额',service_type:'行程类型',flight_info:'航班',memo:'备注',travel_agency_name:'旅行社',travel_agency_order_number:'旅行社订单号'};
  return Object.entries(fields).filter(([key])=>row[key]!==null&&row[key]!==undefined&&row[key]!=='').map(([key,label])=>`<p><strong>${escapeHTML(ui(label))}：</strong>${escapeHTML(String(row[key]))}</p>`).join('') || `<p>${escapeHTML(ui('完整资料包含在导出文件中。'))}</p>`;
}
function renderExpiredArchive() {
  const data = state.archiveData;
  if (!data) return;
  const sections = [['trips','行程'],['customers','客户'],['travel_agencies','旅行社'],['trip_expenses','费用明细'],['customer_contacts','联系方式'],['customer_addresses','客户地址'],['trip_stops','停靠点'],['user_settings','设置与名片资料']];
  document.getElementById('app').innerHTML = `<main class="expired-archive"><section class="panel"><h1>${escapeHTML(ui('账号已到期 · 资料只读'))}</h1><p>${escapeHTML(ui('已有资料仍可查看和导出。新增、编辑、结算、航班刷新和同步已暂停。'))}</p><p>${escapeHTML(ui('导出的 JSON 文件包含个人及业务资料，请妥善保管。'))}</p><button class="button primary" data-action="export-expired-archive">${escapeHTML(ui('导出全部资料'))}</button> <button class="button" data-action="retry-expired-archive">${escapeHTML(ui('重新检查授权'))}</button> <button class="button" data-action="signout">${escapeHTML(ui('退出登录'))}</button> <button class="button danger" data-action="delete-cloud-account">${escapeHTML(ui('删除云端账号'))}</button></section>${sections.map(([key,title])=>`<section class="panel"><h2>${escapeHTML(ui(title))} · ${(data[key]||[]).length}</h2>${(data[key]||[]).map(row=>`<details class="archive-record"><summary>${escapeHTML(row.customer_name||row.name||row.title||row.address||ui(title))} ${key==='trips'?escapeHTML(row.appointment_date||''):''}</summary>${archiveRecordDetails(row)}</details>`).join('')}</section>`).join('')}</main>`;
}
function exportExpiredArchive() {
  if (!state.archiveMode || !state.archiveData) return;
  const url=URL.createObjectURL(new Blob([JSON.stringify(state.archiveData,null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download=ui('TrvelMA-资料备份')+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}

function accountValidityHTML(expiresAt = state.entitlementExpiresAt, now = Date.now()) {
  if (!expiresAt) return "";
  const end = Date.parse(expiresAt);
  if (!Number.isFinite(end)) return "";
  const days = Math.max(0, Math.ceil((end - now) / 86400000));
  const date = new Intl.DateTimeFormat(uiLanguage(), {year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).format(new Date(end));
  return `<div class="account-validity"><strong>${escapeHTML(days ? ui('剩余 %ld 天', days) : ui('已到期'))}</strong><small>${escapeHTML(ui('到期：%@', date))}</small></div>`;
}

function renderApp() {
  if (state.archiveMode) { renderExpiredArchive(); return; }
  document.documentElement.lang = uiLanguage();
  const [title, subtitle] = pageNames[state.page];
  document.getElementById("app").innerHTML = `
    <div class="app-shell" data-page="${escapeHTML(state.page)}">
      <aside class="sidebar">
        <div class="brand-lockup"><span class="brand-mark">云</span><span>${escapeHTML(ui('云盛行程管家'))}</span></div>
        ${accountValidityHTML()}
        <div class="nav-label">${escapeHTML(ui('工作台'))}</div>
        <nav class="nav-list">${navItems.map(([key, icon, label]) => `<button class="nav-item ${state.page === key ? "active" : ""}" data-action="navigate" data-page="${key}"><span class="nav-icon">${appIcon(icon)}</span><span>${escapeHTML(ui(label))}</span></button>`).join("")}</nav>

      </aside>
      <main class="main ${state.page === "wallet" ? "finance-main" : ""}">
        <header class="topbar"><div><h1>${escapeHTML(ui(title))}</h1><p>${escapeHTML(ui(subtitle))}</p></div><div class="top-actions"><span class="connection" role="status" aria-live="polite">${escapeHTML(ui('云端已连接'))}</span><button class="button quiet small top-icon-button" data-action="refresh-data" title="${escapeHTML(ui('刷新'))}" aria-label="${escapeHTML(ui('刷新'))}">${appIcon("arrow.clockwise")}</button><button class="button quiet small top-icon-button" data-action="signout" title="${escapeHTML(ui('退出登录'))}" aria-label="${escapeHTML(ui('退出登录'))}">${appIcon("rectangle.portrait.and.arrow.right")}</button><div class="topbar-user"><span class="avatar">${escapeHTML((state.user?.user_metadata?.salutation || state.user?.email || "云").slice(0, 1))}</span><span class="user-copy"><strong>${escapeHTML(state.user?.user_metadata?.salutation || ui("已登录"))}</strong><small>${escapeHTML(state.user?.email || "")}</small></span></div></div></header>
        <section id="pageContent">${renderPage()}</section>
      </main>
    </div>`;
  renderConnectionStatus();
}

function renderPage() {
  if (state.page === "home") return renderHome();
  if (state.page === "trips") return renderTrips();
  if (state.page === "customers") return renderCustomers();
  if (state.page === "businessCard") return renderBusinessCard();
  if (state.page === "agencies") return renderAgencies();
  if (state.page === "wallet") return renderWallet();
  return renderSettings();
}

function activeTrips() { return state.trips.filter(trip => !trip.is_cancelled); }
function upcomingTrips() {
  const today = dateInput(new Date());
  return state.trips.filter(trip => !trip.is_completed && !trip.is_cancelled && dateInput(trip.appointment_date) >= today)
    .sort(compareTrips);
}

function tripMatchesSearch(trip) {
  const query = state.search.trim().toLocaleLowerCase();
  if (!query) return true;
  return [trip.customer_name, trip.customer_contact, trip.service_type, trip.location_start,
    ...(trip.stops || []).map(stop => stop.address), trip.location_end, trip.flight_info, trip.travel_agency_order_number,
    trip.order_source, trip.memo].join(" ").toLocaleLowerCase().includes(query);
}

function tripDates(trips) {
  return [...new Set(trips.map(trip => dateInput(trip.appointment_date)))].sort();
}

function renderDateCard(date, selected, count, all = false) {
  const label = all ? "全部" : date === dateInput(new Date()) ? "今天" : date === dateInput(new Date(Date.now() + 86400000)) ? "明天" : new Intl.DateTimeFormat("zh-CN", { weekday: "short" }).format(new Date(`${date}T12:00:00`));
  return `<button class="trip-date-card ${selected ? "active" : ""}" data-action="${all ? "trip-date-all" : "trip-date"}" ${all ? "" : `data-date="${date}"`}><span>${label}</span><strong>${all ? "全部" : date.slice(5).replace("-", "/")}</strong><small>${all ? "行程" : `${count} 单`}</small></button>`;
}

function renderDateStrip(dates, selected, trips, allCount, allSelected, action = "trip-date") {
  return `<div class="trip-date-strip">${renderDateCard("", allSelected, allCount, true)}${dates.map(date => renderDateCard(date, selected === date, trips.filter(trip => dateInput(trip.appointment_date) === date).length)).join("")}</div>`;
}

function renderMonthCalendar(trips) {
  const month = state.tripCalendarMonth;
  const year = month.getFullYear();
  const monthNumber = month.getMonth();
  const firstWeekday = (new Date(year, monthNumber, 1).getDay() + 6) % 7;
  const daysInMonth = new Date(year, monthNumber + 1, 0).getDate();
  const counts = new Map();
  for (const trip of trips) {
    const key = dateInput(trip.appointment_date);
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const cells = Array.from({ length: firstWeekday }, () => `<span class="calendar-empty"></span>`);
  for (let day = 1; day <= daysInMonth; day++) {
    const date = `${year}-${String(monthNumber + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const count = counts.get(date) || 0;
    cells.push(`<button class="calendar-day ${state.tripDate === date ? "active" : ""} ${count ? "has-trips" : ""}" data-action="trip-date" data-date="${date}" ${count ? "" : "disabled"}><span>${day}</span>${count ? `<small>${count}</small>` : ""}</button>`);
  }
  return `<section class="trip-calendar"><div class="calendar-heading"><button class="button quiet small" data-action="calendar-month" data-step="-1" aria-label="上个月">${appIcon("chevron.left")}</button><strong>${year}年${monthNumber + 1}月</strong><button class="button quiet small" data-action="calendar-month" data-step="1" aria-label="下个月">${appIcon("chevron.right")}</button></div><div class="calendar-grid calendar-weekdays">${["一", "二", "三", "四", "五", "六", "日"].map(day => `<span>${day}</span>`).join("")}</div><div class="calendar-grid">${cells.join("")}</div></section>`;
}

function statCard(icon, label, value, note) {
  return `<article class="stat-card"><div class="stat-top"><span>${label}</span><span class="stat-icon">${appIcon(icon)}</span></div><div class="stat-value">${value}</div><div class="stat-note">${note}</div></article>`;
}

function renderHome() {
  const upcoming = upcomingTrips();
  const monthStart = new Date(); monthStart.setDate(1); monthStart.setHours(0, 0, 0, 0);
  const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 1);
  const monthTrips = state.trips.filter(trip => !trip.is_cancelled && new Date(trip.appointment_date) >= monthStart && new Date(trip.appointment_date) < monthEnd);
  const monthNet = monthTrips.reduce((sum, trip) => sum + netIncome(trip), 0);
  const unpaid = state.trips.filter(trip => !trip.is_paid && !trip.is_cancelled).reduce((sum, trip) => sum + Number(trip.price || 0) + Number(trip.tip || 0), 0);
  const visible = upcoming.filter(trip => (!state.homeDate || dateInput(trip.appointment_date) === state.homeDate) && tripMatchesSearch(trip));
  const dates = tripDates(upcoming);
  return `<div class="stats-grid">
      ${statCard("calendar", "待执行行程", upcoming.length, "从今天开始的待执行安排")}
      ${statCard("person.crop.rectangle.badge.plus.fill", "客户", state.customers.length, "已保存的客户资料")}
      ${statCard("arrow.up.right", "本月净收入", currency(monthNet), "车费、小费及费用调整")}
      ${statCard("clock.fill", "未收款", currency(unpaid), "尚未结清的行程款项")}
    </div>
    <div class="home-workspace"><section class="trip-dashboard home-trip-dashboard">
      ${renderDateStrip(dates, state.homeDate, upcoming, upcoming.length, !state.homeDate)}
      <div class="page-tools trip-search-tools"><label class="search-wrap">${appIcon("magnifyingglass")}<input class="search-input" data-search="home" value="${escapeHTML(state.search)}" placeholder="搜索客户、地点、航班"></label><button class="button primary" data-action="new-trip">${appIcon("plus")} 新增行程</button></div>
      <div class="section-heading"><h2>待执行行程</h2><small>${visible.length}</small></div>
      ${visible.length ? `<div class="trip-list">${visible.map(renderTripCard).join("")}</div>` : emptyState(state.search ? "没有找到行程" : "目前没有待执行行程", state.search ? "请更换搜索内容。" : "新增行程后会显示在这里。", "trip")}
    </section>
    ${upcoming.length ? `<aside class="panel home-next-trip"><div class="section-heading"><h2>${escapeHTML(ui('接载时间'))}</h2>${appIcon('clock.fill')}</div><div class="home-next-time">${timeOnly(upcoming[0].appointment_time)}</div><p class="home-next-date">${dateOnly(upcoming[0].appointment_date)}</p><strong>${escapeHTML(upcoming[0].customer_name || ui('未填写客户'))}</strong><span class="pill accent">${escapeHTML(upcoming[0].service_type || ui('行程'))}</span><div class="home-next-route"><p>${appIcon('mappin.and.ellipse')}${escapeHTML(upcoming[0].location_start || '—')}</p><p>${appIcon('flag.checkered')}${escapeHTML(upcoming[0].location_end || '—')}</p></div><button class="button small" data-action="view-trip" data-id="${escapeHTML(upcoming[0].id)}">${escapeHTML(ui('详细信息'))}${appIcon('chevron.right')}</button></aside>` : ''}
    </div>`;
}

function filteredTrips() {
  const today = dateInput(new Date());
  return state.trips.filter(trip => {
    if (state.tripFilter === "pending" && (trip.is_completed || trip.is_cancelled)) return false;
    if (state.tripFilter === "unpaid" && trip.is_paid) return false;
    if (state.tripFilter === "history" && dateInput(trip.appointment_date) >= today) return false;
    if (state.tripDate && dateInput(trip.appointment_date) !== state.tripDate) return false;
    return tripMatchesSearch(trip);
  }).sort(compareTrips);
}

function renderTrips() {
  const trips = filteredTrips();
  const filters = [["all", "全部"], ["pending", "待执行"], ["unpaid", "未收款"], ["history", "历史"]];
  const dates = tripDates(state.trips);
  const statuses = `<div class="tabs">${filters.map(([key, label]) => `<button class="tab ${state.tripFilter === key ? "active" : ""}" data-action="trip-filter" data-filter="${key}">${label}</button>`).join("")}</div>`;
  return `<section class="trip-dashboard">
    <div class="trip-mode-switch"><button class="${state.tripDateMode === "seven" ? "active" : ""}" data-action="trip-date-mode" data-mode="seven">周</button><button class="${state.tripDateMode === "month" ? "active" : ""}" data-action="trip-date-mode" data-mode="month">月历</button></div>
    ${state.tripDateMode === "seven" ? renderDateStrip(dates, state.tripDate, state.trips, state.trips.length, !state.tripDate) : renderMonthCalendar(state.trips)}
    <div class="page-tools trip-search-tools"><label class="search-wrap">${appIcon("magnifyingglass")}<input class="search-input" data-search="trips" value="${escapeHTML(state.search)}" placeholder="搜索客户、地点、航班"></label><button class="button primary" data-action="new-trip">${appIcon("plus")} 新增行程</button></div>
    ${statuses}
    <div class="section-heading"><h2>${filters.find(([key]) => key === state.tripFilter)?.[1]}行程</h2><small>${trips.length} 条</small></div>
    ${trips.length ? `<div class="trip-list">${trips.map(renderTripCard).join("")}</div>` : emptyState("没有符合条件的行程", "可以调整搜索内容，或新增行程。", "trip")}</section>`;
}

const expandedTripContacts = new Set();
function tripContactActionsHTML(trip) {
  const phones = tripTelephoneContacts(trip, state.contacts, state.customers.map(c => c.id));
  return `<div class="trip-contact-actions">${phones.length ? phones.map(phone => `<div><span>${escapeHTML(phone)}</span><a class="button small" href="sms:${telephoneNumber(phone)}" aria-label="发送信息">${appIcon("message.fill")}</a><a class="button small" href="tel:${telephoneNumber(phone)}" aria-label="拨打电话">${appIcon("phone.fill")}</a></div>`).join("") : '<span class="muted">未填写</span>'}</div>`;
}
const TRIP_AMOUNTS_PRIVACY_KEY = "yunsheng.web.trip-amounts-hidden.v2.";
const tripAmountsPrivacyFallback = new Map();
function tripAmountsHidden(tripID) {
  if (!tripID) return false;
  const key = String(tripID).toLowerCase();
  try { return localStorage.getItem(TRIP_AMOUNTS_PRIVACY_KEY + key) === "true"; }
  catch { return tripAmountsPrivacyFallback.get(key) === true; }
}
function toggleTripAmounts(tripID) {
  if (!tripID) return;
  const key = String(tripID).toLowerCase();
  const hidden = !tripAmountsHidden(key);
  tripAmountsPrivacyFallback.set(key, hidden);
  try { localStorage.setItem(TRIP_AMOUNTS_PRIVACY_KEY + key, String(hidden)); } catch {}
  renderApp();
}

function renderTripCard(trip, { readOnly = false } = {}) {
  const hidden = !readOnly && tripAmountsHidden(trip.id);
  const money = value => hidden ? "••••" : currency(value);
  const isPending = !trip.is_completed && !trip.is_cancelled;
  const tripStops = (trip.stops || []).map(stop => stop.address).filter(Boolean);
  const expanded = readOnly || state.expandedFlights.has(trip.id);
  const moneyRows = (trip.expenses || []).map(item => `<span>${escapeHTML(item.title)} ${item.is_addition ? "+" : "−"}${money(item.amount)}</span>`).join("");
  return `<article class="trip-card trip-card-full" ${readOnly ? "" : `data-action="view-trip" data-id="${trip.id}"`}>
    <div class="trip-time"><strong>${timeOnly(trip.appointment_time)}</strong><small>${dateOnly(trip.appointment_date)}</small></div>
    <div class="trip-main">
      <div class="trip-heading"><div class="trip-title">${readOnly ? `<strong>${escapeHTML(trip.customer_name || "未填写客户")}</strong>` : `<button class="trip-guest-toggle" data-action="toggle-trip-contact" data-id="${escapeHTML(trip.id)}" aria-expanded="${expandedTripContacts.has(trip.id)}">${escapeHTML(trip.customer_name || "未填写客户")}${appIcon(expandedTripContacts.has(trip.id) ? "chevron.up" : "chevron.down")}</button>`}<span class="trip-service">${appIcon(serviceSymbol(trip.service_type))} ${escapeHTML(trip.service_type || "行程")}</span></div><div class="trip-price-controls"><strong class="trip-price">${money(trip.price)}</strong>${readOnly ? "" : `<button type="button" class="trip-amount-visibility" data-action="toggle-trip-amounts" data-id="${escapeHTML(trip.id)}" aria-label="${hidden ? "显示金额" : "隐藏金额"}">${appIcon(hidden ? "eye.slash" : "eye")}</button>`}</div></div>
      ${expandedTripContacts.has(trip.id) ? tripContactActionsHTML(trip) : ""}
      <div class="trip-facts"><span>${appIcon("person.fill")} ${escapeHTML(trip.customer_count || "1")} 位乘客</span><span>${appIcon("suitcase.fill")} ${escapeHTML(trip.customer_stuff || "0")} 件行李</span>${trip.order_source ? `<span>订单：${escapeHTML(trip.order_source)}</span>` : ""}${trip.order_source === '旅行社订单' && trip.travel_agency_order_number ? `<span>旅行社订单号：${escapeHTML(trip.travel_agency_order_number)}</span>` : ''}${trip.customer_contact ? `<span>联系：${escapeHTML(trip.customer_contact)}</span>` : ""}</div>
      <div class="trip-route trip-route-full"><div class="route-point start"><span class="route-icon">${appIcon("mappin.and.ellipse")}</span><span class="trip-route-label">起始点</span><span class="trip-route-value">${escapeHTML(trip.location_start || "—")}</span></div>
        ${tripStops.map((stop, index) => `<div class="route-point stop"><span class="route-icon">${appIcon("mappin")}</span><span class="trip-route-label">停靠点 ${index + 1}</span><span class="trip-route-value">${escapeHTML(stop)}</span></div>`).join("")}
        <div class="route-point end"><span class="route-icon">${appIcon("flag.checkered")}</span><span class="trip-route-label">目的地</span><span class="trip-route-value">${escapeHTML(trip.location_end || "—")}</span></div></div>
      ${trip.flight_info ? readOnly ? `<section class="trip-flight"><div class="flight-summary"><span class="flight-plane">${appIcon("airplane")}</span><strong>${escapeHTML(trip.flight_info)}</strong></div>${flightDetailsHTML(trip)}</section>` : `<section class="trip-flight"><button class="flight-summary" data-action="flight-toggle" data-id="${trip.id}"><span class="flight-plane">${appIcon("airplane")}</span><strong>${escapeHTML(trip.flight_info)}</strong><small>${dateOnly(trip.flight_date || trip.appointment_date)}</small>${trip.flight_departure_time ? `<span>${escapeHTML(timeDisplay(trip.flight_departure_time))}</span>` : ""}<b>航班</b><span class="flight-chevron">${appIcon(expanded ? "chevron.up" : "chevron.down")}</span></button>${expanded ? `${flightDetailsHTML(trip)}<button class="button small" data-action="refresh-flight-card" data-id="${trip.id}">刷新航班</button>` : ""}</section>` : ""}
      ${trip.memo ? `<p class="trip-memo">${escapeHTML(trip.memo)}</p>` : ""}
      <div class="trip-status-row">${tripStatus(trip)} ${paymentStatus(trip)}</div>
      <div class="trip-money-summary"><span><small>行程费用</small><strong>${money(trip.price)}</strong></span><span><small>小费</small><strong>${money(trip.tip)}</strong></span><span><small>净收入</small><strong class="trip-net">${money(netIncome(trip))}</strong></span></div>
      ${moneyRows ? `<div class="trip-expense-summary">${moneyRows}</div>` : ""}
      ${readOnly ? "" : `<div class="trip-actions">${isPending ? `<button class="button small" data-action="edit-trip" data-id="${trip.id}">编辑</button><button class="button small complete-action" data-action="toggle-complete" data-id="${trip.id}">已完成</button><button class="button small danger" data-action="cancel-trip" data-id="${trip.id}">取消行程</button><button class="button small danger" data-action="delete-trip" data-id="${trip.id}">删除</button>` : trip.is_cancelled ? `<button class="button small" data-action="restore-trip" data-id="${trip.id}">恢复行程</button>` : trip.is_completed ? `<button class="button small" data-action="restore-trip" data-id="${trip.id}">恢复待执行</button>` : ""}${!trip.is_paid ? `<button class="button small settle-action" data-action="toggle-paid" data-id="${trip.id}">财务结算</button>` : ""}</div>`}
    </div>
  </article>`;
}

function emptyState(title, detail, action) {
  const actionMarkup = action === "trip" ? `<button class="button primary" data-action="new-trip">${appIcon("plus")} 新增行程</button>` : "";
  return `<div class="empty"><strong>${title}</strong><div>${detail}</div>${actionMarkup ? `<div style="margin-top:16px">${actionMarkup}</div>` : ""}</div>`;
}

function customerStats(customer) {
  const related = state.trips.filter(trip => !trip.is_cancelled && (trip.customer_id === customer.id || (!trip.customer_id && trip.customer_name === customer.name)));
  const income = related.reduce((sum, trip) => sum + Number(trip.price || 0) + Number(trip.tip || 0) + (trip.expenses || []).filter(item => item.is_addition).reduce((total, item) => total + Number(item.amount || 0), 0), 0);
  const unpaid = related.filter(trip => !trip.is_paid).reduce((sum, trip) => sum + Number(trip.price || 0) + Number(trip.tip || 0), 0);
  return { trips: related.length, income, unpaid };
}

function openCustomerDetail(customer) {
  const related = state.trips.filter(trip => trip.customer_id === customer.id || (!trip.customer_id && trip.customer_name === customer.name)).sort((a, b) => new Date(b.appointment_date) - new Date(a.appointment_date));
  const contacts = contactRows(customer.id);
  const addresses = addressRows(customer.id);
  const contactHTML = contacts.map(item => {
    const kind = item.contact_type || item.label || "联系方式";
    const value = String(item.value || "");
    const normalized = kind.toLocaleLowerCase();
    const quickActions = /电话|phone|mobile|手机/i.test(normalized)
      ? `<nav class="contact-quick-actions"><a class="button small" href="tel:${escapeHTML(value.replace(/[^+0-9]/g, ""))}">拨打</a><a class="button small" href="sms:${escapeHTML(value.replace(/[^+0-9]/g, ""))}">短信</a></nav>`
      : /邮箱|email|mail/i.test(normalized) ? `<nav class="contact-quick-actions"><a class="button small" href="mailto:${escapeHTML(value)}">发邮件</a></nav>` : "";
    return `<div class="detail-record"><div><strong>${escapeHTML(kind)}${item.is_default ? ' <small class="pill accent">默认</small>' : ""}</strong><span>${escapeHTML(value)}</span></div>${quickActions}</div>`;
  }).join("") || (customer.email ? `<div class="detail-record"><div><strong>邮箱${contacts.length ? "" : ' <small class="pill accent">默认</small>'}</strong><span>${escapeHTML(customer.email)}</span></div><nav class="contact-quick-actions"><a class="button small" href="mailto:${escapeHTML(customer.email)}">发邮件</a></nav></div>` : '<p class="empty-hint">暂无联系方式</p>');
  const addressHTML = addresses.map(item => '<div class="detail-record"><div><strong>' + escapeHTML(item.label || "常用地址") + (item.is_default ? ' <small class="pill accent">默认</small>' : '') + '</strong><span>' + escapeHTML(item.address) + '</span></div><button class="button small" data-action="navigate-saved-address" data-address="' + escapeHTML(item.address) + '">使用默认导航</button></div>').join("") || '<p class="empty-hint">暂无常用地址</p>';
  const tripHTML = related.map(trip => '<button class="customer-history-row" data-action="view-trip" data-id="' + trip.id + '"><span><small>出行日期</small><strong>' + dateOnly(trip.appointment_date) + '</strong></span><span><small>目的地</small><strong>' + escapeHTML(trip.location_end || "—") + '</strong></span><span><small>车费</small><strong>' + currency(trip.price) + '</strong></span></button>').join("") || '<p class="empty-hint">暂无出行记录</p>';
  const agencyInfo = Number(customer.category) === 2 ? `<section class="form-section"><div class="form-section-title"><div><h3>旅行社信息</h3></div></div><div class="detail-grid"><div><small>旅行社代码</small><strong>${escapeHTML(customer.travel_agency_code || "未选择")}</strong></div><div><small>旅行社名称</small><strong>${escapeHTML(customer.travel_agency_name || "未选择")}</strong></div></div></section>` : "";
  const remark = customer.remark ? `<section class="form-section"><div class="form-section-title"><div><h3>备注</h3></div></div><p class="trip-memo">${escapeHTML(customer.remark)}</p></section>` : "";
  showModal("客户资料", '<section class="customer-detail-hero"><div class="customer-initial">' + escapeHTML((customer.name || "?").slice(0, 1)) + '</div><div><h3>' + escapeHTML(customer.name) + '</h3><small>' + (Number(customer.category) === 2 ? "旅行社" : "普通客户") + ' · ' + escapeHTML(languageName(customer.language_preference)) + '</small></div></section>' + agencyInfo +
    '<section class="form-section"><div class="form-section-title"><div><h3>联系方式</h3></div></div><div class="detail-record-list">' + contactHTML + '</div></section>' +
    '<section class="form-section"><div class="form-section-title"><div><h3>常用地址</h3></div></div><div class="detail-record-list">' + addressHTML + '</div></section>' +
    '<section class="form-section customer-trip-history"><div class="form-section-title"><div><h3>出行记录</h3><p>' + customerStats(customer).trips + ' 次出行 · 总收入 ' + currency(customerStats(customer).income) + ' · 未收款 ' + currency(customerStats(customer).unpaid) + '</p></div></div><div class="customer-history-list">' + tripHTML + '</div></section>' +
    remark + '<div class="detail-actions"><button class="button small danger" data-action="delete-customer" data-id="' + customer.id + '">删除</button><button class="button small primary" data-action="edit-customer" data-id="' + customer.id + '">编辑资料</button></div>', "editor-modal detail-modal");
}

function flightOffsetLabel(value) {
  const text = String(value || "").trim();
  if (!/T/.test(text)) return "";
  if (/Z$/i.test(text)) return "GMT";
  const offset = text.match(/([+-])(\d{2}):?(\d{2})$/);
  if (!offset) return "";
  return `GMT${offset[1]}${Number(offset[2])}${offset[3] === "00" ? "" : `:${offset[3]}`}`;
}

function flightResultHTML(number, flight = {}, fallback = {}) {
  const code = String(number || "").toUpperCase().match(/^([A-Z]{2,3}|[A-Z][0-9]|[0-9][A-Z])(?=\d)/)?.[1] || "";
  const departure = flight.departureTime || fallback.departureTime;
  const arrival = flight.estimatedArrivalTime || fallback.estimatedArrivalTime;
  return `<div class="app-flight-result" aria-label="航班查询结果">
    <div class="app-flight-airline"><span class="app-flight-logo" aria-hidden="true">${code ? escapeHTML(code) : appIcon("airplane")}</span><div><strong>${escapeHTML(number || "—")}</strong>${flight.airlineName ? `<small>${escapeHTML(flight.airlineName)}</small>` : ""}</div></div>
    <div class="app-flight-schedule"><div class="app-flight-time departure"><div><strong>${escapeHTML(timeDisplay(departure))}</strong><small>${escapeHTML(flightOffsetLabel(departure))}</small></div><span>起飞时间</span></div><div class="app-flight-direction" aria-label="计划航班方向"><div><i></i><span>${appIcon("airplane")}</span><i></i></div><small>计划</small></div><div class="app-flight-time arrival"><div><small>${escapeHTML(flightOffsetLabel(arrival))}</small><strong>${escapeHTML(timeDisplay(arrival))}</strong></div><span>预计到达时间</span></div></div>
    <div class="app-flight-airports"><div><small>起飞机场</small><strong>${escapeHTML(flight.departureAirport || "—")}</strong><span>出发航站楼 ${escapeHTML(flight.departureTerminal?.trim() || "—")}</span></div><div><small>到达机场</small><strong>${escapeHTML(flight.arrivalAirport || "—")}</strong><span>到达航站楼 ${escapeHTML(flight.arrivalTerminal?.trim() || fallback.arrivalTerminal?.trim() || "—")}</span></div></div>
  </div>`;
}

function flightDetailsHTML(trip) {
  return flightResultHTML(trip.flight_info, readFlightSnapshot(trip, airportCrosswalk) || {}, {
    departureTime: trip.flight_departure_time,
    estimatedArrivalTime: trip.flight_estimated_arrival_time,
    arrivalTerminal: trip.flight_arrival_terminal
  });
}

function detailSection(title, subtitle, content) {
  return `<section class="form-section detail-section"><div class="form-section-title"><div><h3>${escapeHTML(title)}</h3>${subtitle ? `<p>${escapeHTML(subtitle)}</p>` : ""}</div></div><div class="detail-section-body">${content}</div></section>`;
}

function openTripDetail(trip) {
  const pending = !trip.is_completed && !trip.is_cancelled;
  const tripRows = (trip.stops || []).map((stop, index) => '<div><small>停靠点 ' + (index + 1) + '</small><strong>' + escapeHTML(stop.address) + '</strong></div>').join("");
  const fields = '<div class="detail-grid"><div><small>客户</small><strong>' + escapeHTML(trip.customer_name || "—") + '</strong></div><div><small>联系方式</small><strong>' + escapeHTML(trip.customer_contact || "—") + '</strong>' + tripContactActionsHTML(trip) + '</div><div><small>行程类型</small><strong>' + escapeHTML(trip.service_type || "接机") + '</strong></div><div><small>订单来源</small><strong>' + escapeHTML(trip.order_source || "普通客户") + '</strong></div><div><small>乘客人数</small><strong>' + escapeHTML(trip.customer_count || "1") + ' 位</strong></div><div><small>行李数量</small><strong>' + escapeHTML(trip.customer_stuff || "0") + ' 件</strong></div><div><small>行程状态</small><strong>' + tripStatus(trip) + '</strong></div><div><small>结算状态</small><strong>' + paymentStatus(trip) + '</strong></div><div><small>起始点</small><strong>' + escapeHTML(trip.location_start || "—") + '</strong></div>' + tripRows + '<div><small>目的地</small><strong>' + escapeHTML(trip.location_end || "—") + '</strong></div></div>';
  const flight = trip.flight_info ? detailSection('航班信息', '', flightDetailsHTML(trip) + `<div class="detail-flight-actions"><button type="button" class="button small" data-action="refresh-flight-card" data-id="${trip.id}">刷新航班</button></div>`) : '';
  const expenses = (trip.expenses || []).map(item => '<div class="finance-row"><span>' + escapeHTML(item.title) + (item.is_addition ? ' ＋' : ' −') + '</span><strong>' + currency(item.amount) + '</strong></div>').join("");
  const actions = '<button class="button small" data-action="copy-trip" data-id="' + trip.id + '">复制行程</button>' + (pending ? '<button class="button small" data-action="edit-trip" data-id="' + trip.id + '">编辑</button><button class="button small complete-action" data-action="toggle-complete" data-id="' + trip.id + '">已完成</button><button class="button small danger" data-action="cancel-trip" data-id="' + trip.id + '">取消行程</button><button class="button small danger" data-action="delete-trip" data-id="' + trip.id + '">删除</button>' : trip.is_cancelled ? '<button class="button small" data-action="restore-trip" data-id="' + trip.id + '">恢复行程</button>' : trip.is_completed ? '<button class="button small" data-action="restore-trip" data-id="' + trip.id + '">恢复待执行</button>' : '') + (!trip.is_paid ? '<button class="button small settle-action" data-action="toggle-paid" data-id="' + trip.id + '">财务结算</button>' : "");
  showModal("行程详情", '<div class="detail-summary"><div><strong>' + escapeHTML(trip.customer_name || "未填写客户") + '</strong><small>' + dateOnly(trip.appointment_date) + ' · ' + timeOnly(trip.appointment_time) + ' · ' + escapeHTML(trip.service_type || "接机") + '</small></div><strong>' + currency(trip.price) + '</strong></div>' +
    '<div class="detail-columns"><div class="detail-column">' + detailSection("行程信息", "", fields + (trip.order_source === '旅行社订单' ? `<div class="detail-grid"><div><small>旅行社订单号</small><strong>${escapeHTML(trip.travel_agency_order_number || '—')}</strong></div><div><small>旅行社</small><strong>${escapeHTML(trip.travel_agency_name || '—')} · ${escapeHTML(trip.travel_agency_code || '—')}</strong></div></div>` : '')) + '</div><div class="detail-column">' + flight +
    detailSection("财务结算", "", '<div class="detail-grid"><div><small>行程费用</small><strong>' + currency(trip.price) + '</strong></div><div><small>小费</small><strong>' + currency(trip.tip) + '</strong></div><div><small>净收入</small><strong>' + currency(netIncome(trip)) + '</strong></div></div>' + expenses) +
    '</div></div>' + (trip.memo ? '<p class="trip-memo">' + escapeHTML(trip.memo) + '</p>' : '') + '<div class="detail-actions">' + actions + '</div>', "editor-modal detail-modal");
}

function renderCustomers() {
  const query = state.search.trim().toLocaleLowerCase();
  const customers = state.customers.filter(customer => !query || [customer.name, customer.email, customer.travel_agency_name].join(" ").toLocaleLowerCase().includes(query));
  return `<div class="page-tools"><input class="search-input" data-search="customers" value="${escapeHTML(state.search)}" placeholder="搜索客户姓名、邮箱…"><button class="button primary" data-action="new-customer">＋ 新增客户</button></div>
    ${customers.length ? `<div class="customer-grid">${customers.map(customer => {
      const stats = customerStats(customer);
      const category = Number(customer.category) === 2 ? "旅行社" : "普通客户";
      const contacts = contactRows(customer.id).map(item => item.value).join(" · ");
      return `<article class="customer-card" data-action="view-customer" data-id="${customer.id}"><div class="customer-id"><div class="customer-initial">${escapeHTML((customer.name || "?").slice(0, 1))}</div><div class="customer-info"><strong>${escapeHTML(customer.name)}</strong><small>${category} · ${escapeHTML(languageName(customer.language_preference))}<br>${escapeHTML(contacts || customer.email || "暂无联系方式")}</small></div></div><div class="customer-stats"><span>${stats.trips} 次出行</span><strong class="customer-income">总收入 ${currency(stats.income)}</strong><strong class="customer-unpaid">未收款 ${currency(stats.unpaid)}</strong></div><div class="trip-meta"><button class="button small" data-action="edit-customer" data-id="${customer.id}">编辑</button><button class="button small danger" data-action="delete-customer" data-id="${customer.id}">删除</button></div></article>`;
    }).join("")}</div>` : emptyState("还没有客户资料", "新增客户后，手机端也会同步看到。", "customer")}`;
}

function renderAgencies() {
  const query = state.search.trim().toLocaleLowerCase();
  const agencies = state.agencies.filter(agency => !query || [agency.agency_code, agency.name, agency.contact_person, agency.phone].join(" ").toLocaleLowerCase().includes(query));
  return `<div class="page-tools"><input class="search-input" data-search="agencies" value="${escapeHTML(state.search)}" placeholder="搜索旅行社名称或代码…"><button class="button primary" data-action="new-agency">＋ 新增旅行社</button></div>
    ${agencies.length ? `<div class="agency-grid">${agencies.map(agency => `<article class="agency-card"><div class="customer-id"><div class="customer-initial">${appIcon("building.2.fill")}</div><div class="customer-info"><strong>${escapeHTML(agency.name)}</strong><small>代码：${escapeHTML(agency.agency_code)}<br>${escapeHTML(agency.contact_person || "暂无联系人")} ${escapeHTML(agency.phone || "")}</small></div></div><div class="trip-meta"><button class="button small" data-action="edit-agency" data-id="${agency.id}">编辑</button><button class="button small danger" data-action="delete-agency" data-id="${agency.id}">删除</button></div></article>`).join("")}</div>` : emptyState("还没有合作旅行社", "新增旅行社资料后可以在行程中选择。", "agency")}`;
}

function shiftFinanceAnchor(value, period, amount) {
  const date = new Date(value);
  if (period === "day" || period === "week") date.setDate(date.getDate() + amount * (period === "week" ? 7 : 1));
  if (period === "month" || period === "year") {
    const day = date.getDate();
    date.setDate(1);
    if (period === "month") date.setMonth(date.getMonth() + amount);
    else date.setFullYear(date.getFullYear() + amount);
    const lastDay = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    date.setDate(Math.min(day, lastDay));
  }
  return date;
}

function renderWallet() {
  const query = new URLSearchParams(location.hash.slice(1));
  const period = query.get("period") || "day";
  const anchor = query.has("anchor") ? new Date(`${query.get("anchor")}T12:00:00`) : new Date();
  const dayStart = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate());
  const start = new Date(dayStart);
  if (period === "week") start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  if (period === "month") start.setDate(1);
  if (period === "year") { start.setMonth(0, 1); }
  const end = new Date(start);
  if (period === "day") end.setDate(end.getDate() + 1);
  if (period === "week") end.setDate(end.getDate() + 7);
  if (period === "month") end.setMonth(end.getMonth() + 1);
  if (period === "year") end.setFullYear(end.getFullYear() + 1);
  const selected = state.trips.filter(trip => !trip.is_cancelled && new Date(trip.appointment_date) >= start && new Date(trip.appointment_date) < end);
  const entries=[];
  for(const trip of selected) {
    entries.push({title:'行程费用',amount:Math.max(0,Number(trip.price || 0)),isAddition:true},{title:'小费',amount:Math.max(0,Number(trip.tip || 0)),isAddition:true});
    for(const item of trip.expenses || []) entries.push({title:item.title,amount:item.amount,isAddition:Boolean(item.is_addition)});
  }
  const rows=financialCategoryGroups(entries);
  const totalVolume=rows.reduce((sum,row)=>sum+row.amount,0);
  const income=rows.reduce((sum,row)=>sum+row.incomeAmount,0);
  const expenses=rows.reduce((sum,row)=>sum+row.expenseAmount,0);
  const net = income - expenses;
  const colors = ["#a86be8", "#40b0d6", "#faa842", "#4f7df5", "#f26378", "#2ebaa0", "#c29945"];
  const chartLayer = (depth = false) => {
    const ring = rows.length && totalVolume > 0
      ? (() => {
          const radius = 80;
          const circumference = 2 * Math.PI * radius;
          let angle = 0;
          return rows.map((row, index) => {
            const sweep = row.amount / totalVolume * 360;
            const inset = Math.min(1.5, sweep / 3);
            const visibleSweep = Math.max(0, sweep - inset * 2);
            const dash = circumference * visibleSweep / 360;
            const offset = -circumference * (angle + inset) / 360;
            const opacity = (row.expense ? 0.78 : 1) * (depth ? 0.92 : 1);
            angle += sweep;
            return `<circle cx="100" cy="100" r="${radius}" fill="none" stroke="${colors[index % colors.length]}" stroke-opacity="${opacity}" stroke-width="32" stroke-linecap="round" stroke-dasharray="${dash} ${circumference - dash}" stroke-dashoffset="${offset}"/>`;
          }).join("");
        })()
      : `<circle cx="100" cy="100" r="80" fill="none" stroke="${depth ? "#d4d8e5" : "#e7eaf2"}" stroke-opacity="${depth ? 0.78 : 0.94}" stroke-width="24"/>`;
    return `<svg class="wallet-chart-svg" viewBox="0 0 200 200" aria-hidden="true"><g transform="rotate(-90 100 100)">${ring}</g></svg>`;
  };
  const dateTitle = period === "week" ? `${start.getFullYear()} 年\n${start.getMonth() + 1}/${start.getDate()} – ${new Date(end.getTime() - 86400000).getMonth() + 1}/${new Date(end.getTime() - 86400000).getDate()}` : period === "day" ? `${start.getFullYear()}年${start.getMonth() + 1}月${start.getDate()}日` : period === "month" ? `${start.getFullYear()}年${start.getMonth() + 1}月` : `${start.getFullYear()}年`;
  const periods = [["day", "天"], ["week", "本周"], ["month", "本月"], ["year", "年"]];
  return `<div class="finance-page">
    <div class="finance-period-picker" role="group" aria-label="财务日期范围">${periods.map(([key, label]) => `<button class="finance-period-option ${period === key ? "active" : ""}" aria-pressed="${period === key}" data-action="wallet-period" data-period="${key}">${label}</button>`).join("")}</div>
    <div class="wallet-date-navigator finance-date-navigator"><button class="button" data-action="wallet-shift" data-step="-1" aria-label="上一段日期">${appIcon("chevron.left")}</button><strong>${escapeHTML(dateTitle).replace("\n", "<br>")}</strong><button class="button" data-action="wallet-shift" data-step="1" aria-label="下一段日期">${appIcon("chevron.right")}</button></div>
    <section class="panel finance-summary" aria-label="收支图表">
      <div class="wallet-chart-shell"><div class="wallet-chart-depth">${chartLayer(true)}</div><div class="wallet-chart">${chartLayer()}<div class="wallet-chart-center"><small>总收入</small><strong>${currency(income)}</strong><span class="wallet-chart-divider"></span><small>净收入</small><strong class="wallet-net-value">${currency(net)}</strong></div></div></div>
      <div class="finance-category-list">${rows.map((row, index) => `<div class="finance-category"><div class="finance-category-heading"><i style="--category-color:${colors[index % colors.length]}"></i><span>${escapeHTML(row.name)}</span><small>${totalVolume ? (row.amount / totalVolume * 100).toFixed(1) : "0.0"}%</small></div><div class="finance-category-amount">${row.incomeAmount ? `<strong class="income">+${currency(row.incomeAmount)}</strong>` : ""}${row.expenseAmount ? `<strong class="expense">−${currency(row.expenseAmount)}</strong>` : ""}</div></div>`).join("") || `<div class="finance-empty"><strong>暂无收支</strong><small>所选日期内没有财务记录</small></div>`}</div>
    </section>
    <section class="panel finance-breakdown finance-snapshot-entry"><div class="section-heading"><h2>${appIcon("chart.pie.fill")} 收支明细</h2><div class="finance-snapshot-count"><span>${selected.length} 条行程</span><button class="button small quiet" data-action="finance-snapshots" data-start="${start.toISOString()}" data-end="${end.toISOString()}">${appIcon("list.bullet.rectangle")} 详细信息</button></div></div><div class="finance-totals"><div class="finance-total-tile income"><small>${appIcon("arrow.down.left")} 收入</small><strong>${currency(income)}</strong></div><div class="finance-total-tile expense"><small>${appIcon("arrow.up.right")} 支出</small><strong>${currency(expenses)}</strong></div></div></section>
    ${renderPaymentMethods()}
    ${renderAgencyStatementEntry()}
  </div>`;
}


let statementAgency = "";
let statementSelection = new Set();
let statementOwner = null;
let statementSnapshot = null;
function statementEntryDate(value) {
  const text=String(value || '');
  const date=new Date(/^\d{4}-\d{2}-\d{2}$/.test(text) ? text+'T12:00:00' : text);
  return Number.isNaN(date.valueOf()) ? ui('日期未填写') : new Intl.DateTimeFormat(uiLanguage(),{year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
}
function renderAgencyStatementEntry() {
  if (statementOwner !== state.user?.id) { statementOwner = state.user?.id; statementAgency = ""; statementSelection.clear(); statementSnapshot = null; }
  const eligible = state.trips.filter(t => t.order_source === '旅行社订单' && !t.is_paid && !t.is_cancelled);
  const agencies = [...new Map(eligible.map(t => [statementAgencyKey(t), t])).entries()].sort(([a],[b]) => a.localeCompare(b));
  const trips = agencyStatementTrips(state.trips, statementAgency);
  statementSelection = new Set([...statementSelection].filter(id => trips.some(t => t.id === id)));
  return `<section class="panel statement-entry"><div class="statement-entry-heading"><div><h2>${appIcon("list.bullet.rectangle")} ${escapeHTML(ui('对账单'))}</h2><p>${escapeHTML(ui('按旅行社核对未结算行程'))}</p></div></div><label class="statement-agency-field"><span>${escapeHTML(ui('旅行社'))}</span><select id="statementAgency"><option value="">${escapeHTML(ui('请选择旅行社'))}</option>${agencies.map(([key,t]) => `<option value="${escapeHTML(key)}" ${key === statementAgency ? 'selected' : ''}>${escapeHTML(t.travel_agency_name)} · ${escapeHTML(t.travel_agency_code)}</option>`).join('')}</select></label>${statementAgency ? `<div class="statement-selection-bar"><span>${escapeHTML(ui('%ld 条未结算行程', trips.length))} <small>${escapeHTML(ui('已选 %ld 条', statementSelection.size))}</small></span><div class="statement-selection-actions"><button class="button small quiet" data-action="statement-all">${escapeHTML(ui('全选'))}</button><button class="button small quiet" data-action="statement-none">${escapeHTML(ui('清空'))}</button></div></div><div class="statement-choices">${trips.map(t => `<label class="statement-choice ${statementSelection.has(t.id) ? 'is-selected' : ''}"><span class="statement-choice-content"><strong>${escapeHTML(t.customer_name || ui('未填写客人'))}</strong><small>${escapeHTML(statementEntryDate(t.appointment_date))} · ${timeOnly(t.appointment_time)}</small><small class="statement-order">${escapeHTML(ui('订单号'))} ${escapeHTML(t.travel_agency_order_number || ui('未填写'))}</small></span><input type="checkbox" aria-label="${escapeHTML(ui('选择 %@', t.customer_name || ui('行程')))}" data-statement-trip="${escapeHTML(t.id)}" ${statementSelection.has(t.id) ? 'checked' : ''}></label>`).join('') || `<p class="empty-hint">${escapeHTML(ui('暂无未结算行程'))}</p>`}</div><div class="statement-entry-footer"><p>${escapeHTML(ui('仅生成对账单，不改变结算状态'))}</p><button class="button primary" data-action="statement-preview" ${statementSelection.size ? '' : 'disabled'}>${escapeHTML(ui('对账单（%ld 条）', statementSelection.size))}</button></div>` : `<p class="empty-hint">${escapeHTML(ui('选择旅行社后，勾选需要对账的行程。'))}</p>`}</section>`;

}
function openAgencyStatement() {
  const trips = agencyStatementTrips(state.trips, statementAgency).filter(t => statementSelection.has(t.id));
  if (!trips.length) return;
  statementSnapshot = { ...buildAgencyStatement(trips, key => ui(key), uiLanguage()), title: ui('%@ 对账单', trips[0].travel_agency_name) };
  const report = statementSnapshot;
  showModal(report.title, `<p class="statement-intro">${escapeHTML(ui('%ld 条行程 · 未结算 · 仅供核对', trips.length))}</p><div class="statement-table-scroll"><table class="statement-table"><thead><tr>${report.headers.map(v => `<th>${escapeHTML(v)}</th>`).join('')}</tr></thead><tbody>${report.rows.map(row => `<tr>${row.map(v => `<td>${escapeHTML(String(v || '—'))}</td>`).join('')}</tr>`).join('')}</tbody></table></div><div class="statement-summary"><small>${escapeHTML(ui('本次对账合计'))}</small><div>${Object.entries(report.totals).map(([code,total]) => `<p><strong>${escapeHTML(ui('合计：%@', statementMoney(total, code)))}</strong></p>`).join('')}</div></div><p class="statement-footnote">${escapeHTML(ui('仅供对账，未改变结算状态。'))}</p><div class="form-actions"><button class="button primary" data-action="statement-share">${escapeHTML(ui('分享图片'))}</button><button class="button" data-action="statement-export">${escapeHTML(ui('导出 CSV'))}</button><button class="button" data-action="close-modal">${escapeHTML(ui('关闭'))}</button></div>`, 'agency-statement-modal');
}
async function shareAgencyStatement() {
  if (!statementSnapshot || statementOwner !== state.user?.id) return;
  const report = statementSnapshot;
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  ctx.font='14px sans-serif';
  const widths = report.headers.map((h,i) => i === 4 ? 260 : Math.max(72,Math.min(220,Math.max(...[h,...report.rows.map(r=>r[i])].flatMap(v=>String(v).split('\n')).map(v=>ctx.measureText(v).width))+24)));
  const width=widths.reduce((a,b)=>a+b,0)+48;
  const files=[];
  function wrap(value, maxWidth) {
    const lines=[];
    for (const paragraph of String(value ?? '—').split('\n')) {
      let line='';
      for(const char of paragraph) { if(line && ctx.measureText(line+char).width>maxWidth) { lines.push(line); line=char; } else line+=char; }
      lines.push(line);
    }
    return lines;
  }
  const pages=Math.max(1,Math.ceil(report.rows.length/15));
  for(let page=0;page<pages;page++) {
    ctx.font='14px sans-serif';
    const cells=report.rows.slice(page*15,(page+1)*15).map(row=>row.map((v,i)=>wrap(v,widths[i]-24)));
    const heights=cells.map(row=>Math.max(...row.map(lines=>lines.length))*21+26);
    const height=180+heights.reduce((a,b)=>a+b,0)+(page===pages-1?Object.keys(report.totals).length*30:0);
    canvas.width=width*2; canvas.height=height*2;
    ctx.scale(2,2); ctx.fillStyle='#ffffff'; ctx.fillRect(0,0,width,height);
    ctx.fillStyle='#35332f'; ctx.font='bold 22px sans-serif';ctx.fillText(report.title,24,35);
    ctx.fillStyle='#847b70';ctx.font='13px sans-serif';ctx.fillText(ui('%ld 条行程 · 仅供对账 · 第 %ld 页',report.rows.length,page+1)+` / ${pages}`,24,60);
    let y=80;
    function drawCellRow(row,h,header,index) {
      let x=24;
      row.forEach((lines,i)=>{
        ctx.fillStyle=header?'#f3f1ec':i===widths.length-1?'#f6efe6':index%2?'#faf9f6':'#ffffff';ctx.fillRect(x,y,widths[i],h);
        ctx.fillStyle=header?'#716b61':i===widths.length-1?'#775033':'#35332f';ctx.font=header?'bold 13px sans-serif':'14px sans-serif';
        ctx.textAlign=i>=6?'right':'left';
        lines.forEach((line,l)=>ctx.fillText(line,i>=6?x+widths[i]-12:x+12,y+24+l*21));
        ctx.strokeStyle='#e7e3dc';ctx.beginPath();ctx.moveTo(x,y+h);ctx.lineTo(x+widths[i],y+h);ctx.stroke();x+=widths[i];
      });y+=h;ctx.textAlign='left';
    }
    drawCellRow(report.headers.map(v=>[v]),40,true,0);
    cells.forEach((row,i)=>drawCellRow(row,heights[i],false,i));
    if(page===pages-1) {ctx.fillStyle='#775033';ctx.font='bold 18px sans-serif'; for(const [code,total] of Object.entries(report.totals)){y+=30;ctx.fillText(ui('合计：%@',statementMoney(total,code)),24,y);}}
    ctx.fillStyle='#847b70';ctx.font='12px sans-serif';ctx.fillText('仅供对账，未改变结算状态。',24,height-16);
    const encoded=canvas.toDataURL('image/png').split(',')[1];
    if(!encoded) throw Error(ui('对账单图片生成失败，请重新打开后重试。'));
    const binary=atob(encoded);const bytes=new Uint8Array(binary.length);
    for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
    const blob=new Blob([bytes],{type:'image/png'});
    files.push(new File([blob],`旅行社对账单-${page+1}.png`,{type:'image/png'}));
  }
  if(statementOwner!==state.user?.id) return;
  if(navigator.canShare?.({files})) {
    try { await navigator.share({files,title:report.title}); return; }
    catch(error) {if(error.name==='AbortError') return;}
  }
  for(const file of files) {const url=URL.createObjectURL(file);const link=document.createElement('a');link.href=url;link.download=file.name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  showToast(ui('已下载对账单图片，可在微信中选择图片发送。'));
}

function exportAgencyStatement() {
  if (!statementSnapshot || statementOwner !== state.user?.id) return;
  const r = statementSnapshot;
  const safe = value => { const v = String(value ?? ''); return /^[=+@\-\t\r]/.test(v) ? "'" + v : v; };
  const csv = [[r.title],r.headers,...r.rows,...Object.entries(r.totals).map(([c,n]) => ['合计',statementMoney(n,c)])].map(row => row.map(v => '"' + safe(v).replaceAll('"','""') + '"').join(',')).join('\r\n');
  const url = URL.createObjectURL(new Blob(['\uFEFF' + csv], {type:'text/csv;charset=utf-8'}));
  const link = document.createElement('a'); link.href=url; link.download='旅行社对账单.csv'; link.click(); setTimeout(() => URL.revokeObjectURL(url),1000);
}

function openFinanceSnapshots(start, end) {
  const trips = state.trips.filter(trip => !trip.is_cancelled && new Date(trip.appointment_date) >= new Date(start) && new Date(trip.appointment_date) < new Date(end))
    .sort((a, b) => Date.parse(a.appointment_date) - Date.parse(b.appointment_date) || Date.parse(a.appointment_time) - Date.parse(b.appointment_time) || String(a.id).localeCompare(String(b.id)));
  const cards = trips.map(trip => {
    const details = renderTripCard(trip, { readOnly: true });
    return `<details class="finance-trip-snapshot"><summary><span class="finance-snapshot-date"><strong>${timeOnly(trip.appointment_time)}</strong><small>${escapeHTML(new Date(trip.appointment_date).toLocaleDateString("zh-CN", {year:"numeric",month:"2-digit",day:"2-digit"}))}</small></span><strong class="finance-snapshot-guest">${escapeHTML(trip.customer_name || "未填写客户")}</strong><strong>${currency(netIncome(trip))}</strong><span class="finance-snapshot-arrow" aria-label="查看行程情况">${appIcon("chevron.right")}</span></summary><div class="finance-snapshot-record">${details}</div></details>`;
  }).join("");
  showModal("行程快照", `<div class="finance-snapshot-list">${cards || '<p class="empty-hint">所选日期内没有行程</p>'}</div><div class="form-actions"><button class="button" data-action="close-modal">关闭</button></div>`, "finance-snapshot-modal");
}

const financeRecordAnimations = new WeakMap();
function toggleFinanceRecord(details) {
  const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  if (reduceMotion || typeof details.animate !== "function") { details.open = !details.open; return; }
  const previous = financeRecordAnimations.get(details);
  const opening = previous ? !previous.opening : !details.open;
  const start = details.getBoundingClientRect().height;
  if (previous) previous.animation.cancel();
  details.style.overflow = "hidden";
  details.open = true;
  const expanded = details.getBoundingClientRect().height;
  const summary = details.querySelector("summary");
  const styles = window.getComputedStyle(details);
  const collapsed = summary.getBoundingClientRect().height + parseFloat(styles.paddingTop) + parseFloat(styles.paddingBottom) + parseFloat(styles.borderTopWidth) + parseFloat(styles.borderBottomWidth);
  const animation = details.animate([{ height: `${start}px` }, { height: `${opening ? expanded : collapsed}px` }], { duration: 440, easing: "cubic-bezier(.22,.61,.36,1)" });
  financeRecordAnimations.set(details, { animation, opening });
  animation.onfinish = () => {
    if (financeRecordAnimations.get(details)?.animation !== animation) return;
    details.open = opening;
    details.style.overflow = "";
    financeRecordAnimations.delete(details);
  };
}

function imageDataURL(base64) { return base64 ? `data:image/jpeg;base64,${base64}` : ""; }
async function storageRequest(path, { method = "GET", body, contentType, queueOffline = true, offlinePath } = {}) {
  const requestUserID = state.user?.id;
  const requestGeneration = workspaceGeneration;
  const session = await currentSession();
  if (!session) throw new Error("云端登录状态已失效，请重新登录。");
  if (!requestUserID || (state.user?.id !== requestUserID || workspaceGeneration !== requestGeneration) || session.user?.id !== requestUserID) {
    throw new Error("账号已切换，请重新加载当前账号资料。");
  }
  await ensureAccountDevice();
  if(workspaceGeneration!==requestGeneration || state.user?.id!==requestUserID)throw Error('账号会话已变化，已停止旧图片请求。');
  const queueUpload = async () => {
    const bytes = new Uint8Array(await body.arrayBuffer());
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
    persistOfflineOperation({ kind: "storage-upload", path, base64: btoa(binary), contentType: contentType || "image/jpeg" }, requestUserID);
  };
  if (queueOffline && method === "POST" && queuedOperationCount() > 0) {
    await queueUpload();
    return { ok: true, queued: true };
  }
  if (queueOffline && method === "DELETE" && state.productEdition !== "cloud"
      && (queuedOperationCount() > 0 || !navigator.onLine)) {
    persistOfflineOperation({ kind: "storage-delete", path: offlinePath || path }, requestUserID);
    return { ok: true, queued: true };
  }
  let response;
  try {
    response = await networkFetch(`${SUPABASE_URL}/storage/v1/${path}`, {
      method,
      cache: state.productEdition === "cloud" ? "no-store" : "default",
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${session.access_token}`,
        'x-account-device-id': accountDeviceID(),
        ...(contentType ? { "Content-Type": contentType } : {}),
        ...(method === "POST" ? { "x-upsert": "true" } : {}),
      },
      body,
    });
  } catch (error) {
    if(workspaceGeneration !== requestGeneration || state.user?.id !== requestUserID) throw Error('账号会话已变化，已停止旧请求。');
    if (!queueOffline || !isNetworkFailure(error)) throw error;
    if (method === "POST") {
      await queueUpload();
      return { ok: true, queued: true };
    }
    if (method === "DELETE" && state.productEdition !== "cloud") {
      persistOfflineOperation({ kind: "storage-delete", path: offlinePath || path }, requestUserID);
      return { ok: true, queued: true };
    }
    throw error;
  }
  if ((state.user?.id !== requestUserID || workspaceGeneration !== requestGeneration)) throw new Error("账号已切换，请重新加载当前账号资料。");
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    const error = new Error(payload.message || payload.error || "云端图片存储失败，请确认已应用 Storage 配置。");
    error.status = response.status;
    throw error;
  }
  return response;
}
function objectPath(path) { return path.split("/").map(encodeURIComponent).join("/"); }
async function imageAsJpeg(base64) {
  const response = await fetch(imageDataURL(base64));
  const bitmap = await createImageBitmap(await response.blob());
  const canvas = document.createElement("canvas");
  const scale = Math.min(1, 2048 / Math.max(bitmap.width, bitmap.height));
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  canvas.getContext("2d").drawImage(bitmap, 0, 0);
  bitmap.close();
  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.88));
  if (!blob) throw new Error("图片转换失败，请重新选择图片。");
  return blob;
}
function accountAssetImagePaths(column, value) {
  if (!value || typeof value !== "object") return [];
  if (column === "business_card_data") {
    return [value.portraitPath, ...(value.qrCodes || []).map(item => item.imagePath)].filter(path => typeof path === "string" && path);
  }
  return (value.methods || []).map(item => item.qrImagePath).filter(path => typeof path === "string" && path);
}
function isOwnedAccountAssetPath(path, ownerID) {
  const components = String(path || "").split("/");
  let decodedComponents;
  try { decodedComponents = components.map(component => decodeURIComponent(component)); }
  catch { return false; }
  return decodedComponents.length >= 2 && decodedComponents[0] === ownerID
    && decodedComponents.every(component => component && component !== "." && component !== ".." && !/[\\/]/.test(component));
}
async function removeAccountAssetImage(path, ownerID, queueOffline = false) {
  if (!isOwnedAccountAssetPath(path, ownerID)) throw new Error("图片路径不属于当前账号，已阻止删除。");
  return storageRequest("object/account-assets", {
    method: "DELETE", body: JSON.stringify({ prefixes: [path] }),
    contentType: "application/json", queueOffline, offlinePath: path,
  });
}
async function hydrateAccountAssets() {
  const ownerID=state.user?.id;if(!ownerID)throw Error('请先登录云端账号。');
  const card=state.businessCard, methods=state.paymentMethods;
  const cache=state.assetImageCache || (state.assetImageCache=new Map());
  async function fill(item,pathKey,dataKey,current) {
    const path=item[pathKey];if(!path||item[dataKey])return;
    if(!isOwnedAccountAssetPath(path,ownerID))throw Error('图片路径不属于当前账号。');
    const response=await storageRequest(`object/authenticated/account-assets/${objectPath(path)}`);
    const bytes=new Uint8Array(await response.arrayBuffer());
    if(state.user?.id!==ownerID||!current()||item[pathKey]!==path||item[dataKey])return;
    let binary='';for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));
    const data=btoa(binary);item[dataKey]=data;cache.set(path,data);
  }
  await fill(card,'portraitPath','portraitData',()=>state.businessCard===card);
  for(const qr of card.qrCodes||[])await fill(qr,'imagePath','imageData',()=>state.businessCard===card&&card.qrCodes.includes(qr));
  for(const method of methods)await fill(method,'qrImagePath','qrImageData',()=>state.paymentMethods===methods&&methods.includes(method));
}
function renderPaymentMethods() {
  return `<section class="panel account-asset-panel"><div class="section-heading"><h2>${appIcon("qrcode")} 收款方式</h2><button class="button small" data-action="add-payment-method">${appIcon("plus")} 添加</button></div>${state.paymentMethods.length ? `<div class="asset-list">${state.paymentMethods.map(method => `<article class="asset-row"><button class="asset-image-button" data-action="preview-payment-qr" data-id="${escapeHTML(method.id)}" ${method.qrImageData ? "" : "disabled"}>${method.qrImageData ? `<img src="${imageDataURL(method.qrImageData)}" alt="${escapeHTML(method.name || "收款二维码")}">` : `<span>添加二维码</span>`}</button><div class="asset-row-content"><label>收款方式名称<input data-payment-name="${escapeHTML(method.id)}" value="${escapeHTML(method.name || "")}" placeholder="例如：Zelle"></label><label class="button small asset-upload">${method.qrImageData ? "更换二维码" : "选择二维码图片"}<input type="file" accept="image/*" data-payment-image="${escapeHTML(method.id)}"></label></div><button class="button small danger" data-action="remove-payment-method" data-id="${escapeHTML(method.id)}" aria-label="删除收款方式">${appIcon("trash")}</button></article>`).join("")}</div>` : `<p class="empty-hint">添加收款方式名称和二维码，方便向客户展示。</p>`}</section>`;
}

function renderBusinessCard() {
  const card = state.businessCard;
  const metadata = state.user?.user_metadata || {};
  const name = metadata.salutation || "未填写";
  const phone = metadata.phone || "未填写";
  const email = state.user?.email || "未填写";
  const portrait = card.portraitData ? `<img src="${imageDataURL(card.portraitData)}" alt="名片头像">` : `<span>人像</span>`;
  const styleName = Number(card.style) === 1 ? "金属质感" : "简洁平版";
  return `<section class="business-card-editor"><div class="panel business-card-settings"><div class="business-card-photo"><label class="business-avatar-picker">${portrait}<span>更换头像<input type="file" accept="image/*" data-card-photo></span></label>${card.portraitData ? `<button class="button small danger" data-action="remove-card-photo">删除头像</button>` : ""}</div><div class="readonly-profile"><label>姓名<input readonly value="${escapeHTML(name)}"></label><label>电话<input readonly value="${escapeHTML(phone)}"></label><label>电子邮箱<input readonly value="${escapeHTML(email)}"></label></div><label class="field">昵称<input data-card-field="nickname" value="${escapeHTML(card.nickname || "")}" placeholder="输入名片上显示的昵称"></label><div class="field"><label>名片样式</label><div class="business-style-options"><button class="business-style-option ${Number(card.style) === 0 ? "selected" : ""}" data-action="card-style" data-style="0"><strong>样式一</strong><small>简洁平版</small></button><button class="business-style-option ${Number(card.style) === 1 ? "selected" : ""}" data-action="card-style" data-style="1"><strong>样式二</strong><small>金属质感</small></button></div></div><button class="button primary" data-action="save-business-card">保存名片</button></div><div class="business-card-preview ${Number(card.style) === 1 ? "metallic" : "flat"}"><div class="preview-heading">${card.portraitData ? `<img src="${imageDataURL(card.portraitData)}" alt="">` : `<span>${escapeHTML(String(name).slice(0, 1))}</span>`}<div><strong>${escapeHTML(card.nickname || name)}</strong><small>${escapeHTML(name)}</small></div></div><div class="preview-contact"><span>${escapeHTML(phone)}</span><span>${escapeHTML(email)}</span></div><small>${styleName}</small></div></section><section class="panel account-asset-panel"><div class="section-heading"><h2>二维码</h2><button class="button small" data-action="add-card-qr">${appIcon("plus")} 添加</button></div>${card.qrCodes.length ? `<div class="asset-list">${card.qrCodes.map(qr => `<article class="asset-row"><button class="asset-image-button" data-action="preview-card-qr" data-id="${escapeHTML(qr.id)}" ${qr.imageData ? "" : "disabled"}>${qr.imageData ? `<img src="${imageDataURL(qr.imageData)}" alt="${escapeHTML(qr.name || "二维码")}">` : `<span>添加二维码</span>`}</button><div class="asset-row-content"><label>二维码名称<input data-card-qr-name="${escapeHTML(qr.id)}" value="${escapeHTML(qr.name || "")}" placeholder="例如：微信"></label><label class="button small asset-upload">${qr.imageData ? "更换二维码" : "选择二维码图片"}<input type="file" accept="image/*" data-card-qr-image="${escapeHTML(qr.id)}"></label></div><button class="button small danger" data-action="remove-card-qr" data-id="${escapeHTML(qr.id)}">删除</button></article>`).join("")}</div>` : `<p class="empty-hint">添加微信、LINE 或其他联系二维码。</p>`}</section>`;
}

async function cloudAssetValue(column, value, ownerID, uploadedPaths = []) {
  const cloudValue = structuredClone(value);
  const saveImage = async (item, dataKey, pathKey, path) => {
    if (!item[dataKey]) return;
    const cache=state.assetImageCache || (state.assetImageCache=new Map());
    if(item[pathKey] && cache.get(item[pathKey])===item[dataKey]) { delete item[dataKey]; return; }
    const originalData=item[dataKey];
    const jpeg = await imageAsJpeg(item[dataKey]);
    if(state.user?.id !== ownerID) throw Error('账号已切换，未上传图片。');
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await jpeg.arrayBuffer()))).map(n=>n.toString(16).padStart(2,'0')).join('');
    const objectName = `${ownerID}/${path.replace(/\.jpg$/, '')}-${digest}.jpg`;
    if(item[pathKey] !== objectName) {
      const upload = await storageRequest(`object/account-assets/${objectPath(objectName)}`, {method:'POST',body:jpeg,contentType:'image/jpeg'});
      if(!upload?.queued)uploadedPaths.push(objectName);
    }
    if(state.user?.id !== ownerID) throw Error('账号已切换，已忽略旧图片结果。');
    cache.set(objectName,originalData);
    item[pathKey] = objectName;
    delete item[dataKey];
  };
  if (column === "business_card_data") {
    await saveImage(cloudValue, "portraitData", "portraitPath", "business-card/portrait.jpg");
    for (const qr of cloudValue.qrCodes || []) {
      qr.id ||= crypto.randomUUID();
      await saveImage(qr, "imageData", "imagePath", `business-card/qr/${qr.id}.jpg`);
    }
  } else {
    for (const method of cloudValue.methods || []) {
      method.id ||= crypto.randomUUID();
      await saveImage(method, "qrImageData", "qrImagePath", `payment-methods/${method.id}.jpg`);
    }
  }
  return cloudValue;
}
async function persistAccountAsset(column, value, removedPaths = []) {
  const ownerID = state.user?.id;
  if (!ownerID) throw new Error("请先登录云端账号。");
  const previousSettings = state.settings || defaultSettings();
  const updatedAt = new Date().toISOString();
  let cloudValue;
  const uploadedPaths = [];
  let row;
  try {
    cloudValue = await cloudAssetValue(column, value, ownerID, uploadedPaths);
    if (state.user?.id !== ownerID) throw new Error("账号已切换，请重新加载当前账号资料。");
    if (column === "business_card_data") {
      if (cloudValue.portraitPath) value.portraitPath = cloudValue.portraitPath;
      for (const item of value.qrCodes || []) {
        const saved = (cloudValue.qrCodes || []).find(candidate => candidate.id === item.id);
        if (saved?.imagePath) item.imagePath = saved.imagePath;
      }
    } else {
      for (const item of value.methods || []) {
        const saved = (cloudValue.methods || []).find(candidate => candidate.id === item.id);
        if (saved?.qrImagePath) item.qrImagePath = saved.qrImagePath;
      }
    }
    row = { owner_id: ownerID, [column]: cloudValue, [`${column}_updated_at`]: updatedAt, updated_at: updatedAt };
    await upsert("user_settings", row, "owner_id");
    if (state.user?.id !== ownerID) throw new Error("账号已切换，请重新加载当前账号资料。");
  } catch (error) {
    throw error;
  }
  state.settings = { ...previousSettings, ...row };
  // Shared immutable objects are retained. Deletion needs server-side reference
  // checks; a delayed client or an ambiguous commit can still reference them.
  return { cleanupFailed: false };
}

async function saveBusinessCard(silent = false, removedPaths = []) {
  const result = await persistAccountAsset("business_card_data", state.businessCard, removedPaths);
  if (!silent) showToast(result.cleanupFailed ? "名片已同步，但旧图片未能全部清理，请重新保存重试。" : "名片已保存并同步到云端。", result.cleanupFailed);
}

async function savePaymentMethods(silent = false, removedPaths = []) {
  const result = await persistAccountAsset("wallet_payment_methods", { methods: state.paymentMethods }, removedPaths);
  if (!silent) showToast(result.cleanupFailed ? "收款方式已同步，但旧图片未能全部清理，请重新保存重试。" : "收款方式已保存并同步到云端。", result.cleanupFailed);
}

async function readImageBase64(file) {
  if (!file.type.startsWith("image/")) throw new Error("请选择图片文件。");
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  return btoa(binary);
}

async function setCardPhoto(file) { return setQRImage('portrait','portrait',file); }
async function setQRImage(kind,id,file) {
  const ownerID=state.user?.id;
  const card=state.businessCard,methods=state.paymentMethods;
  const tokens=state.assetReadTokens || (state.assetReadTokens={}),key=`${kind}:${id}`,token=crypto.randomUUID();tokens[key]=token;
  try {
    const imageData=await readImageBase64(file);
    if(state.user?.id!==ownerID||tokens[key]!==token)return;
    if(kind==='portrait') {
      if(state.businessCard!==card)return;
      card.portraitData=imageData;await saveBusinessCard();
    } else if(kind==='card') {
      if(state.businessCard!==card)return;
      const qr=card.qrCodes.find(q=>q.id===id);if(!qr)return;
      qr.imageData=imageData;await saveBusinessCard();
    } else {
      if(state.paymentMethods!==methods)return;
      const method=methods.find(m=>m.id===id);if(!method)return;
      method.qrImageData=imageData;await savePaymentMethods();
    }
    if(state.user?.id===ownerID)updatePageContent();
  } catch(error) {if(state.user?.id===ownerID)showToast(error.message||'图片保存失败。',true);}
}

function showQRPreview(title, data, name, kind, id) {
  if (!data) return;
  showModal(name || title, `<div class="qr-preview"><img src="${imageDataURL(data)}" alt="${escapeHTML(name || title)}"><button class="button primary" data-action="share-qr" data-kind="${kind}" data-id="${escapeHTML(id)}">分享二维码</button></div>`, "qr-preview-modal");
}

async function shareQR(kind, id) {
  const item = kind === "card"
    ? state.businessCard.qrCodes.find(qr => qr.id === id)
    : state.paymentMethods.find(method => method.id === id);
  const data = kind === "card" ? item?.imageData : item?.qrImageData;
  if (!data) return;
  const blob = await (await fetch(imageDataURL(data))).blob();
  const file = new File([blob], `${(item.name || "二维码").replace(/[\\/:*?"<>|]/g, "_")}.jpg`, { type: blob.type || "image/jpeg" });
  if (navigator.share && (!navigator.canShare || navigator.canShare({ files: [file] }))) {
    try { await navigator.share({ title: item.name || "二维码", files: [file] }); }
    catch (error) { if (error.name !== "AbortError") throw error; }
  } else {
    const link = document.createElement("a");
    link.href = imageDataURL(data);
    link.download = file.name;
    link.click();
    showToast("二维码已下载，可以通过设备的分享功能发送。");
  }
}

function settingsCurrencyLabel(region, currency, symbol, fallbackRegion, fallbackCurrency) {
  let country = fallbackRegion, name = fallbackCurrency;
  try {
    country = new Intl.DisplayNames([uiLanguage()], {type:'region'}).of(region) || country;
    name = new Intl.DisplayNames([uiLanguage()], {type:'currency'}).of(currency) || name;
  } catch { /* Older browsers retain readable source labels and the stable currency code. */ }
  return `${country} · ${symbol} ${name} (${currency})`;
}
function renderSettings() {
  const settings = state.settings || defaultSettings();
  const countries = [["US", "美国", "美元", "US Dollar", "USD", "$"], ["CA", "加拿大", "加拿大元", "Canadian Dollar", "CAD", "CA$"], ["CN", "中国", "人民币", "Chinese Yuan", "CNY", "¥"], ["GB", "英国", "英镑", "British Pound", "GBP", "£"], ["JP", "日本", "日元", "Japanese Yen", "JPY", "¥"], ["KR", "韩国", "韩元", "South Korean Won", "KRW", "₩"], ["ES", "西班牙", "欧元", "Euro", "EUR", "€"], ["FR", "法国", "欧元", "Euro", "EUR", "€"], ["DE", "德国", "欧元", "Euro", "EUR", "€"], ["AU", "澳大利亚", "澳元", "Australian Dollar", "AUD", "A$"], ["HK", "中国香港", "港元", "Hong Kong Dollar", "HKD", "HK$"], ["TW", "中国台湾", "新台币", "New Taiwan Dollar", "TWD", "NT$"], ["SG", "新加坡", "新加坡元", "Singapore Dollar", "SGD", "S$"], ["MX", "墨西哥", "墨西哥比索", "Mexican Peso", "MXN", "MX$"], ["IN", "印度", "印度卢比", "Indian Rupee", "INR", "₹"], ["CH", "瑞士", "瑞士法郎", "Swiss Franc", "CHF", "CHF"]];
  const configuredNavigation = state.settings?.navigation_provider;
  const navigation = getAccountPreference("navigation") || (configuredNavigation === "apple_maps" ? "appleMaps" : configuredNavigation || "appleMaps");
  const selectedCurrency = countries.find(([code]) => code === settings.currency_country_code) || countries[0];
  const languageCode = normalizedLanguageCode(settings.language_code);
  return `<section class="panel" style="max-width:760px"><div class="section-heading" style="margin-top:0"><h2>${escapeHTML(ui('账户偏好'))}</h2></div><form id="settingsForm"><div class="form-grid"><div class="field"><label for="language">${escapeHTML(ui('语言偏好'))}</label><select id="language" name="language_code"><option value="zh-Hans" ${languageCode === "zh-Hans" ? "selected" : ""}>简体中文</option><option value="zh-Hant" ${languageCode === "zh-Hant" ? "selected" : ""}>繁體中文</option><option value="en" ${languageCode === "en" ? "selected" : ""}>English</option><option value="ja" ${languageCode === "ja" ? "selected" : ""}>日本語</option><option value="ko" ${languageCode === "ko" ? "selected" : ""}>한국어</option><option value="es" ${languageCode === "es" ? "selected" : ""}>Español</option></select><small>${escapeHTML(ui('偏好保存至云端；导航、设置、对账单和部分账号页面支持所选语言，其余业务页面仍在补齐翻译。'))}</small></div><div class="field"><label for="currency">${escapeHTML(ui('国家和地区 · 本位币'))}</label><select id="currency" name="currency_country_code">${countries.map(([code, country, currencyName, currencyEnglish, currencyCode, symbol]) => `<option value="${code}" ${settings.currency_country_code === code ? "selected" : ""}>${escapeHTML(settingsCurrencyLabel(code,currencyCode,symbol,country,currencyName))}</option>`).join("")}</select><small>${escapeHTML(settingsCurrencyLabel(selectedCurrency[0],selectedCurrency[4],selectedCurrency[5],selectedCurrency[1],selectedCurrency[2]))}</small></div><div class="field"><label for="navigation_provider">${escapeHTML(ui('默认导航'))}</label><select id="navigation_provider" name="navigation_provider"><option value="appleMaps" ${navigation === "appleMaps" ? "selected" : ""}>${escapeHTML(ui('Apple 地图'))}</option><option value="googleMaps" ${navigation === "googleMaps" ? "selected" : ""}>Google Maps</option></select></div></div><p class="muted">${escapeHTML(ui('航班查询由云端安全代理处理，无需在浏览器保存飞友密钥。'))}</p><button class="button primary" type="submit">${escapeHTML(ui('保存设置'))}</button></form></section>
    <section class="panel expense-catalog-panel" style="max-width:760px;margin-top:14px"><div class="section-heading" style="margin-top:0"><div><h2>${escapeHTML(ui('费用项目'))}</h2><p>${escapeHTML(ui('这些名称会用于财务结算选择。默认包含居间费和高速通行费。'))}</p></div><button class="button small" data-action="add-expense-name">${appIcon("plus")} ${escapeHTML(ui('添加项目'))}</button></div><div class="expense-name-list">${expenseCatalog().map(name => `<div class="expense-name-row"><input data-expense-name value="${escapeHTML(name)}"><button class="button small danger" data-action="remove-expense-name">−</button></div>`).join("")}</div><button class="button primary" data-action="save-expense-catalog" style="margin-top:12px">${escapeHTML(ui('保存费用项目'))}</button></section>
    <section class="panel" style="max-width:760px;margin-top:14px"><div class="section-heading" style="margin-top:0"><h2>${escapeHTML(ui('版本信息'))}</h2></div><button class="button" data-action="build-information">${escapeHTML(ui('版本信息'))}</button></section>
    <section class="panel" style="max-width:760px;margin-top:14px"><div class="section-heading" style="margin-top:0"><h2>${escapeHTML(ui('云端账户'))}</h2></div><div class="customer-info"><strong>${escapeHTML(state.user?.email || "")}</strong><small>${escapeHTML(ui('使用同一云端账号与 iPhone 应用同步。'))}</small></div><button class="button danger" data-action="delete-cloud-account">${escapeHTML(ui('删除云端账号'))}</button><p><a href="./privacy.html" target="_blank">${escapeHTML(ui('隐私政策'))}</a> · <a href="./support.html" target="_blank">${escapeHTML(ui('帮助与支持'))}</a></p></section>`;
}

function showAccountDeletion() {
  showModal(ui('删除云端账号'), `<form id="deleteAccountForm">${!state.session?`<label class="field">${escapeHTML(ui('账号邮箱'))}<input name="email" type="email" autocomplete="username" required></label>`:''}<p>${escapeHTML(ui('将永久删除当前云端账号、客户、行程、财务记录及名片附件，无法恢复。其他账号不受影响。'))}</p><p>${escapeHTML(ui('删除账号不会自动取消 Apple 订阅，请先在系统订阅管理中取消续费。'))} <a href="https://apps.apple.com/account/subscriptions/" target="_blank" rel="noopener">${escapeHTML(ui('取消订阅续费'))}</a></p><label class="field">${escapeHTML(ui('当前密码'))}<input name="password" type="password" autocomplete="current-password" required></label><label class="field">${escapeHTML(ui('输入 DELETE 确认'))}<input name="confirmation" required pattern="DELETE" autocomplete="off"></label><button class="button danger" type="submit">${escapeHTML(ui('永久删除此云端账号'))}</button></form>`);
}
async function submitAccountDeletion(form) {
  const fields=new FormData(form);
  if(fields.get('confirmation')!=='DELETE')throw Error(ui('请输入 DELETE 确认删除。'));
  const session=state.session ? await currentSession() : await authRequest('token?grant_type=password',{email:String(fields.get('email')||'').trim().toLowerCase(),password:fields.get('password')});
  const owner=session?.user?.id;
  if(!owner)throw Error(ui('请重新验证邮箱和密码。'));
  let response;
  try {response=await networkFetch(`${SUPABASE_URL}/functions/v1/delete-account`,{method:'POST',headers:{apikey:SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({password:fields.get('password'),confirmation:'DELETE'})});}
  finally {form.elements.password.value='';}
  const result=await response.json();
  if(!response.ok||result.deleted!==true)throw Error(result.error||ui('删除未完成，请稍后重试。'));
  localStorage.removeItem(offlineQueueKey(owner));localStorage.removeItem(offlineCacheKey(owner));localStorage.removeItem(`${ACCOUNT_PREFERENCE_PREFIX}${owner}.product-edition`);
  document.getElementById('modal-root')?.remove();
  if(state.user && state.user.id!==owner)return;
  const notice=ui('云端账号及关联资料已删除。');
  clearSession();resetAccountWorkspace();authNotice=notice;renderLogin();
}

function showModal(title, content, className = "") {
  document.getElementById("modal-root")?.remove();
  const customerActions = className.includes("trip-editor-modal")
    ? `<button class="button quiet small" data-action="close-modal">取消</button><h2>${title}</h2><button class="button primary small" type="submit" form="tripForm">保存</button>`
    : className.includes("customer-editor-modal")
    ? `<button class="button quiet small" data-action="close-modal">取消</button><h2>${title}</h2><button class="button primary small" type="submit" form="customerForm">${title === "新增客户" ? "保存" : "保存修改"}</button>`
    : `<h2>${title}</h2><button class="button quiet small" data-action="close-modal" aria-label="关闭">${appIcon("xmark")}</button>`;
  document.body.insertAdjacentHTML("beforeend", `<div id="modal-root" class="modal-backdrop ${className.includes("finance-snapshot-modal") ? "finance-snapshot-backdrop" : ""}"><section class="modal ${className}"><header class="modal-head">${customerActions}</header>${content}</section></div>`);
}

function formField(label, name, value = "", type = "text", options = {}) {
  const id = `field-${name}`;
  const flightAttributes = name === "flight_info" ? ' data-flight-number inputmode="text" autocapitalize="characters" autocomplete="off"' : "";
  const common = `id="${id}" name="${name}" ${options.required ? "required" : ""} ${options.placeholder ? `placeholder="${escapeHTML(options.placeholder)}"` : ""}${flightAttributes}`;
  if (options.select) return `<div class="field ${options.span ? "span-2" : ""}"><label for="${id}">${label}</label><select ${common}>${options.select.map(([v, text]) => `<option value="${escapeHTML(v)}" ${String(value) === String(v) ? "selected" : ""}>${escapeHTML(text)}</option>`).join("")}</select></div>`;
  if (type === "textarea") return `<div class="field ${options.span ? "span-2" : ""}"><label for="${id}">${label}</label><textarea ${common}>${escapeHTML(value)}</textarea></div>`;
  return `<div class="field ${options.span ? "span-2" : ""}"><label for="${id}">${label}</label><input ${common} type="${type}" value="${escapeHTML(value)}"></div>`;
}

function modalActions(submitLabel = "保存") {
  return `<div class="form-actions"><button type="button" class="button" data-action="close-modal">取消</button><button type="submit" class="button primary">${submitLabel}</button></div>`;
}

function formSection(title, subtitle, fields, className = "") {
  return `<section class="form-section${className ? ` ${escapeHTML(className)}` : ""}"><div class="form-section-title"><div><h3>${title}</h3><p>${subtitle}</p></div></div><div class="form-grid">${fields}</div></section>`;
}

function serviceTypePicker(value = "接机") {
  const services = ["接机", "送机", "接送", "包车", "转机", "其它"];
  const selectedValue = value === "其他" ? "其它" : value;
  return `<fieldset class="field span-2 service-type-field"><legend>行程类型</legend><div class="service-type-picker">${services.map(name => `<label class="service-type-option ${name === selectedValue ? "selected" : ""}"><input type="radio" name="service_type" value="${name}" ${name === selectedValue ? "checked" : ""} required><span class="service-type-icon">${appIcon(name === selectedValue ? "checkmark.circle.fill" : serviceSymbol(name, "picker"))}</span><span>${name}</span></label>`).join("")}</div></fieldset>`;
}

function orderSourcePicker(value = "普通客户", code = "", name = "", orderNumber = "") {
  const agencyOrder = value === "旅行社订单";
  return `<fieldset class="field span-2 order-source-field"><legend>订单来源</legend><div class="order-source-picker">
    <label class="order-source-option ${agencyOrder ? "" : "selected"}"><input type="radio" name="order_source" value="普通客户" ${agencyOrder ? "" : "checked"}><span class="order-source-icon">${appIcon("person.fill")}</span><span><strong>普通客户</strong><small>熟客、散客或临时客人</small></span><span class="order-source-check">${appIcon("checkmark")}</span></label>
    <label class="order-source-option ${agencyOrder ? "selected" : ""}"><input type="radio" name="order_source" value="旅行社订单" ${agencyOrder ? "checked" : ""}><span class="order-source-icon">${appIcon("building.2.fill")}</span><span><strong>旅行社订单</strong><small>旅行社、地接或平台派单</small></span><span class="order-source-check">${appIcon("checkmark")}</span></label>
  </div><div class="agency-info-fields ${agencyOrder ? "" : "hidden"}"><div class="agency-selected-summary"><div><small>旅行社代码</small><strong data-agency-code-label>${escapeHTML(code || "尚未选择")}</strong></div><div><small>旅行社名称</small><strong data-agency-name-label>${escapeHTML(name || "点击选择旅行社")}</strong></div><button type="button" class="button small" data-action="pick-agency">选择</button></div>${formField("旅行社订单号", "travel_agency_order_number", orderNumber)}<input type="hidden" name="travel_agency_code" value="${escapeHTML(code)}"><input type="hidden" name="travel_agency_name" value="${escapeHTML(name)}"></div>
  </fieldset>`;
}

function customerCategoryPicker(value = 1, code = "", name = "") {
  const agencyCustomer = Number(value) === 2;
  return `<fieldset class="field span-2 customer-category-field"><legend>客户类型</legend><div class="customer-category-picker"><label class="customer-category-option ${agencyCustomer ? "" : "selected"}"><input type="radio" name="category" value="1" ${agencyCustomer ? "" : "checked"}><span>普通客户</span></label><label class="customer-category-option ${agencyCustomer ? "selected" : ""}"><input type="radio" name="category" value="2" ${agencyCustomer ? "checked" : ""}><span>旅行社</span></label></div><div class="customer-agency-fields ${agencyCustomer ? "" : "hidden"}"><div class="agency-selected-summary"><div><small>旅行社代码</small><strong data-agency-code-label>${escapeHTML(code || "尚未选择")}</strong></div><div><small>旅行社名称</small><strong data-agency-name-label>${escapeHTML(name || "点击选择旅行社")}</strong></div><button type="button" class="button small" data-action="pick-agency" data-form="customerForm">选择</button></div><input type="hidden" name="travel_agency_code" value="${escapeHTML(code)}"><input type="hidden" name="travel_agency_name" value="${escapeHTML(name)}"></div></fieldset>`;
}

function addressFormField(label, name, value = "", target = name, span = true) {
  const id = `field-${name}`;
  return `<div class="field ${span ? "span-2" : ""}"><label for="${id}">${label}</label><div class="address-input-row"><input id="${id}" name="${name}" list="tripAddressSuggestions" value="${escapeHTML(value)}" placeholder="输入地址或从客户常用地址中选择"><button type="button" class="button address-pick-button" data-action="pick-address" data-target="${target}" aria-label="选择客户常用地址">${appIcon("book.closed")}<span>地址</span></button><button type="button" class="button location-button" data-action="current-location" data-target="${target}" title="获取当前位置">${appIcon("location.north.fill")}</button><button type="button" class="button location-button" data-action="navigate-address" data-target="${target}" title="使用默认导航">${appIcon("arrow.triangle.turn.up.right.diamond.fill")}</button></div></div>`;
}

function stopField(value = "", index = 0) {
  return `<div class="field span-2 stop-field"><label for="field-stop-address-${index}">停靠点 ${index + 1}</label><button type="button" class="button small danger stop-remove-button" data-action="remove-stop" aria-label="删除停靠点">${appIcon("minus.circle.fill")}</button><div class="address-input-row"><input id="field-stop-address-${index}" name="stop_address" list="tripAddressSuggestions" data-stop-input data-stop-index="${index}" value="${escapeHTML(value)}" placeholder="请输入停靠点"><button type="button" class="button address-pick-button" data-action="pick-address" data-target="stop:${index}" aria-label="选择客户常用地址">${appIcon("book.closed")}<span>地址</span></button><button type="button" class="button location-button" data-action="current-location" data-target="stop:${index}" title="获取当前位置">${appIcon("location.north.fill")}</button><button type="button" class="button location-button" data-action="navigate-address" data-target="stop:${index}" title="使用默认导航">${appIcon("arrow.triangle.turn.up.right.diamond.fill")}</button></div></div>`;
}

function flightTimeInput(value) {
  if (!value) return "";
  const match = String(value).match(/(?:^|T|\s)(\d{1,2}:\d{2})/);
  return match ? match[1].padStart(5, "0") : "";
}

function reminderDefaults(date, time) {
  const pickup = new Date(`${date}T${time || "09:00"}:00`);
  const first = new Date(pickup);
  first.setDate(first.getDate() - 1);
  const second = new Date(pickup.getTime() - 2 * 60 * 60 * 1000);
  const localDate = value => new Date(value.getTime() - value.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
  const localTime = value => `${String(value.getHours()).padStart(2, "0")}:${String(value.getMinutes()).padStart(2, "0")}`;
  return { firstDate: localDate(first), firstTime: localTime(first), secondDate: localDate(second), secondTime: localTime(second) };
}

function reminderFields(trip, date, time, copying = false) {
  const defaults = reminderDefaults(date, time);
  const pickup = new Date(`${date}T${time || "09:00"}:00`);
  const copyReminder = new Date(pickup.getTime() - 2 * 60 * 60 * 1000);
  const localDate = value => new Date(value.getTime() - value.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
  const localTime = value => `${String(value.getHours()).padStart(2, "0")}:${String(value.getMinutes()).padStart(2, "0")}`;
  const firstDate = copying ? localDate(copyReminder) : trip?.reminder_at ? dateInput(trip.reminder_at) : defaults.firstDate;
  const firstTime = copying ? localTime(copyReminder) : trip?.reminder_at ? timeInput(trip.reminder_at) : defaults.firstTime;
  const secondDate = !copying && trip?.second_reminder_at ? dateInput(trip.second_reminder_at) : defaults.secondDate;
  const secondTime = !copying && trip?.second_reminder_at ? timeInput(trip.second_reminder_at) : defaults.secondTime;
  const enabled = copying || Boolean(trip?.reminder_enabled);
  const secondEnabled = !copying && Boolean(trip?.has_second_reminder);
  return `<section class="form-section reminder-section"><div class="form-section-title"><div><h3>提醒</h3><p>开启后，在设定时间发送浏览器通知。</p></div></div>
    <label class="toggle-line"><input type="checkbox" name="reminder_enabled" ${enabled ? "checked" : ""}><span>自定义提醒</span></label>
    <div class="reminder-fields ${enabled ? "" : "hidden"}">
      <div class="field"><label>提醒时间</label><div class="compact-inputs"><input type="date" name="reminder_date" value="${firstDate}"><input type="time" name="reminder_time" value="${firstTime}"></div><small>${copying ? "复制行程默认：接载时间提前 2 小时" : "默认：接载日期前一天的同一时间"}</small></div>
      <label class="toggle-line second-reminder-toggle"><input type="checkbox" name="has_second_reminder" ${secondEnabled ? "checked" : ""}><span>增加第二次提醒</span></label>
      <div class="field second-reminder-fields ${secondEnabled ? "" : "hidden"}"><label>第二次提醒时间</label><div class="compact-inputs"><input type="date" name="second_reminder_date" value="${secondDate}"><input type="time" name="second_reminder_time" value="${secondTime}"></div><small>默认：接载时间提前 2 小时</small></div>
    </div></section>`;
}

function pickerOverlay(title, rows) {
  document.getElementById("picker-backdrop")?.remove();
  document.body.insertAdjacentHTML("beforeend", `<div id="picker-backdrop" class="modal-backdrop picker-backdrop"><section class="modal picker-modal"><header class="modal-head"><h2>${escapeHTML(title)}</h2><button class="button quiet small" data-action="close-picker" aria-label="关闭">${appIcon("xmark")}</button></header><div class="picker-list">${rows || `<p class="empty-hint">没有可选择的项目。</p>`}</div></section></div>`);
}

function openAddressPicker(form, target) {
  const customerID = form.elements.customer_id.value;
  const rows = addressRows(customerID).slice().sort((a, b) => Number(b.is_default) - Number(a.is_default));
  pickerOverlay("选择客户常用地址", rows.map(address => `<button type="button" class="picker-row address-picker-row" data-action="select-address" data-target="${escapeHTML(target)}" data-address="${escapeHTML(address.address || "")}"><span class="picker-row-icon">${appIcon("book.closed")}</span><span class="address-picker-copy"><strong class="picker-address-main">${escapeHTML(address.address || "未填写地址")}</strong><span class="picker-address-meta"><span>${escapeHTML(address.label || "常用地址")}</span>${address.is_default ? '<span class="pill accent">默认</span>' : ""}</span></span></button>`).join(""));
}

function openAgencyPicker(formID = "tripForm") {
  pickerOverlay("选择旅行社", state.agencies.map(agency => `<button type="button" class="picker-row" data-action="select-agency" data-form="${formID}" data-code="${escapeHTML(agency.agency_code)}" data-name="${escapeHTML(agency.name)}"><span class="picker-row-icon">${appIcon("building.2.fill")}</span><span><strong>${escapeHTML(agency.name)}</strong><small>${escapeHTML(agency.agency_code)}${agency.contact_person ? ` · ${escapeHTML(agency.contact_person)}` : ""}</small></span></button>`).join(""));
}

function tripCustomerField(customerID = "", customerName = "") {
  const customer = customerByID(customerID);
  const name = customerName || customer?.name || "";
  return `<div class="field span-2"><label for="field-customer_name">客户名称 · 必填</label><div class="app-trip-customer-input"><input id="field-customer_name" name="customer_name" value="${escapeHTML(name)}" placeholder="请输入客户姓名" required><button type="button" class="button" data-action="pick-trip-customer" aria-label="选择客户">${appIcon("book.closed")}<span data-trip-customer-label class="visually-hidden">${escapeHTML(name || "选择或搜索客户")}</span></button><button type="button" class="button quiet" data-action="clear-trip-customer" aria-label="清除客户">${appIcon("xmark")}</button></div><input type="hidden" name="customer_id" value="${escapeHTML(customerID)}"></div>`;
}

function openTripCustomerPicker() {
  const rows = state.customers.map(customer => {
    const contact = contactRows(customer.id).find(item => item.is_default) || contactRows(customer.id)[0];
    return `<button type="button" class="picker-row" data-customer-option data-action="select-trip-customer" data-customer-id="${escapeHTML(customer.id)}" data-customer-name="${escapeHTML(customer.name)}" data-customer-contact="${escapeHTML(contact?.value || "")}"><span class="picker-row-icon">${escapeHTML((customer.name || "?").slice(0, 1))}</span><span><strong>${escapeHTML(customer.name)}</strong><small>${escapeHTML(contact?.value || (Number(customer.category) === 2 ? customer.travel_agency_name || "旅行社客户" : "暂无联系方式"))}</small></span></button>`;
  }).join("");
  pickerOverlay("选择客户", `<div class="picker-search"><input type="search" data-customer-picker-search placeholder="搜索客户姓名或联系方式"></div><button type="button" class="picker-row" data-customer-option data-action="select-trip-customer" data-customer-id="" data-customer-name="" data-customer-contact=""><span class="picker-row-icon">×</span><span><strong>不关联客户</strong><small>手动填写客户名称</small></span></button>${rows}`);
}

function renumberStopFields(form) {
  form.querySelectorAll("[data-stop-input]").forEach((input, index) => {
    input.dataset.stopIndex = index;
    input.id = `field-stop-address-${index}`;
    input.closest(".stop-field")?.querySelector("label")?.setAttribute("for", input.id);
    const label = input.closest(".stop-field")?.querySelector("label");
    if (label) label.textContent = `停靠点 ${index + 1}`;
    input.parentElement.querySelectorAll("[data-target]").forEach(button => { button.dataset.target = `stop:${index}`; });
  });
}

function flightContext(form) {
  return JSON.stringify(['flight_info','flight_date','service_type','location_start','location_end'].map(k => form.elements[k].value));
}
async function queryFlights(number, date) {
  const ownerID = state.user?.id;
  const generation=workspaceGeneration;
  const session = await currentSession();
  if (!ownerID || (state.user?.id !== ownerID || workspaceGeneration !== generation) || session?.user?.id !== ownerID) throw Error('登录状态已变化，请重试。');
  if (!state.entitlementResolved || !['cloud','sync'].includes(state.productEdition)) throw Error('此账号没有有效的航班查询权限。');
  const response = await networkFetch(`${SUPABASE_URL}/functions/v1/variflight-lookup`, { method:'POST', headers:{ apikey:SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`,'Content-Type':'application/json' },body:JSON.stringify({flightNumber:number,flightDate:date}) });
  if ((state.user?.id !== ownerID || workspaceGeneration !== generation)) throw Error('账号已切换，已忽略航班结果。');
  const raw = await response.text();
  if (!response.ok) throw Error(`航班查询失败（${response.status}），请重试。`);
  let payload; try {payload=JSON.parse(raw);} catch {payload=raw.split(/\n\s*\n/).map(block=>block.split('\n').filter(line=>line.startsWith('data:')).map(line=>line.slice(5).trim()).join('\n')).filter(Boolean);}
  const candidates = parseFlights(payload);
  if(!candidates.length) throw Error('未查到可用航段，原航班信息已保留。');
  await airportCrosswalkReady;
  if(state.user?.id!==ownerID || workspaceGeneration!==generation)throw Error('账号会话已变化，已忽略旧航班结果。');
  return candidates;
}
function flightCandidateRows(candidates) {
  return candidates.map((flight, index) => `<button type="button" class="picker-row app-flight-choice" data-action="select-flight-candidate" data-index="${index}"><span class="app-flight-choice-copy"><span class="app-flight-choice-route"><strong>${escapeHTML(flight.departureAirport || "—")} → ${escapeHTML(flight.arrivalAirport || "—")}</strong>${appIcon("chevron.right")}</span>${flight.airlineName ? `<small>${escapeHTML(flight.airlineName)}</small>` : ""}<span class="app-flight-choice-times">${flight.departureTime ? `<small>${appIcon("airplane.departure")} ${escapeHTML(timeDisplay(flight.departureTime))}</small>` : ""}${flight.estimatedArrivalTime ? `<small>${appIcon("airplane.arrival")} ${escapeHTML(timeDisplay(flight.estimatedArrivalTime))}</small>` : ""}</span></span></button>`).join("");
}

function chooseFlight(candidates, select) {
  state.flightPicker = { candidates, select, ownerID: state.user?.id };
  pickerOverlay("选择航段", flightCandidateRows(candidates));
  const picker = document.querySelector("#picker-backdrop .picker-modal");
  picker?.classList.add("app-flight-picker");
  const close = picker?.querySelector('[data-action="close-picker"]');
  if (close) { close.textContent = "取消"; close.setAttribute("aria-label", "取消航段选择"); }
}

async function lookupFlight(form) {
  const number=form.elements.flight_info.value.trim().toUpperCase().replace(/[^A-Z0-9]/g,''),date=form.elements.flight_date.value;
  if(!number||!date)throw Error('请填写航班号和日期。');
  const context=flightContext(form),ownerID=state.user?.id,button=form.querySelector('[data-action="lookup-flight"]');
  button.disabled=true;button.textContent='正在查询航班';
  const feedback=form.querySelector('[data-flight-feedback]');
  if(feedback){feedback.textContent='正在查询航班信息…';feedback.classList.remove('hidden');}
  try {
    const candidates=await queryFlights(number,date);
    if(!form.isConnected || flightContext(form)!==context || ownerID!==state.user?.id)return;
    if(feedback) feedback.classList.add('hidden');
    chooseFlight(candidates, candidate=>{
      if(!form.isConnected || flightContext(form)!==context || ownerID!==state.user?.id)throw Error('行程已变化，请重新查询航班。');
      const trip={service_type:form.elements.service_type.value,location_start:form.elements.location_start.value,location_end:form.elements.location_end.value};
      if(!routeMatches(candidate,trip,airportCrosswalk))throw Error('此航段与行程机场不符，请选择正确航段。');
      form.elements.flight_selection_snapshot.value=JSON.stringify(makeFlightSnapshot(number,date,candidate));
      form.elements.flight_departure_time.value=flightTimeInput(candidate.departureTime);
      form.elements.flight_estimated_arrival_time.value=flightTimeInput(candidate.estimatedArrivalTime);
      form.elements.flight_arrival_terminal.value=candidate.arrivalTerminal||'';
      form.elements.flight_baggage_carousel.value=candidate.baggageCarousel||'';
      const result=form.querySelector('[data-flight-result]');result.classList.remove('hidden');result.innerHTML=flightResultHTML(number,candidate);
    });
  } catch(error) {
    if(feedback && form.isConnected && flightContext(form)===context && ownerID===state.user?.id){feedback.textContent=error.message || '航班查询失败，请重试。';feedback.classList.remove('hidden');}
    throw error;
  } finally {button.disabled=!form.elements.flight_info.value.trim();button.textContent='查询航班信息';button.insertAdjacentHTML?.('afterbegin', appIcon('magnifyingglass') + ' ');}
}
async function refreshFlightCard(trip) {
  if(!trip) return;
  const ownerID=state.user?.id, context=JSON.stringify([trip.flight_info,trip.flight_date,trip.service_type,trip.location_start,trip.location_end]);
  const candidates=await queryFlights(trip.flight_info,dateInput(trip.flight_date));
  chooseFlight(candidates,async candidate=>{
    if(state.user?.id!==ownerID)throw Error('账号已变化。');
    const latest=state.trips.find(t=>t.id===trip.id);
    if(!latest || context!==JSON.stringify([latest.flight_info,latest.flight_date,latest.service_type,latest.location_start,latest.location_end]))throw Error('行程已变化，请刷新后重试。');
    if(!routeMatches(candidate,latest,airportCrosswalk))throw Error('此航段与行程机场不符。');
    const filters=Object.fromEntries(['id','flight_info','flight_date','service_type','location_start','location_end'].map(k=>[k,`eq.${trip[k]}`]));
    filters.deleted_at='is.null';
    const saved=await request('trips',{method:'PATCH',query:filters,body:{flight_selection_snapshot:makeFlightSnapshot(trip.flight_info,dateInput(trip.flight_date),candidate),flight_departure_time:flightTimeInput(candidate.departureTime)||null,flight_estimated_arrival_time:flightTimeInput(candidate.estimatedArrivalTime)||null,flight_arrival_terminal:candidate.arrivalTerminal||'',flight_baggage_carousel:candidate.baggageCarousel||'',updated_at:new Date().toISOString()},prefer:'return=representation',queueOffline:false});
    if(!saved?.length)throw Error('云端行程已变化，未覆盖新资料，请重新同步。');
    if(state.user?.id!==ownerID)return;
    await loadData();renderApp();showToast('航班快照已更新。');
  });
}
function previewPickup(form) {
  const order=recognizePickup(form.elements.smart_order_text.value);
  const agency=matchPickupAgency(state.agencies);
  state.pickupPreview={order,agency,form,ownerID:state.user?.id};
  pickerOverlay('核对识别结果',`<div class="form-section"><p>旅行社订单号：${escapeHTML(order.number)}</p><p>接客：${escapeHTML(order.date)} ${order.time}（洛杉矶时间）${order.inferredYear?' · 已推断年份':''}</p><p>航班：${order.flight} · ${order.airport}</p><p>联系人：${escapeHTML(order.contact)} · ${escapeHTML(order.phone)}</p><p>${escapeHTML(order.passengers)} 人 · ${escapeHTML(order.luggage)} 件行李</p><p>${escapeHTML(order.destination)}</p><p>旅行社：${escapeHTML(agency?.name||'途风（请手动选择合作旅行社）')} · ${escapeHTML(agency?.agency_code||'尚未匹配')}</p><p>${order.reminders.length===2?'将开启两条未来提醒':'接客时间太近或已过，请手动设置提醒'}</p><button type="button" class="button primary" data-action="apply-pickup">填入行程</button></div>`);
}
function applyPickup() {
  const preview=state.pickupPreview;
  if(!preview||preview.ownerID!==state.user?.id||!preview.form.isConnected)throw Error('草稿或账号已变化，请重新识别。');
  const {order:o,form,agency}=preview;
  o.reminders=pickupReminders(o.iso);
  const set=(key,value)=>{form.elements[key].value=value;};
  form.elements.order_source.value='旅行社订单';form.elements.order_source[1].dispatchEvent(new Event('change',{bubbles:true}));
  form.elements.service_type.value='接机';form.querySelector('input[name="service_type"][value="接机"]').dispatchEvent(new Event('change',{bubbles:true}));
  for(const [key,value] of Object.entries({travel_agency_order_number:o.number,travel_agency_name:agency?.name||'途风',travel_agency_code:agency?.agency_code||'',appointment_date:o.date,appointment_time:o.time,flight_date:o.date,flight_info:o.flight,location_start:o.airport,location_end:o.destination,customer_name:o.contact,customer_contact:o.phone,customer_id:'',flight_selection_snapshot:'null',flight_departure_time:'',flight_estimated_arrival_time:o.time,flight_arrival_terminal:'',flight_baggage_carousel:''}))set(key,value);
  if(o.passengers)set('customer_count',o.passengers);if(o.luggage)set('customer_stuff',o.luggage);
  form.querySelector('[data-trip-customer-label]').textContent='选择或搜索客户';
  form.querySelector('[data-agency-code-label]').textContent=agency?.agency_code||'尚未选择';form.querySelector('[data-agency-name-label]').textContent=agency?.name||'途风（请选择）';
  form.dataset.timeZone='America/Los_Angeles';
  form.elements.reminder_enabled.checked=o.reminders.length===2;form.elements.has_second_reminder.checked=o.reminders.length===2;
  form.querySelector('.reminder-fields').classList.toggle('hidden',o.reminders.length!==2);form.querySelector('.second-reminder-fields').classList.toggle('hidden',o.reminders.length!==2);
  o.reminders.forEach((iso,i)=>{const p=partsInZone(iso),prefix=i?'second_reminder':'reminder';set(`${prefix}_date`,`${p.year}-${p.month}-${p.day}`);set(`${prefix}_time`,`${p.hour}:${p.minute}`);});
  const note=`途风订单号：${o.number}\n航班预计抵达：${o.time}（洛杉矶当地时间；已用作接客时间）\n原始订单：\n${o.rawText}`;
  if(!form.elements.memo.value.includes(note))form.elements.memo.value+=(form.elements.memo.value?'\n\n':'')+note;
  form.querySelector('[data-smart-feedback]').textContent='已填入草稿，接客时间和提醒按洛杉矶时间保存。请核对后保存行程。';
  invalidateFormFlight(form);
  state.pickupPreview=null;document.getElementById('picker-backdrop')?.remove();
}

function tripReminderMessage(trip, reminderDate) {
  const clean = value => String(value || "").trim().replace(/\s+/g, " ");
  const flight = readFlightSnapshot(trip, airportCrosswalk);
  const airport = (name, terminal) => {
    if (!clean(name)) return "";
    const value = clean(terminal);
    return clean(name) + (value ? " " + (/^\d+$/.test(value) ? "T" + value : value) : "");
  };
  const airports = [airport(flight?.departureAirport, flight?.departureTerminal), airport(flight?.arrivalAirport, flight?.arrivalTerminal)];
  const title = [trip.service_type ? `[${clean(trip.service_type)}]` : "行程提醒", clean(trip.flight_info).toUpperCase(), airports.every(Boolean) ? airports.join(" → ") : ""].filter(Boolean).join(" ");
  const day = trip.appointment_date && !Number.isNaN(new Date(trip.appointment_date).getTime()) ? dateInput(trip.appointment_date) : "";
  const time = timeOnly(trip.appointment_time);
  const pickup = new Date(`${day}T${time}`);
  const minutes = Math.ceil((pickup.getTime() - new Date(reminderDate).getTime()) / 60000);
  const remaining = minutes > 0 ? `距接客约 ${minutes % 60 === 0 ? minutes / 60 + " 小时" : minutes + " 分钟"}` : "";
  const route = [clean(trip.location_start), clean(trip.location_end)].filter(Boolean).join(" → ");
  return { title, body: [day && time !== "—" ? `${day.slice(5).replace("-", "/")} ${time}` : "", clean(trip.customer_name), route, remaining].filter(Boolean).join(" · ") };
}

function scheduleWebReminders() {
  for (const timer of webReminderTimers.values()) clearTimeout(timer);
  webReminderTimers.clear();
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  for (const trip of state.trips) {
    if (!trip.reminder_enabled || trip.is_cancelled || trip.is_completed) continue;
    for (const [kind, value] of [["first", trip.reminder_at], ["second", trip.has_second_reminder ? trip.second_reminder_at : null]]) {
      const dueAt = new Date(value).getTime();
      if (!value || dueAt <= Date.now()) continue;
      const key = `${trip.id}:${kind}`;
      const arm = () => {
        const remaining = dueAt - Date.now();
        webReminderTimers.set(key, setTimeout(() => {
          if (remaining > 2_147_000_000) { arm(); return; }
          const current = state.trips.find(item => item.id === trip.id);
          if (!current || current.is_cancelled || current.is_completed) return;
          const message = tripReminderMessage(current, dueAt);
          new Notification(message.title, { body: message.body, tag: key });
        }, Math.min(remaining, 2_147_000_000)));
      };
      arm();
    }
  }
}

function openSettlement(trip) {
  state.settlementDraft = {
    tripID: trip.id, price: Number(trip.price || 0), tip: Number(trip.tip || 0),
    expenses: (trip.expenses || []).map(item => ({ id: item.id, is_addition: Boolean(item.is_addition), title: item.title || "", amount: Number(item.amount || 0) })),
  };
  renderSettlementModal(trip);
}

function renderSettlementModal(trip) {
  const draft = state.settlementDraft;
  const expenseFields = draft.expenses.map((item, index) => `<div class="settlement-expense" data-expense-row>
    <select name="expense_addition_${index}" aria-label="费用增减"><option value="false" ${item.is_addition ? "" : "selected"}>− 扣减</option><option value="true" ${item.is_addition ? "selected" : ""}>＋ 增加</option></select>
    <select name="expense_title_${index}" aria-label="费用项目"><option value="">选择费用项目</option>${[...new Set([...expenseCatalog(), item.title].filter(Boolean))].map(name => `<option value="${escapeHTML(name)}" ${item.title === name ? "selected" : ""}>${escapeHTML(name)}</option>`).join("")}</select>
    <input name="expense_amount_${index}" type="number" min="0" step="0.01" value="${escapeHTML(item.amount)}" placeholder="金额" aria-label="费用金额">
    <button type="button" class="button small danger" data-action="remove-expense" data-index="${index}" aria-label="删除费用">−</button>
  </div>`).join("");
  const total = draft.price + draft.tip + draft.expenses.reduce((sum, item) => sum + (item.is_addition ? 1 : -1) * Number(item.amount || 0), 0);
  const route = [trip.location_start, ...(trip.stops || []).map(item => item.address), trip.location_end].filter(Boolean).join(" → ") || "—";
  showModal("财务结算", `<form id="settlementForm" class="editor-form settlement-form" data-id="${trip.id}">
    <div class="editor-columns settlement-columns"><div class="editor-column">
    <div class="settlement-trip-summary"><span class="form-emblem">＄</span><div><strong>${escapeHTML(trip.customer_name || "未填写客户")}</strong><p>${escapeHTML(trip.service_type || "行程")} · ${dateOnly(trip.appointment_date)} ${timeOnly(trip.appointment_time)}</p><small>${escapeHTML(route)}</small></div></div>
    ${formSection("财务信息", "净收入按行程费用 + 小费 ± 费用明细自动汇总", `<div class="field"><label for="settlement-price">行程费用</label><input id="settlement-price" name="price" type="number" min="0" step="0.01" value="${escapeHTML(draft.price)}" required></div><div class="field"><label for="settlement-tip">小费</label><input id="settlement-tip" name="tip" type="number" min="0" step="0.01" value="${escapeHTML(draft.tip)}" required></div>`)}
    </div><div class="editor-column">
    <section class="form-section"><div class="form-section-title"><div><h3>费用明细</h3><p>例如居间费、高速通行费或其他调整</p></div><button type="button" class="button small" data-action="add-expense">${appIcon("plus")} 添加费用</button></div><div class="settlement-expense-list">${expenseFields || `<p class="settlement-empty">暂无费用明细，可按需添加。</p>`}</div></section>
    </div></div><div class="settlement-net"><span>净收入</span><strong id="settlement-net-value">${currency(total)}</strong></div>
    <div class="form-actions"><button type="button" class="button" data-action="close-modal">取消</button><button type="submit" class="button" data-settlement-mode="save">${escapeHTML(ui("仅保存"))}</button><button type="submit" class="button primary" data-settlement-mode="settle">${escapeHTML(ui("结算"))}</button></div></form>`, "editor-modal settlement-modal workspace-editor");
}

function captureSettlementDraft(form) {
  const data = new FormData(form);
  const rows = [...form.querySelectorAll("[data-expense-row]")];
  state.settlementDraft.price = Number(data.get("price") || 0);
  state.settlementDraft.tip = Number(data.get("tip") || 0);
  state.settlementDraft.expenses = rows.map((_, index) => ({
    id: state.settlementDraft.expenses[index]?.id || crypto.randomUUID(),
    is_addition: data.get(`expense_addition_${index}`) === "true",
    title: String(data.get(`expense_title_${index}`) || ""),
    amount: Number(data.get(`expense_amount_${index}`) || 0),
  }));
}

async function submitSettlement(form, markPaid = true) {
  captureSettlementDraft(form);
  const draft = state.settlementDraft;
  if (draft.price < 0 || draft.tip < 0 || draft.expenses.some(item => !item.title.trim() || item.amount <= 0)) {
    throw new Error("行程费用和小费不能小于 0；每条费用明细需填写名称和大于 0 的金额。");
  }
  const trip = state.trips.find(item => item.id === draft.tripID);
  if (!trip) throw new Error("找不到对应的行程记录。");
  const ownerID = state.user?.id;
  await request(markPaid ? 'rpc/settle_online_trip' : 'rpc/save_online_trip_finances', { method: 'POST', body: settlementPayload(draft), prefer: 'return=minimal', queueOffline: state.productEdition !== 'cloud' });
  if (state.user?.id !== ownerID) return;
  state.settlementDraft = null;
  document.getElementById("modal-root")?.remove();
  await loadData(); renderApp(); showToast(markPaid ? "财务结算已保存并同步。" : "费用信息已保存，收款状态保持不变。");
}

function openCustomerForm(customer = null) {
  const language = [["zh-Hans", "简体中文"], ["zh-Hant", "繁體中文"], ["en", "English"], ["es", "Español"], ["ja", "日本語"], ["ko", "한국어"]];
  showModal(customer ? "编辑客户" : "新增客户", `<form id="customerForm" class="editor-form customer-form" data-id="${customer?.id || ""}">
    <div class="editor-columns"><div class="editor-column">
    ${formSection("基本资料", "客户身份与沟通偏好", `${formField("客户名称 · 必填", "name", customer?.name || "", "text", { required: true, placeholder: "输入客户姓名" })}${customerCategoryPicker(customer?.category || 1, customer?.travel_agency_code || "", customer?.travel_agency_name || "")}${formField("语言喜好", "language_preference", customer?.language_preference || "zh-Hans", "text", { select: language })}${formField("称呼 / 来源", "source", customer?.source || "", "text", { placeholder: "选填" })}${formField("邮箱", "email", customer?.email || "", "email", { placeholder: "name@example.com" })}`)}
    </div><div class="editor-column">
    ${formSection("联系方式", "可添加多条，并指定一个默认联系方式", `<div class="field span-2"><div class="dynamic-row-heading"><strong>联系方式</strong><button type="button" class="button small" data-action="add-customer-contact">${appIcon("plus")} 添加联系方式</button></div><div class="customer-contact-rows">${(customer ? contactRows(customer.id) : [{ contact_type: "电话", value: "", is_default: true }]).map((item, index) => customerContactField(item, index)).join("")}</div></div>`)}
    </div><div class="editor-column">
    ${formSection("常用地址", "可保存多个接送地址，并指定一个默认地址", `<div class="field span-2"><div class="dynamic-row-heading"><strong>常用地址</strong><button type="button" class="button small" data-action="add-customer-address">${appIcon("plus")} 添加地址</button></div><div class="customer-address-rows">${(customer ? addressRows(customer.id) : [{ label: "家", address: "", is_default: true }]).map((item, index) => customerAddressField(item, index)).join("")}</div></div>`)}
    ${formSection("备注", "记录与服务相关的补充信息", formField("备注", "remark", customer?.remark || "", "textarea", { span: true, placeholder: "添加备注…" }))}
    </div></div></form>`, "editor-modal customer-editor-modal workspace-editor");
}

function customerContactField(item = {}, index = 0) {
  const types = [["电话", "电话"], ["微信", "微信"], ["邮箱", "邮箱"], ["WhatsApp", "WhatsApp"], ["Line", "Line"]];
  return `<div class="dynamic-record contact-record" data-contact-row data-id="${item.id || ""}"><select name="contact_type" aria-label="联系方式类型">${types.map(([value, label]) => `<option value="${value}" ${value === (item.contact_type || item.label || "电话") ? "selected" : ""}>${label}</option>`).join("")}</select><input name="contact_value" value="${escapeHTML(item.value || "")}" placeholder="电话号码或账号"><label class="default-choice"><input type="radio" name="contact_default" value="${index}" ${item.is_default || index === 0 ? "checked" : ""}>默认</label><button type="button" class="button small danger" data-action="remove-customer-row" aria-label="删除联系方式">−</button></div>`;
}

function customerAddressField(item = {}, index = 0) {
  const labels = [["家", "家"], ["公司", "公司"], ["其他", "其他"]];
  return `<div class="dynamic-record address-record" data-address-row data-id="${item.id || ""}"><select name="address_label" aria-label="地址类型">${labels.map(([value, label]) => `<option value="${value}" ${value === (item.label || "家") ? "selected" : ""}>${label}</option>`).join("")}</select><input name="address_value" value="${escapeHTML(item.address || "")}" placeholder="输入门牌号、街道、城市或机场"><label class="default-choice"><input type="radio" name="address_default" value="${index}" ${item.is_default || index === 0 ? "checked" : ""}>默认</label><button type="button" class="button small danger" data-action="remove-customer-row" aria-label="删除地址">−</button></div>`;
}

function openAgencyForm(agency = null) {
  showModal(agency ? "编辑旅行社" : "新增旅行社", `<form id="agencyForm" class="agency-editor-form" data-id="${agency?.id || ""}"><div class="form-grid">
    ${formField("旅行社代码 · 必填", "agency_code", agency?.agency_code || "", "text", { required: true })}
    ${formField("旅行社名称 · 必填", "name", agency?.name || "", "text", { required: true })}
    ${formField("联系人", "contact_person", agency?.contact_person || "")}
    ${formField("联系电话", "phone", agency?.phone || "", "tel")}
    ${formField("办公地址", "office_address", agency?.office_address || "", "text", { span: true })}
  </div>${modalActions()}</form>`, "editor-modal agency-editor-modal");
}

function tripRouteFields(trip) {
  const stops = (trip?.stops || []).map(stop => stop.address).filter(Boolean);
  return `<div class="field span-2"><div class="route-fields app-trip-route">
    <div class="route-start-wrap">${addressFormField("起始点", "location_start", trip?.location_start || "", "start", false)}<button type="button" class="button route-swap" data-action="swap-route" title="互换起始点和目的地">${appIcon("arrow.up.arrow.down")}<span>互换</span></button></div>
    <div class="stops-list">${stops.map((stop,index) => stopField(stop,index)).join("")}</div>
    <button type="button" class="button small app-add-stop" data-action="add-stop">${appIcon("plus.circle")} 增加停靠点</button>
    ${addressFormField("目的地", "location_end", trip?.location_end || "", "end", false)}
  </div></div>`;
}

function tripPaidSelector(isPaid) {
  return `<fieldset class="field trip-paid-field"><legend>结算状态</legend><div class="trip-paid-picker"><label><input type="radio" name="is_paid" value="false" ${isPaid ? "" : "checked"}><span>未收款</span></label><label><input type="radio" name="is_paid" value="true" ${isPaid ? "checked" : ""}><span>已结清</span></label></div></fieldset>`;
}

function tripFlightSection(trip, copying, pickupDate) {
  const number = trip?.flight_info || "";
  const date = trip?.flight_date && !copying ? dateInput(trip.flight_date) : pickupDate;
  const preserved = {
    flight_departure_time: flightTimeInput(trip?.flight_departure_time),
    flight_estimated_arrival_time: flightTimeInput(trip?.flight_estimated_arrival_time),
    flight_arrival_terminal: trip?.flight_arrival_terminal || "",
    flight_baggage_carousel: trip?.flight_baggage_carousel || ""
  };
  return `<section class="app-trip-flight-section" aria-label="航班信息">
    <div class="app-trip-flight-inputs">${formField(`${appIcon("airplane")} 航班信息`, "flight_info", number, "text", {placeholder:"请输入航班号"})}${formField(`${appIcon("calendar")} 航班日期`, "flight_date", date, "date")}</div>
    <button type="button" class="app-trip-flight-query" data-action="lookup-flight" ${number.trim() ? "" : "disabled"}>${appIcon("magnifyingglass")} 查询航班信息</button>
    <div data-flight-feedback class="app-trip-flight-feedback hidden" role="status" aria-live="polite"></div>
    <div data-flight-result class="flight-lookup-result hidden"></div>
    ${Object.entries(preserved).map(([name, value]) => `<input type="hidden" name="${name}" value="${escapeHTML(value)}">`).join("")}
  </section>`;
}

function openTripForm(trip = null, copying = false) {
  const today = dateInput(new Date());
  const pickupDate = trip && !copying ? dateInput(trip.appointment_date) : today;
  const pickupTime = trip ? timeInput(trip.appointment_time) : "09:00";
  const stops = (trip?.stops || []).map(stop => stop.address).filter(Boolean);
  const statusLabel = !copying && trip?.is_cancelled ? "已取消" : !copying && trip?.is_completed ? "已完成" : "待执行";
  showModal(trip && !copying ? "编辑行程" : copying ? "复制行程" : "新增行程", `<form id="tripForm" class="editor-form trip-form" data-id="${trip && !copying ? trip.id : crypto.randomUUID()}" data-original-updated-at="${escapeHTML(!copying ? trip?.updated_at || '' : '')}">

    <div class="editor-columns">
    <div class="editor-column">
    ${formSection("行程类型", "", serviceTypePicker(trip?.service_type || "接机"), "trip-type-section")}
    <details class="smart-order-disclosure"><summary>智能输入</summary><section class="form-section smart-input-section"><label for="smart-order-text">智能输入</label><textarea id="smart-order-text" name="smart_order_text" rows="4" placeholder="粘贴途风接机订单"></textarea><small>智能识别录入</small><button type="button" class="button" data-action="recognize-pickup">识别订单</button><p data-smart-feedback></p></section></details>
    <input type="hidden" name="flight_selection_snapshot" value="${escapeHTML(JSON.stringify(!copying ? trip?.flight_selection_snapshot || null : null))}">
    <datalist id="tripAddressSuggestions">${addressRows(trip?.customer_id || "").map(address => `<option value="${escapeHTML(address.address)}">${escapeHTML(address.label || "常用地址")}</option>`).join("")}</datalist>
    ${formSection("订单来源", "", orderSourcePicker(trip?.order_source || "普通客户", trip?.travel_agency_code || "", trip?.travel_agency_name || "", copying ? "" : trip?.travel_agency_order_number || ""), "trip-source-section")}
    ${formSection("客户", "", `${tripCustomerField(trip?.customer_id || "", trip?.customer_name || "")}${formField("联系方式", "customer_contact", trip?.customer_contact || "", "text", {span:true,placeholder:"电话或其他联系方式"})}${formField("人数", "customer_count", trip?.customer_count || "1", "number")}${formField("行李", "customer_stuff", trip?.customer_stuff || "0", "number")}`, "trip-customer-section")}
    </div>
    <div class="editor-column">
    ${formSection("行程详情", "", `${formField("接载日期", "appointment_date", pickupDate, "date", {required:true})}${formField("接载时间", "appointment_time", pickupTime, "time", {required:true})}${tripRouteFields(trip)}`, "trip-details-section")}
    ${formSection("航班信息", "", `<div class="span-2">${tripFlightSection(trip, copying, pickupDate)}</div>`, "trip-flight-panel")}
    </div>
    <div class="editor-column">
    ${formSection("费用与备注", "", `${formField("行程费用", "price", trip?.price ?? 0, "number")}${formField("备注", "memo", trip?.memo || "", "textarea", {span:true,placeholder:"接载说明或其他备注…"})}<input type="hidden" name="tip" value="${escapeHTML(copying ? 0 : trip?.tip ?? 0)}">`, "trip-finance-section")}
    ${formSection("状态信息", "", `<div class="field"><label>行程状态</label><div class="readonly-status">${statusLabel}</div></div>${tripPaidSelector(!copying && trip?.is_paid)}`, "trip-state-section")}
    ${reminderFields(trip, pickupDate, pickupTime, copying)}
    </div>
    </div></form>`, "editor-modal trip-editor-modal workspace-editor");
  const savedFlight = !copying && trip ? readFlightSnapshot(trip, airportCrosswalk) : null;
  if (savedFlight) {
    const result = document.querySelector('#tripForm [data-flight-result]');
    result.classList.remove('hidden');
    result.innerHTML = flightResultHTML(trip.flight_info, savedFlight);
  }
}


function showToast(message, error = false) {
  const networkNotice = /无法连接云端|无法验证云端|连接云端失败|网络.*(断开|连接|恢复)|failed to fetch|network error/i.test(String(message));
  if (networkNotice) {
    if (networkToastShownForCurrentOutage) return;
    networkToastShownForCurrentOutage = true;
  }
  if (!error && queuedOperationCount() > 0) {
    message = message.replace("并同步到云端", "，联网后同步").replace("同步到云端", "待联网同步");
    if (!message.includes("待同步") && !message.includes("待联网")) message += "（有修改待联网同步）";
  }
  document.querySelector(".toast")?.remove();
  document.body.insertAdjacentHTML("beforeend", `<div class="toast" style="${error ? "border-color:#723541;background:#3a2029;color:#ffb0b6" : ""}">${escapeHTML(message)}</div>`);
  setTimeout(() => document.querySelector(".toast")?.remove(), 3500);
}

function setBusy(value) {
  state.busy = value;
  if (!state.session) renderLogin();
}

async function doLogin(form) {
  const fields = new FormData(form);
  let attemptedUserID = null;
  state.error = ""; setBusy(true);
  try {
    const data = await authRequest("token?grant_type=password", { email: String(fields.get("email")||"").trim().toLowerCase(), password: fields.get("password") });
    attemptedUserID = data.user.id;
    if (state.user && state.user.id !== data.user.id) resetAccountWorkspace();
    writeSession({ ...data, expires_at: Date.now() + (data.expires_in || 3600) * 1000 });
    state.user = data.user;
    await resolveProductEdition();
    if (state.archiveMode) { await loadExpiredArchive(); return; }
    if (state.productEdition === "cloud" && queuedOperationCount() > 0) {
      await replayOfflineQueue();
      if (queuedOperationCount() > 0) throw new Error("此账号有尚未提交的离线修改；请联网完成同步后再使用云端版。");
    }
    await loadData();
    if (state.user?.id !== attemptedUserID) return;
    state.page = "home";
    renderApp();
    if (navigator.onLine && queuedOperationCount() > 0) void replayOfflineQueue();
  } catch (error) {
    if (attemptedUserID && state.user?.id !== attemptedUserID) return;
    state.error = error.message || "登录失败。";
    if (attemptedUserID && queuedOperationCount() > 0) {
      renderPendingSyncBlocker();
    } else {
      clearSession();
    }
  } finally {
    state.busy = false;
    if (!state.session) renderLogin();
  }
}

async function initialize() {
  if (await consumeAuthLink()) return;
  if (!state.session) { renderLogin(); return; }
  document.getElementById("app").innerHTML = `<div class="loading"><div><div class="spinner"></div>正在连接云端…</div></div>`;
  const session = await currentSession();
  if (!session) { renderLogin(); return; }
  const initializedUserID = session.user.id;
  state.user = session.user;
  try {
    await resolveProductEdition();
    if (state.archiveMode) { await loadExpiredArchive(); return; }
    if (state.user?.id !== initializedUserID) return;
    if (state.productEdition === "cloud" && queuedOperationCount() > 0) {
      await replayOfflineQueue();
      if (state.user?.id !== initializedUserID) return;
      if (queuedOperationCount() > 0) throw new Error("此账号有尚未提交的离线修改；请联网完成同步后再使用云端版。");
    }
    await loadData();
    if (state.user?.id !== initializedUserID) return;
    renderApp();
    if (navigator.onLine) void replayOfflineQueue();
  } catch (error) {
    if (state.user?.id !== initializedUserID) return;
    if (queuedOperationCount() > 0) {
      renderPendingSyncBlocker();
      return;
    }
    if (isNetworkFailure(error) && state.user) {
      state.offline = true;
      document.getElementById("app").innerHTML = `<main class="offline-start"><section class="panel"><h1>暂时无法连接云端</h1><p>此浏览器还没有可用的离线资料缓存。请恢复网络后重试；登录状态和待同步修改会保留。</p><button class="button primary" data-action="retry-offline-load">重试连接</button></section></main>`;
      return;
    }
    clearSession(); state.error = error.message; renderLogin();
  }
}

window.addEventListener("offline", () => {
  state.offline = true;
  renderConnectionStatus();
});

window.addEventListener("online", () => {
  state.offline = false;
  renderConnectionStatus();
  if (state.user) {
    if (queuedOperationCount() > 0) void replayOfflineQueue();
    else void loadData().then(() => renderApp()).catch(() => {});
  }
});

function updatePageContent() {
  const content = document.getElementById("pageContent");
  if (content) content.innerHTML = renderPage();
}

let pendingTripCompletion = null;
const completingTripIDs = new Set();
function requestTripCompletion(id) {
  const trip = state.trips.find(item => item.id === id);
  if (!trip || trip.is_completed || trip.is_cancelled || completingTripIDs.has(id)) return;
  pendingTripCompletion = {id, ownerID: state.user?.id};
  showModal("确认完成行程？", `<p class="completion-prompt-copy">确认后，该行程将标记为已完成。</p><div class="form-actions"><button class="button" data-action="close-modal">取消</button><button class="button primary" data-action="confirm-trip-completion">确认</button></div>`, "completion-prompt-modal");
}
async function confirmTripCompletion(button) {
  const pending = pendingTripCompletion;
  if (!pending || pending.ownerID !== state.user?.id || completingTripIDs.has(pending.id)) return;
  const trip = state.trips.find(item => item.id === pending.id);
  if (!trip || trip.is_completed || trip.is_cancelled) return;
  completingTripIDs.add(pending.id);
  button.disabled = true;
  try {
    await markTrip(pending.id, {is_completed:true, is_cancelled:false});
    if (pending.ownerID !== state.user?.id) return;
    pendingTripCompletion = null;
    showModal("行程已结束", `<p class="completion-prompt-copy">是否财务结算？</p><div class="form-actions"><button class="button" data-action="close-modal">否</button><button class="button primary" data-action="completion-settlement" data-id="${escapeHTML(pending.id)}">是</button></div>`, "completion-prompt-modal");
  } finally {
    completingTripIDs.delete(pending.id);
    button.disabled = false;
  }
}

async function markTrip(id, updates) {
  const ownerID=state.user?.id;
  await patch("trips", { id: `eq.${id}` }, { ...updates, updated_at: new Date().toISOString() });
  if(state.user?.id!==ownerID)return;
  await loadData();
  if(state.user?.id!==ownerID)return;
  document.getElementById('modal-root')?.remove();
  renderApp();
  showToast("行程已更新，并同步到云端。");
}

async function deleteTrip(id) {
  if (!confirm("确定删除这条行程吗？删除后会从各设备同步移除。")) return;
  if (state.productEdition === "cloud") {
    await callOnlineRPC("delete_online_trip", { p_trip_id: id });
    await loadData(); renderApp(); showToast("行程已删除。");
    return;
  }
  const deletedAt = new Date().toISOString();
  await Promise.all([
    patch("trip_stops", { trip_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt }),
    patch("trip_expenses", { trip_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt }),
    patch("trips", { id: `eq.${id}` }, { deleted_at: deletedAt, updated_at: deletedAt }),
  ]);
  await loadData(); renderApp(); showToast("行程已删除。");
}

async function deleteCustomer(id) {
  const customer = customerByID(id);
  if (state.trips.some(trip => trip.customer_id === id || (!trip.customer_id && trip.customer_name === customer?.name))) { showToast("该客户已有行程记录，不能删除。", true); return; }
  if (!confirm("确定删除这位客户吗？")) return;
  if (state.productEdition === "cloud") {
    await callOnlineRPC("delete_online_customer", { p_customer_id: id });
    await loadData(); renderApp(); showToast("客户已删除。");
    return;
  }
  const deletedAt = new Date().toISOString();
  await Promise.all([
    patch("customer_contacts", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt }),
    patch("customer_addresses", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt }),
    patch("customers", { id: `eq.${id}` }, { deleted_at: deletedAt, updated_at: deletedAt }),
  ]);
  await loadData(); renderApp(); showToast("客户已删除。");
}

async function deleteAgency(id) {
  if (!confirm("确定删除这家旅行社吗？")) return;
  const now = new Date().toISOString();
  await patch("travel_agencies", { id: `eq.${id}` }, { deleted_at: now, updated_at: now });
  await loadData(); renderApp(); showToast("旅行社已删除。");
}

async function submitCustomer(form) {
  const data = Object.fromEntries(new FormData(form));
  const id = form.dataset.id || crypto.randomUUID();
  const existing = customerByID(id);
  const now = new Date().toISOString();
  const row = {
    ...(existing || {}), id, owner_id: state.user.id, name: data.name.trim(), email: data.email.trim(),
    source: data.source.trim(), type: existing?.type || 1, category: Number(data.category),
    travel_agency_code: Number(data.category) === 2 ? (data.travel_agency_code || "") : "", travel_agency_name: Number(data.category) === 2 ? (data.travel_agency_name || "") : "",
    language_preference: data.language_preference, remark: data.remark.trim(), avatar_url: existing?.avatar_url || "",
    created_at: existing?.created_at || now, updated_at: now, deleted_at: null,
  };
  if (Number(data.category) === 2 && (!row.travel_agency_code || !row.travel_agency_name)) throw new Error("请选择关联的旅行社。");
  const oldContacts = contactRows(id);
  const oldAddresses = addressRows(id);
  const defaultContact = Number(new FormData(form).get("contact_default"));
  const defaultAddress = Number(new FormData(form).get("address_default"));
  const addresses = [...form.querySelectorAll("[data-address-row]")].flatMap((record, index) => {
    const address = record.querySelector('[name="address_value"]').value.trim();
    if (!address) return [];
    const prior = oldAddresses.find(item => item.id === record.dataset.id);
    return [{
      id: prior?.id || crypto.randomUUID(), label: record.querySelector('[name="address_label"]').value,
      address, is_default: index === defaultAddress,
    }];
  });
  const contacts = [...form.querySelectorAll("[data-contact-row]")].flatMap((record, index) => {
    const value = record.querySelector('[name="contact_value"]').value.trim();
    if (!value) return [];
    const prior = oldContacts.find(item => item.id === record.dataset.id);
    const contactType = record.querySelector('[name="contact_type"]').value;
    return [{
      id: prior?.id || crypto.randomUUID(), label: contactType, contact_type: contactType,
      value, is_default: index === defaultContact,
    }];
  });
  if (state.productEdition === "cloud") {
    await callOnlineRPC("save_online_customer", {
      p_customer: row, p_contacts: contacts, p_addresses: addresses,
    });
  } else {
    await upsert("customers", row);
    await Promise.all([
      patch("customer_contacts", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: now, updated_at: now }),
      patch("customer_addresses", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: now, updated_at: now }),
    ]);
    // Await all saved rows so customer edits are fully synchronized before the view refreshes.
    await Promise.all([
      ...contacts.map(contact => upsert("customer_contacts", {
        ...contact, owner_id: state.user.id, customer_id: id,
        created_at: oldContacts.find(item => item.id === contact.id)?.created_at || now,
        updated_at: now, deleted_at: null,
      })),
      ...addresses.map(address => upsert("customer_addresses", {
        ...address, owner_id: state.user.id, customer_id: id,
        created_at: oldAddresses.find(item => item.id === address.id)?.created_at || now,
        updated_at: now, deleted_at: null,
      })),
    ]);
  }
  await loadData(); renderApp(); showToast(existing ? "客户资料已更新。" : "客户已新增。");
}

async function submitAgency(form) {
  const data = Object.fromEntries(new FormData(form));
  const id = form.dataset.id || crypto.randomUUID();
  const existing = state.agencies.find(agency => agency.id === id);
  const now = new Date().toISOString();
  await upsert("travel_agencies", {
    ...(existing || {}), id, owner_id: state.user.id, agency_code: data.agency_code.trim(), name: data.name.trim(),
    contact_person: data.contact_person.trim(), phone: data.phone.trim(), office_address: data.office_address.trim(),
    created_at: existing?.created_at || now, updated_at: now, deleted_at: null,
  });
  await loadData(); renderApp(); showToast(existing ? "旅行社资料已更新。" : "旅行社已新增。");
}

async function submitTrip(form) {
  const data = Object.fromEntries(new FormData(form));
  const existing = state.trips.find(trip => trip.id === form.dataset.id);
  const ownerID = state.user?.id;
  if (existing && navigator.onLine && queuedOperationCount() === 0 && form.dataset.originalUpdatedAt) {
    const latest = (await getRows('trips', { id: `eq.${existing.id}`, limit: '1' }))[0];
    if (state.user?.id !== ownerID) throw Error('账号已切换，草稿未保存。');
    if (!latest || latest.updated_at !== form.dataset.originalUpdatedAt) throw Error('此行程已在其他设备更新。当前草稿已保留，请重新同步后核对再编辑。');
  }
  const { stops: _stops, expenses: _expenses, ...existingColumns } = existing || {};
  const customer = customerByID(data.customer_id);
  const now = new Date().toISOString();
  const formDateAt = (day, time = '00:00') => form.dataset.timeZone ? zonedISO(day, time, form.dataset.timeZone) : dateAt(day, time);
  const appointmentDate = formDateAt(data.appointment_date);
  const appointmentTime = formDateAt(data.appointment_date, data.appointment_time);
  const row = {
    ...existingColumns, id: form.dataset.id, owner_id: state.user.id,
    service_type: data.service_type, order_source: data.order_source,
    travel_agency_code: data.order_source === "旅行社订单" ? (data.travel_agency_code || "") : "",
    travel_agency_name: data.order_source === "旅行社订单" ? (data.travel_agency_name || "") : "",
    travel_agency_order_number: data.order_source === "旅行社订单" ? (data.travel_agency_order_number || "").trim() : "",
    customer_id: data.customer_id || null, customer_name: data.customer_name.trim(),
    customer_contact: data.customer_contact.trim(), customer_count: data.customer_count || "1",
    customer_stuff: data.customer_stuff || "0", appointment_date: appointmentDate, appointment_time: appointmentTime,
    location_start: data.location_start.trim(), location_end: data.location_end.trim(),
    flight_info: data.flight_info.trim().toUpperCase(), flight_date: data.flight_date ? formDateAt(data.flight_date) : appointmentDate,
    flight_selection_snapshot: JSON.parse(data.flight_selection_snapshot || 'null'),
    flight_departure_time: data.flight_departure_time || null,
    flight_estimated_arrival_time: data.flight_estimated_arrival_time || null,
    flight_arrival_terminal: data.flight_arrival_terminal.trim(),
    flight_baggage_carousel: data.flight_baggage_carousel.trim(),
    memo: data.memo.trim(), price: Number(data.price || 0), tip: Number(data.tip || 0),
    is_paid: data.is_paid === "true", is_completed: existing?.is_completed || false, is_cancelled: existing?.is_cancelled || false,
    reminder_enabled: form.elements.reminder_enabled.checked,
    reminder_at: form.elements.reminder_enabled.checked ? formDateAt(data.reminder_date, data.reminder_time) : null,
    has_second_reminder: form.elements.reminder_enabled.checked && form.elements.has_second_reminder.checked,
    second_reminder_at: form.elements.reminder_enabled.checked && form.elements.has_second_reminder.checked ? formDateAt(data.second_reminder_date, data.second_reminder_time) : null,
    currency_code: state.settings?.currency_code || "USD", created_at: existing?.created_at || now, updated_at: now, deleted_at: null,
  };
  if (!readFlightSnapshot(row, airportCrosswalk)) row.flight_selection_snapshot = null;
  if (![row.price, row.tip].every(n => Number.isFinite(n) && n >= 0)) throw Error('车费和小费必须是非负金额。');
  if (customer && !data.customer_contact) {
    const preferred = contactRows(customer.id).find(contact => contact.is_default) || contactRows(customer.id)[0];
    row.customer_contact = preferred?.value || "";
  }
  if (row.order_source === "旅行社订单" && (!row.travel_agency_code || !row.travel_agency_name)) {
    throw new Error("请选择关联的旅行社。");
  }
  if (row.reminder_enabled && !row.reminder_at) throw new Error("请设置第一次提醒时间。");
  if (row.has_second_reminder && !row.second_reminder_at) throw new Error("请设置第二次提醒时间。");
  const stopAddresses = [...form.querySelectorAll("[data-stop-input]")].map(input => input.value.trim()).filter(Boolean);
  const stops = stopAddresses.map((address, position) => {
    const prior = existing?.stops?.[position];
    return { id: prior?.id || crypto.randomUUID(), position, address };
  });
  if (state.productEdition === "cloud") {
    const expenses = (existing?.expenses || []).map((item, position) => ({
      id: item.id, is_addition: Boolean(item.is_addition), title: item.title || "",
      amount: Number(item.amount || 0), position,
    }));
    await callOnlineRPC("save_online_trip", { p_trip: row, p_stops: stops, p_expenses: expenses });
  } else {
    await upsert("trips", row);
    if (existing) {
      const deletedAt = now;
      await patch("trip_stops", { trip_id: `eq.${row.id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt });
    }
    for (const [position, stop] of stops.entries()) {
      await upsert("trip_stops", {
        ...stop, owner_id: state.user.id, trip_id: row.id, updated_at: now, deleted_at: null,
      });
    }
  }
  if (state.user?.id !== ownerID) return;
  await loadData();
  if (state.user?.id !== ownerID) return;
  document.getElementById('modal-root')?.remove();
  renderApp(); showToast(existing ? "行程已更新。" : "行程已新增。");
}

async function submitSettings(form) {
  const ownerID = state.user?.id;
  if (!ownerID) throw new Error("请先登录云端账号。");
  const data = Object.fromEntries(new FormData(form));
  const currencies = { US: ["美元", "US Dollar", "USD", "$"], CN: ["人民币", "Chinese Yuan", "CNY", "¥"], CA: ["加拿大元", "Canadian Dollar", "CAD", "CA$"], JP: ["日元", "Japanese Yen", "JPY", "¥"], GB: ["英镑", "British Pound", "GBP", "£"], AU: ["澳元", "Australian Dollar", "AUD", "A$"], KR: ["韩元", "South Korean Won", "KRW", "₩"], ES: ["欧元", "Euro", "EUR", "€"], FR: ["欧元", "Euro", "EUR", "€"], DE: ["欧元", "Euro", "EUR", "€"], HK: ["港元", "Hong Kong Dollar", "HKD", "HK$"], TW: ["新台币", "New Taiwan Dollar", "TWD", "NT$"], SG: ["新加坡元", "Singapore Dollar", "SGD", "S$"], MX: ["墨西哥比索", "Mexican Peso", "MXN", "MX$"], IN: ["印度卢比", "Indian Rupee", "INR", "₹"], CH: ["瑞士法郎", "Swiss Franc", "CHF", "CHF"] };
  const [name, , code, symbol] = currencies[data.currency_country_code] || currencies.US;
  const settings = { ...(state.settings || {}), owner_id: ownerID, language_code: data.language_code, currency_country_code: data.currency_country_code, currency_name: name, currency_code: code, currency_symbol: symbol, navigation_provider: data.navigation_provider || "appleMaps", updated_at: new Date().toISOString() };
  await upsert("user_settings", settings, "owner_id");
  if (state.user?.id !== ownerID) return;
  setAccountPreference("navigation", data.navigation_provider || "appleMaps");
  state.settings = settings; renderApp(); showToast(ui("设置已保存。"));
}

async function logout() {
  try { await request("rpc/release_account_device", { method: "POST", body: { p_device_id: accountDeviceID() }, queueOffline: false }); } catch { /* signing out must still work if device release fails */ }
  try { await request("/auth/v1/logout", { method: "POST", query: { scope: "local" } }); } catch { /* local session is still cleared */ }
  clearSession(); state.error = ""; renderLogin();
}

function handleTripFormEnter(event) {
  if (event.key !== "Enter") return;
  const input = event.target;
  const form = input?.form;
  if (form?.id !== "tripForm") return;
  if (input.tagName !== "INPUT" || ["submit", "button"].includes(input.type)) {
    delete form.dataset.blockEnterSubmit;
    return;
  }
  // Preserve native datalist/IME handling, but reject the browser's implicit
  // form submission in the same key event. An explicit Save remains available.
  form.dataset.blockEnterSubmit = "true";
  setTimeout(() => { delete form.dataset.blockEnterSubmit; }, 0);
}
document.addEventListener("keydown", handleTripFormEnter);
document.addEventListener("keyup", event => {
  if (event.key === "Enter" && event.target?.form?.id === "tripForm") delete event.target.form.dataset.blockEnterSubmit;
});
document.addEventListener("pointerdown", event => {
  const form = event.target.closest("button")?.form;
  if (form?.id === "tripForm") delete form.dataset.blockEnterSubmit;
});

document.addEventListener("submit", async event => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  event.preventDefault();
  if (form.id === "tripForm" && form.dataset.blockEnterSubmit === "true") return;
  if (form.dataset.submitting === 'true') return;
  form.dataset.submitting = 'true';
  const submitButtons = [...document.querySelectorAll(`button[type="submit"][form="${form.id}"]`), ...form.querySelectorAll('button[type="submit"]')];
  submitButtons.forEach(button => button.disabled = true);
  try {
    if (form.id === "deleteAccountForm") return await submitAccountDeletion(form);
    if (form.id === "loginForm") return await doLogin(form);
    if (form.id === "authForm") return await submitAuthForm(form);
    if (form.id === "customerForm") return await submitCustomer(form);
    if (form.id === "agencyForm") return await submitAgency(form);
    if (form.id === "tripForm") return await submitTrip(form);
    if (form.id === "settlementForm") return await submitSettlement(form, event.submitter?.dataset.settlementMode === "settle");
    if (form.id === "settingsForm") return await submitSettings(form);
  } catch (error) { showToast(ui(error.message || "操作失败，请稍后重试。"), true); }
  finally { form.dataset.submitting = 'false'; submitButtons.forEach(button => button.disabled = false); }
});

function locateTripAddress(button) {
  const form = button.closest("form");
  const target = button.dataset.target;
  const resolveInput = () => target === "start" ? form?.elements.location_start : target === "end" ? form?.elements.location_end : form?.querySelector(`[data-stop-index="${target.split(":")[1]}"]`);
  const input = resolveInput();
  if (!form || !input || button.disabled) return;
  if (!navigator.geolocation) throw new Error("此浏览器不支持定位功能。");
  const originalValue = input.value, ownerID = state.user?.id, generation = workspaceGeneration;
  const stillCurrent = () => form.isConnected && document.getElementById("tripForm") === form && state.user?.id === ownerID && workspaceGeneration === generation && resolveInput() === input && input.value === originalValue;
  button.disabled = true;
  try {
    navigator.geolocation.getCurrentPosition(position => {
      button.disabled = false;
      if (!stillCurrent()) return;
      const {latitude, longitude} = position.coords;
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
        showToast("无法获取有效位置，请重试。", true); return;
      }
      input.value = `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
      invalidateFormFlight(form);
    }, error => {
      button.disabled = false;
      if (stillCurrent()) showToast(error.message || "无法获取当前位置，请检查浏览器定位权限。", true);
    }, {enableHighAccuracy:true, timeout:12000});
  } catch (error) { button.disabled = false; throw error; }
}

function invalidateFormFlight(form) {
  if (!form?.elements.flight_selection_snapshot) return;
  form.elements.flight_selection_snapshot.value = 'null';
  for (const name of ['flight_departure_time','flight_estimated_arrival_time','flight_arrival_terminal','flight_baggage_carousel']) form.elements[name].value = '';
  form.querySelector('[data-flight-result]')?.classList.add('hidden');
  form.querySelector('[data-flight-feedback]')?.classList.add('hidden');
  const queryButton = form.querySelector('[data-action="lookup-flight"]');
  if(queryButton) queryButton.disabled = !form.elements.flight_info.value.trim();
}
function updateAddressSuggestions(input) {
  const form=input.closest('#tripForm'); if(!form)return;
  const query=input.value.trim().toLocaleLowerCase();
  const saved=[...state.addresses.map(a=>a.address),...state.trips.flatMap(t=>[t.location_start,t.location_end,...(t.stops||[]).map(s=>s.address)])].filter(Boolean);
  const airports=query.length>=2?airportCrosswalk.filter(a=>[a.iata_code,a.name,...a.keywords||[]].some(v=>v.toLocaleLowerCase().includes(query))).slice(0,6).map(a=>`${a.iata_code} ${a.name}`):[];
  form.querySelector('#tripAddressSuggestions').innerHTML=[...new Set([...saved.filter(a=>!query||a.toLocaleLowerCase().includes(query)),...airports])].slice(0,12).map(a=>`<option value="${escapeHTML(a)}"></option>`).join('');
}
document.addEventListener("input", event => {
  if (["loginForm", "authForm"].includes(event.target.form?.id) && ["email", "salutation", "phone"].includes(event.target.name)) authDraft[event.target.name] = event.target.value;
  if (event.target.form?.id === 'tripForm' && ['flight_info','flight_date','service_type','location_start','location_end'].includes(event.target.name)) invalidateFormFlight(event.target.form);
  if (event.target.matches('[name="location_start"], [name="location_end"], [data-stop-input]')) updateAddressSuggestions(event.target);
  if (event.target.matches("[data-flight-number]")) {
    const start = event.target.selectionStart;
    const value = event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (event.target.value !== value) {
      event.target.value = value;
      event.target.setSelectionRange(Math.min(start ?? value.length, value.length), Math.min(start ?? value.length, value.length));
    }
    return;
  }
  if (event.target.matches("[data-card-field='nickname']")) {
    state.businessCard.nickname = event.target.value;
    const previewName = document.querySelector(".business-card-preview .preview-heading strong");
    if (previewName) previewName.textContent = event.target.value || state.user?.user_metadata?.salutation || "未填写";
    return;
  }
  if (event.target.matches("[data-card-qr-name]")) {
    const qr = state.businessCard.qrCodes.find(item => item.id === event.target.dataset.cardQrName);
    if (qr) qr.name = event.target.value;
    return;
  }
  if (event.target.matches("[data-payment-name]")) {
    const method = state.paymentMethods.find(item => item.id === event.target.dataset.paymentName);
    if (method) method.name = event.target.value;
    return;
  }
  const customerPickerSearch = event.target.closest("[data-customer-picker-search]");
  if (customerPickerSearch) {
    const query = customerPickerSearch.value.trim().toLocaleLowerCase();
    document.querySelectorAll("[data-customer-option]").forEach(row => {
      row.classList.toggle("hidden", query !== "" && !row.textContent.toLocaleLowerCase().includes(query));
    });
    return;
  }
  const settlementForm = event.target.closest("#settlementForm");
  if (settlementForm) {
    captureSettlementDraft(settlementForm);
    const draft = state.settlementDraft;
    const total = draft.price + draft.tip + draft.expenses.reduce((sum, item) => sum + (item.is_addition ? 1 : -1) * Number(item.amount || 0), 0);
    const net = settlementForm.querySelector("#settlement-net-value");
    if (net) net.textContent = currency(total);
    return;
  }
  const tripForm = event.target.closest("#tripForm");
  if (tripForm) {
    if (["reminder_date", "reminder_time", "second_reminder_date", "second_reminder_time"].includes(event.target.name)) event.target.dataset.customized = "true";
    if (["appointment_date", "appointment_time"].includes(event.target.name)) {
      const defaults = reminderDefaults(tripForm.elements.appointment_date.value, tripForm.elements.appointment_time.value);
      const updateDefault = (name, value) => { const input = tripForm.elements[name]; if (input && input.dataset.customized !== "true") input.value = value; };
      updateDefault("reminder_date", defaults.firstDate); updateDefault("reminder_time", defaults.firstTime);
      updateDefault("second_reminder_date", defaults.secondDate); updateDefault("second_reminder_time", defaults.secondTime);
    }
    return;
  }
  const input = event.target.closest("[data-search]");
  if (!input) return;
  const selection = input.selectionStart;
  const searchType = input.dataset.search;
  state.search = input.value;
  const content = document.getElementById("pageContent");
  if (content) {
    content.innerHTML = renderPage();
    const replacement = content.querySelector(`[data-search="${searchType}"]`);
    replacement?.focus();
    if (replacement && selection !== null) replacement.setSelectionRange(selection, selection);
  }
});

document.addEventListener("focusin", event => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement)) return;
  if (input.matches('[name="location_start"], [name="location_end"], [data-stop-input]')) updateAddressSuggestions(input);
  if (input.type !== "number") return;
  const isMoney = ["price", "tip"].includes(input.name) || input.name.startsWith("expense_amount_");
  if (!isMoney) return;
  if (/^0+(?:\.0+)?$/.test(input.value.trim())) input.value = "";
  else input.select();
});

document.addEventListener("change", event => {
  if (event.target.id === "authLanguage") { changeAuthLanguage(event.target.value); return; }
  if (event.target.form?.id === 'tripForm' && ['flight_info','flight_date','service_type','location_start','location_end'].includes(event.target.name)) invalidateFormFlight(event.target.form);
  if (event.target.matches("[data-card-photo]")) {
    const file = event.target.files?.[0];
    if (file) void setCardPhoto(file);
    return;
  }
  if (event.target.matches("[data-card-qr-image]")) {
    const file = event.target.files?.[0];
    if (file) void setQRImage("card", event.target.dataset.cardQrImage, file);
    return;
  }
  if (event.target.matches("[data-payment-image]")) {
    const file = event.target.files?.[0];
    if (file) void setQRImage("payment", event.target.dataset.paymentImage, file);
    return;
  }
  if (event.target.matches("[data-card-field='nickname'], [data-card-qr-name]")) void saveBusinessCard().catch(error => showToast(error.message || "名片同步失败。", true));
  if (event.target.matches("[data-payment-name]")) void savePaymentMethods().catch(error => showToast(error.message || "收款方式同步失败。", true));
  if (event.target.name === "service_type") {
    const picker = event.target.closest(".service-type-picker");
    picker?.querySelectorAll(".service-type-option").forEach(option => {
      const selected = option.contains(event.target);
      option.classList.toggle("selected", selected);
      const input = option.querySelector("input");
      const icon = option.querySelector(".service-type-icon");
      if (icon && input) icon.innerHTML = appIcon(selected ? "checkmark.circle.fill" : serviceSymbol(input.value, "picker"));
    });
    return;
  }
  if (event.target.name === "category" && event.target.form?.id === "customerForm") {
    const form = event.target.form;
    form.querySelectorAll(".customer-category-option").forEach(option => option.classList.toggle("selected", option.contains(event.target)));
    form.querySelector(".customer-agency-fields")?.classList.toggle("hidden", event.target.value !== "2");
    if (event.target.value !== "2") {
      form.elements.travel_agency_code.value = ""; form.elements.travel_agency_name.value = "";
      form.querySelector("[data-agency-code-label]").textContent = "尚未选择";
      form.querySelector("[data-agency-name-label]").textContent = "点击选择旅行社";
    }
    return;
  }
  if (event.target.name === "order_source") {
    const form = event.target.form;
    form?.querySelectorAll(".order-source-option").forEach(option => option.classList.toggle("selected", option.contains(event.target)));
    const agencyFields = form?.querySelector(".agency-info-fields");
    if (agencyFields) agencyFields.classList.toggle("hidden", event.target.value !== "旅行社订单");
    if (event.target.value !== "旅行社订单" && form) {
      form.elements.travel_agency_code.value = "";
      form.elements.travel_agency_name.value = "";
      form.elements.travel_agency_order_number.value = "";
      form.querySelector("[data-agency-code-label]").textContent = "尚未选择";
      form.querySelector("[data-agency-name-label]").textContent = "点击选择旅行社";
    }
    return;
  }
  if (event.target.name === "reminder_enabled") {
    event.target.form.querySelector(".reminder-fields")?.classList.toggle("hidden", !event.target.checked);
    if (event.target.checked && "Notification" in window && Notification.permission === "default") Notification.requestPermission();
    return;
  }
  if (event.target.name === "has_second_reminder") {
    event.target.form.querySelector(".second-reminder-fields")?.classList.toggle("hidden", !event.target.checked);
    return;
  }
  if (["reminder_date", "reminder_time", "second_reminder_date", "second_reminder_time"].includes(event.target.name)) {
    event.target.dataset.customized = "true";
    return;
  }
  if (event.target.name !== "customer_id" || !event.target.form) return;
  const customer = customerByID(event.target.value);
  if (!customer) { event.target.form.elements.customer_name.value = ""; event.target.form.elements.customer_contact.value = ""; event.target.form.querySelector("#tripAddressSuggestions")?.replaceChildren(); return; }
  event.target.form.elements.customer_name.value = customer.name;
  const contact = contactRows(customer.id).find(item => item.is_default) || contactRows(customer.id)[0];
  event.target.form.elements.customer_contact.value = contact?.value || "";
  const suggestions = event.target.form.querySelector("#tripAddressSuggestions");
  if (suggestions) suggestions.innerHTML = addressRows(customer.id).map(address => `<option value="${escapeHTML(address.address)}">${escapeHTML(address.label || "常用地址")}</option>`).join("");
});

document.addEventListener("click", async event => {
  if (event.target.closest('a[href^="tel:"], a[href^="sms:"]')) return;
  const financeSummary = event.target.closest(".finance-trip-snapshot > summary");
  if (financeSummary) { event.preventDefault(); toggleFinanceRecord(financeSummary.parentElement); return; }
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  try {
    if (action === "toggle-trip-contact") {
      event.preventDefault(); event.stopPropagation();
      const id = button.dataset.id;
      expandedTripContacts.has(id) ? expandedTripContacts.delete(id) : expandedTripContacts.add(id);
      renderApp();
    }
    else if (action === "statement-preview") openAgencyStatement();
    else if (action === "statement-export") exportAgencyStatement();
    else if (action === "statement-share") await shareAgencyStatement();
    else if (action === "statement-all") { statementSelection = new Set(agencyStatementTrips(state.trips, statementAgency).map(t => t.id)); renderApp(); }
    else if (action === "statement-none") { statementSelection.clear(); renderApp(); }
    else if (action === "delete-cloud-account") showAccountDeletion();
    else if (action === "export-expired-archive") exportExpiredArchive();
    else if (action === "retry-expired-archive") await initialize();
    else if (action === "auth-screen") {
      if(state.busy)return;
      authScreen=["login","register","recover"].includes(button.dataset.mode)?button.dataset.mode:"login";
      state.error="";authNotice="";recoveryCredentials=null;renderLogin();
    }
    else if(action === "auth-password-visibility") toggleAuthPassword(button);
    else if(action === "auth-resend") await resendAuthEmail(button.closest("form"));
    else if (action === "navigate") { state.page = button.dataset.page; state.search = ""; renderApp(); }
    else if (action === "toggle-trip-amounts") toggleTripAmounts(button.dataset.id);
    else if (action === "signout") await logout();
    else if (action === "refresh-data") {
      if (queuedOperationCount() > 0 && navigator.onLine) await replayOfflineQueue();
      await loadData(); renderApp(); showToast(state.offline ? "当前显示本机缓存，联网后会继续同步。" : "已从云端更新数据。");
    }
    else if (action === "retry-offline-load") await initialize();
    else if (action === "new-trip") openTripForm();
    else if (action === "new-customer") openCustomerForm();
    else if (action === "new-agency") openAgencyForm();
    else if (action === "add-payment-method") {
      state.paymentMethods.push({ id: crypto.randomUUID(), name: "", qrImageData: null });
      updatePageContent();
      await savePaymentMethods();
    }
    else if (action === "remove-payment-method") {
      const removedMethod = state.paymentMethods.find(item => item.id === button.dataset.id);
      state.paymentMethods = state.paymentMethods.filter(item => item.id !== button.dataset.id);
      updatePageContent();
      await savePaymentMethods(false, [removedMethod?.qrImagePath].filter(Boolean));
    }
    else if (action === "add-card-qr") {
      state.businessCard.qrCodes.push({ id: crypto.randomUUID(), name: "", imageData: null });
      updatePageContent();
      await saveBusinessCard();
    }
    else if (action === "remove-card-qr") {
      const removedQR = state.businessCard.qrCodes.find(item => item.id === button.dataset.id);
      state.businessCard.qrCodes = state.businessCard.qrCodes.filter(item => item.id !== button.dataset.id);
      updatePageContent();
      await saveBusinessCard(false, [removedQR?.imagePath].filter(Boolean));
    }
    else if (action === "card-style") {
      state.businessCard.style = Number(button.dataset.style);
      updatePageContent();
      await saveBusinessCard();
    }
    else if (action === "save-business-card") await saveBusinessCard();
    else if (action === "remove-card-photo") {
      const removedPath = state.businessCard.portraitPath;
      state.businessCard.portraitData = null;
      delete state.businessCard.portraitPath;
      updatePageContent();
      await saveBusinessCard(false, [removedPath].filter(Boolean));
    }
    else if (action === "preview-card-qr") showQRPreview("名片二维码", state.businessCard.qrCodes.find(item => item.id === button.dataset.id)?.imageData, state.businessCard.qrCodes.find(item => item.id === button.dataset.id)?.name, "card", button.dataset.id);
    else if (action === "preview-payment-qr") showQRPreview("收款二维码", state.paymentMethods.find(item => item.id === button.dataset.id)?.qrImageData, state.paymentMethods.find(item => item.id === button.dataset.id)?.name, "payment", button.dataset.id);
    else if (action === "share-qr") await shareQR(button.dataset.kind, button.dataset.id);
    else if (action === "edit-trip") openTripForm(state.trips.find(item => item.id === button.dataset.id));
    else if (action === "copy-trip") openTripForm(state.trips.find(item => item.id === button.dataset.id), true);
    else if (action === "view-trip") openTripDetail(state.trips.find(item => item.id === button.dataset.id));
    else if (action === "view-customer") openCustomerDetail(customerByID(button.dataset.id));
    else if (action === "edit-customer") openCustomerForm(customerByID(button.dataset.id));
    else if (action === "add-customer-contact") {
      const rows = button.closest(".field").querySelector(".customer-contact-rows");
      rows.insertAdjacentHTML("beforeend", customerContactField({}, rows.querySelectorAll("[data-contact-row]").length));
    }
    else if (action === "add-customer-address") {
      const rows = button.closest(".field").querySelector(".customer-address-rows");
      rows.insertAdjacentHTML("beforeend", customerAddressField({}, rows.querySelectorAll("[data-address-row]").length));
    }
    else if (action === "remove-customer-row") {
      const row = button.closest("[data-contact-row], [data-address-row]");
      const parent = row.parentElement;
      const defaultWasRemoved = row.querySelector('input[type="radio"]')?.checked;
      row.remove();
      const rows = [...parent.children];
      rows.forEach((item, index) => { const radio = item.querySelector('input[type="radio"]'); radio.value = index; if (defaultWasRemoved && index === 0) radio.checked = true; });
    }
    else if (action === "build-information") showModal(escapeHTML(ui('版本信息')), `<p class="completion-prompt-copy">${escapeHTML(ui('Web 构建'))}<br><strong>${escapeHTML(WEB_BUILD)}</strong></p><div class="form-actions"><button class="button primary" data-action="close-modal">${escapeHTML(ui('关闭'))}</button></div>`, "completion-prompt-modal");
    else if (action === "edit-agency") openAgencyForm(state.agencies.find(item => item.id === button.dataset.id));
    else if (action === "navigate-saved-address") {
      const encoded = encodeURIComponent(button.dataset.address || "");
      const url = (getAccountPreference("navigation") || "appleMaps") === "googleMaps" ? `https://www.google.com/maps/dir/?api=1&destination=${encoded}&travelmode=driving` : `https://maps.apple.com/?daddr=${encoded}&dirflg=d`;
      window.open(url, "_blank", "noopener");
    }
    else if (action === "close-modal") { pendingTripCompletion=null; document.getElementById("modal-root")?.remove(); state.pickupPreview=null; state.flightPicker=null; }
    else if (action === "close-picker") { document.getElementById("picker-backdrop")?.remove(); state.pickupPreview=null; state.flightPicker=null; }
    else if (action === "pick-agency") openAgencyPicker(button.dataset.form || "tripForm");
    else if (action === "pick-trip-customer") openTripCustomerPicker();
    else if (action === "clear-trip-customer") {
      const form = button.closest("form");
      if (form) {
        form.elements.customer_id.value = "";
        form.elements.customer_name.value = "";
        form.elements.customer_contact.value = "";
        form.querySelector("[data-trip-customer-label]").textContent = "选择或搜索客户";
        form.querySelector("#tripAddressSuggestions")?.replaceChildren();
      }
    }
    else if (action === "select-trip-customer") {
      const form = document.getElementById("tripForm");
      if (form) {
        form.elements.customer_id.value = button.dataset.customerId || "";
        form.querySelector("[data-trip-customer-label]").textContent = button.dataset.customerName || "选择或搜索客户";
        form.elements.customer_name.value = button.dataset.customerName || "";
        form.elements.customer_contact.value = button.dataset.customerContact || "";
        const customer = customerByID(button.dataset.customerId || "");
        const suggestions = form.querySelector("#tripAddressSuggestions");
        if (suggestions) suggestions.innerHTML = addressRows(customer?.id || "").map(address => `<option value="${escapeHTML(address.address)}">${escapeHTML(address.label || "常用地址")}</option>`).join("");
      }
      document.getElementById("picker-backdrop")?.remove();
    }
    else if (action === "select-agency") {
      const form = document.getElementById(button.dataset.form || "tripForm");
      if (form) {
        form.elements.travel_agency_code.value = button.dataset.code;
        form.elements.travel_agency_name.value = button.dataset.name;
        form.querySelector("[data-agency-code-label]").textContent = button.dataset.code;
        form.querySelector("[data-agency-name-label]").textContent = button.dataset.name;
      }
      document.getElementById("picker-backdrop")?.remove();
    }
    else if (action === "pick-address") {
      const form = document.getElementById("tripForm");
      if (form) openAddressPicker(form, button.dataset.target);
    }
    else if (action === "select-address") {
      const form = document.getElementById("tripForm");
      const target = button.dataset.target;
      const input = target === "start" ? form?.elements.location_start : target === "end" ? form?.elements.location_end : form?.querySelector(`[data-stop-index="${target.split(":")[1]}"]`);
      if (input) { input.value = button.dataset.address || ""; invalidateFormFlight(form); }
      document.getElementById("picker-backdrop")?.remove();
    }
    else if (action === "add-stop") {
      const form = button.closest("form");
      const list = form?.querySelector(".stops-list");
      if (list) { list.insertAdjacentHTML("beforeend", stopField("", list.querySelectorAll("[data-stop-input]").length)); renumberStopFields(form); }
    }
    else if (action === "remove-stop") { const form = button.closest("form"); button.closest(".stop-field")?.remove(); if (form) renumberStopFields(form); }
    else if (action === "swap-route") {
      const form = button.closest("form");
      if (form) { const start = form.elements.location_start.value; form.elements.location_start.value = form.elements.location_end.value; form.elements.location_end.value = start; invalidateFormFlight(form); }
    }
    else if (action === "current-location") locateTripAddress(button);
    else if (action === "navigate-address") {
      const form = button.closest("form");
      const target = button.dataset.target;
      const input = target === "start" ? form?.elements.location_start : target === "end" ? form?.elements.location_end : form?.querySelector(`[data-stop-index="${target.split(":")[1]}"]`);
      const address = input?.value.trim();
      if (!address) throw new Error("请先输入或选择地址。");
      const encoded = encodeURIComponent(address);
      const url = (getAccountPreference("navigation") || "appleMaps") === "googleMaps" ? `https://www.google.com/maps/dir/?api=1&destination=${encoded}&travelmode=driving` : `https://maps.apple.com/?daddr=${encoded}&dirflg=d`;
      window.open(url, "_blank", "noopener");
    }
    else if (action === "lookup-flight") await lookupFlight(button.closest("form"));
    else if (action === "select-flight-candidate") {
      const picker = state.flightPicker;
      const candidate = picker?.candidates[Number(button.dataset.index)];
      if (candidate && picker.ownerID === state.user?.id) { await picker.select(candidate); state.flightPicker = null; document.getElementById('picker-backdrop')?.remove(); }
    }
    else if (action === "refresh-flight-card") await refreshFlightCard(state.trips.find(t => t.id === button.dataset.id));
    else if (action === "recognize-pickup") previewPickup(button.closest('form'));
    else if (action === "apply-pickup") applyPickup();
    else if (action === "trip-filter") { state.tripFilter = button.dataset.filter; state.tripDate = ""; updatePageContent(); }
    else if (action === "trip-date") {
      if (state.page === "home") state.homeDate = button.dataset.date;
      else state.tripDate = button.dataset.date;
      updatePageContent();
    }
    else if (action === "trip-date-all") {
      if (state.page === "home") state.homeDate = "";
      else state.tripDate = "";
      updatePageContent();
    }
    else if (action === "trip-date-mode") { state.tripDateMode = button.dataset.mode; updatePageContent(); }
    else if (action === "calendar-month") { state.tripCalendarMonth = new Date(state.tripCalendarMonth.getFullYear(), state.tripCalendarMonth.getMonth() + Number(button.dataset.step), 1); updatePageContent(); }
    else if (action === "flight-toggle") {
      if (state.expandedFlights.has(button.dataset.id)) state.expandedFlights.delete(button.dataset.id);
      else state.expandedFlights.add(button.dataset.id);
      updatePageContent();
    }
    else if (action === "toggle-complete") requestTripCompletion(button.dataset.id);
    else if (action === "confirm-trip-completion") await confirmTripCompletion(button);
    else if (action === "completion-settlement") {
      const trip = state.trips.find(item => item.id === button.dataset.id);
      if (trip?.is_completed) openSettlement(trip);
    }
    else if (action === "cancel-trip") {
      if (confirm("是否需要取消行程？")) await markTrip(button.dataset.id, { is_cancelled: true, is_completed: false, updated_at: new Date().toISOString() });
    }
    else if (action === "restore-trip") await markTrip(button.dataset.id, { is_cancelled: false, is_completed: false, updated_at: new Date().toISOString() });
    else if (action === "toggle-paid") { const trip = state.trips.find(item => item.id === button.dataset.id); if (trip) openSettlement(trip); }
    else if (action === "add-expense") {
      const form = document.getElementById("settlementForm");
      if (form) captureSettlementDraft(form);
      state.settlementDraft.expenses.push({ is_addition: false, title: "", amount: 0 });
      const trip = state.trips.find(item => item.id === state.settlementDraft.tripID);
      if (trip) renderSettlementModal(trip);
    }
    else if (action === "add-expense-name") {
      document.querySelector(".expense-name-list")?.insertAdjacentHTML("beforeend", '<div class="expense-name-row"><input data-expense-name placeholder="费用名称"><button class="button small danger" data-action="remove-expense-name">−</button></div>');
      document.querySelector(".expense-name-list [data-expense-name]:last-of-type")?.focus();
    }
    else if (action === "remove-expense-name") button.closest(".expense-name-row")?.remove();
    else if (action === "save-expense-catalog") {
      const ownerID = state.user?.id;
      if (!ownerID) throw new Error("请先登录云端账号。");
      const names = [...document.querySelectorAll("[data-expense-name]")].map(input => input.value.trim()).filter(Boolean);
      const unique = [...new Set(names)];
      const settings = { ...(state.settings || defaultSettings()), owner_id: ownerID, expense_catalog: unique, updated_at: new Date().toISOString() };
      await upsert("user_settings", settings, "owner_id");
      if (state.user?.id !== ownerID) return;
      localStorage.setItem(accountPreferenceKey("expense-catalog", ownerID), JSON.stringify(unique));
      state.settings = settings;
      updatePageContent(); showToast(ui("费用项目已保存。"));
    }
    else if (action === "remove-expense") {
      const form = document.getElementById("settlementForm");
      if (form) captureSettlementDraft(form);
      state.settlementDraft.expenses.splice(Number(button.dataset.index), 1);
      const trip = state.trips.find(item => item.id === state.settlementDraft.tripID);
      if (trip) renderSettlementModal(trip);
    }
    else if (action === "delete-trip") await deleteTrip(button.dataset.id);
    else if (action === "delete-customer") await deleteCustomer(button.dataset.id);
    else if (action === "delete-agency") await deleteAgency(button.dataset.id);
    else if (action === "finance-snapshots") openFinanceSnapshots(button.dataset.start, button.dataset.end);
    else if (action === "wallet-period") { location.hash = `period=${button.dataset.period}&anchor=${dateInput(new Date())}`; updatePageContent(); }
    else if (action === "wallet-shift") {
      const params = new URLSearchParams(location.hash.slice(1));
      const period = params.get("period") || "day";
      const anchor = params.has("anchor") ? new Date(`${params.get("anchor")}T12:00:00`) : new Date();
      const amount = Number(button.dataset.step);
      const shifted = shiftFinanceAnchor(anchor, period, amount);
      location.hash = `period=${period}&anchor=${dateInput(shifted)}`; updatePageContent();
    }
  } catch (error) { showToast(ui(error.message || "操作失败，请稍后重试。"), true); }
});

let foregroundRefreshTask = null;
async function refreshOnForeground() {
  if (!state.user || document.visibilityState === 'hidden' || !navigator.onLine || foregroundRefreshTask) return;
  const ownerID=state.user.id;
  foregroundRefreshTask=(async()=>{
    try {
      if(queuedOperationCount()>0)await replayOfflineQueue();
      await loadData();
      if(state.user?.id!==ownerID)return;
      if(!document.getElementById('modal-root'))renderApp(); else renderConnectionStatus();
    } catch(error) {if(state.user?.id===ownerID){state.offline=isNetworkFailure(error);renderConnectionStatus();}}
    finally {foregroundRefreshTask=null;}
  })();
  return foregroundRefreshTask;
}
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')void refreshOnForeground();});
window.addEventListener('pageshow',()=>{void refreshOnForeground();});

 document.addEventListener("change", event => {
  if (event.target.id === 'statementAgency') { statementAgency = event.target.value; statementSelection.clear(); renderApp(); }
  if (event.target.matches('[data-statement-trip]')) { const id = event.target.dataset.statementTrip; if(event.target.checked) statementSelection.add(id); else statementSelection.delete(id); renderApp(); }
});

initialize();
