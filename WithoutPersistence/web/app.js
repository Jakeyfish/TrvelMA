const SUPABASE_URL = "https://lbdfqzeiweqbsklklcqr.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_d4tmuPirsf8-wUDO0Frd7w_PcXME6rs";
const SESSION_KEY = "yunsheng.web.session.v1";
const OFFLINE_CACHE_PREFIX = "yunsheng.web.offline-cache.v1.";
const OFFLINE_QUEUE_PREFIX = "yunsheng.web.offline-queue.v1.";
const ACCOUNT_PREFERENCE_PREFIX = "yunsheng.web.account-preference.v1.";
// These legacy keys were shared by every browser account and have no reliable
// owner. Discard them instead of exposing one account's settings to another.
["yunsheng.web.navigation", "yunsheng.web.variflight-key", "yunsheng.web.expense-catalog"]
  .forEach(key => localStorage.removeItem(key));
let sessionRefreshTask = null;
let offlineReplayTask = null;
let offlineRetryTimer = null;
let offlineRetryCount = 0;
let networkToastShownForCurrentOutage = false;
const webReminderTimers = new Map();

const state = {
  session: readSession(),
  user: null,
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
  wallet: ["钱包", "查看收入、费用和净收入"],
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
  for (const timer of webReminderTimers.values()) clearTimeout(timer);
  webReminderTimers.clear();
  state.page = "home";
  state.customers = [];
  state.contacts = [];
  state.addresses = [];
  state.trips = [];
  state.agencies = [];
  state.stops = [];
  state.expenses = [];
  state.settings = null;
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

async function authRequest(path, body) {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: "POST",
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
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
  if (lower.includes("invalid login credentials")) return "邮箱或密码不正确。";
  if (lower.includes("email not confirmed")) return "请先完成邮箱验证，再登录。";
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
  badge.textContent = offline ? `离线${count ? ` · ${count} 项待同步` : ""}`
    : count ? `${count} 项待同步` : "云端已连接";
}

function writeOfflineCache(snapshot, userID = state.user?.id) {
  if (!userID) return;
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
  const settings = snapshot.settings?.[0];
  if (!settings) return;
  const card = settings.business_card_data;
  const payments = settings.wallet_payment_methods;
  for (const operation of operations) {
    if (operation.kind !== "storage-upload" || operation.owner_id !== userID) continue;
    const path = operation.path.split("/account-assets/")[1] || "";
    if (!path.startsWith(`${userID}/`)) continue;
    const relative = path.slice(userID.length + 1);
    if (relative === "business-card/portrait.jpg" && card) card.portraitData = operation.base64;
    else {
      const cardQR = relative.match(/^business-card\/qr\/([^/]+)\.jpg$/);
      if (cardQR && card) {
        const qr = card.qrCodes?.find(item => item.id === cardQR[1]);
        if (qr) qr.imageData = operation.base64;
      }
      const paymentQR = relative.match(/^payment-methods\/([^/]+)\.jpg$/);
      if (paymentQR && payments) {
        const method = payments.methods?.find(item => item.id === paymentQR[1]);
        if (method) method.qrImageData = operation.base64;
      }
    }
  }
}

function persistOfflineOperation(operation, userID = state.user?.id) {
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

async function replayOfflineQueue() {
  if (!navigator.onLine || !state.user?.id || offlineReplayTask || queuedOperationCount() === 0) return;
  const replayUserID = state.user.id;
  clearTimeout(offlineRetryTimer);
  offlineRetryTimer = null;
  offlineReplayTask = (async () => {
    let blockedByServer = false;
    try {
      while (state.user?.id === replayUserID && readOfflineQueue(replayUserID).operations.length > 0 && navigator.onLine) {
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
          const binary = atob(operation.base64);
          const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
          await storageRequest(operation.path, {
            method: "POST", body: new Blob([bytes], { type: operation.contentType || "image/jpeg" }),
            contentType: operation.contentType || "image/jpeg", queueOffline: false,
          });
        } else {
          await request(operation.table, {
            method: operation.method, query: operation.query, body: operation.body,
            prefer: operation.prefer, queueOffline: false,
          });
        }
        if (state.user?.id !== replayUserID) break;
        const latest = readOfflineQueue(replayUserID);
        latest.operations = latest.operations.filter(item => item.id !== operation.id);
        latest.retryCount = 0;
        latest.nextRetryAt = null;
        if (latest.operations.length) localStorage.setItem(offlineQueueKey(replayUserID), JSON.stringify(latest));
        else localStorage.removeItem(offlineQueueKey(replayUserID));
        renderConnectionStatus();
      }
      if (state.user?.id !== replayUserID) return;
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
      if (state.user?.id !== replayUserID) return;
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
      if (state.user?.id === replayUserID && !blockedByServer && navigator.onLine && queuedOperationCount() > 0 && !offlineRetryTimer) scheduleOfflineQueueRetry();
    }
  })();
  return offlineReplayTask;
}

function isNetworkFailure(error) {
  return !navigator.onLine || error instanceof TypeError || error.status === 429 || error.status >= 500;
}

async function request(tableOrPath, { method = "GET", query = {}, body, prefer, queueOffline = true } = {}) {
  const requestUserID = state.user?.id;
  const isAuthPath = tableOrPath.startsWith("/auth/");
  const session = await currentSession();
  if (!session) throw new Error("云端登录状态已失效，请重新登录。");
  if (!isAuthPath && (!requestUserID || state.user?.id !== requestUserID || session.user?.id !== requestUserID)) {
    throw new Error("账号已切换，请重新加载当前账号资料。");
  }
  const url = apiURL(isAuthPath ? tableOrPath : `/rest/v1/${tableOrPath}`, query);
  const headers = {
    apikey: SUPABASE_PUBLISHABLE_KEY,
    Authorization: `Bearer ${session.access_token}`,
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
    response = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch (error) {
    if (!queueOffline || method === "GET" || isAuthPath || !requestUserID || !isNetworkFailure(error)) throw error;
    const table = tableOrPath.replace(/^\/rest\/v1\//, "");
    const operation = { table, method, query, body, prefer };
    persistOfflineOperation(operation, requestUserID);
    return method === "POST" && prefer?.includes("return=representation")
      ? (Array.isArray(body) ? body : [body]) : null;
  }
  if (!isAuthPath && state.user?.id !== requestUserID) throw new Error("账号已切换，请重新加载当前账号资料。");
  const text = await response.text();
  const payload = text ? (() => { try { return JSON.parse(text); } catch { return text; } })() : null;
  if (!response.ok) throw new Error(friendlyError(typeof payload === "object" && payload ? payload : { message: text }));
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

async function patch(table, filters, body) {
  return request(table, { method: "PATCH", query: filters, body, prefer: "return=minimal" });
}

async function loadData() {
  const userID = state.user?.id;
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
    if (state.user?.id !== userID) return;
    snapshot = { customers, contacts, addresses, trips, agencies, settings, stops, expenses };
    const queued = readOfflineQueue().operations;
    for (const operation of queued) applyQueuedOperation(snapshot, operation);
    writeOfflineCache(snapshot);
    restoreQueuedStorageImages(snapshot, queued, state.user.id);
    state.offline = false;
  } catch (error) {
    if (state.user?.id !== userID) return;
    const cached = isNetworkFailure(error) ? readOfflineCache() : null;
    if (!cached) throw error;
    snapshot = cached;
    const queued = readOfflineQueue().operations;
    for (const operation of queued) applyQueuedOperation(snapshot, operation);
    writeOfflineCache(snapshot);
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
      if (state.user?.id !== userID) return;
    }
    catch (error) {
      if (state.user?.id !== userID) return;
      if (!isNetworkFailure(error)) throw error;
      state.offline = true;
    }
  }
  if (migrateCardImages) {
    await saveBusinessCard(true);
    if (state.user?.id !== userID) return;
  }
  if (migratePaymentImages) {
    await savePaymentMethods(true);
    if (state.user?.id !== userID) return;
  }
  state.stops = snapshot.stops || [];
  state.expenses = snapshot.expenses || [];
  state.trips = (snapshot.trips || []).filter(row => !row.deleted_at).map(trip => ({
    ...trip,
    stops: state.stops.filter(stop => stop.trip_id === trip.id && !stop.deleted_at).sort((a, b) => a.position - b.position),
    expenses: state.expenses.filter(expense => expense.trip_id === trip.id && !expense.deleted_at).sort((a, b) => a.position - b.position),
  }));
  scheduleWebReminders();
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

function renderLogin() {
  document.getElementById("app").innerHTML = `
    <main class="login-screen">
      <section class="login-brand">
        <div class="brand-lockup"><span class="brand-mark">云</span><span>云盛行程管家</span></div>
        <div class="brand-copy"><h1>每一段行程，<br>都安排妥当。</h1><p>客户资料、行程安排与结算信息，在手机和浏览器之间保持同步。</p></div>
        <div class="brand-foot">安全登录后，访问你的云端业务数据。</div>
      </section>
      <section class="login-panel"><form id="loginForm" class="login-card">
        <h2>欢迎回来</h2><p>使用行程管家云端账号登录</p>
        ${state.error ? `<div class="error">${escapeHTML(state.error)}</div>` : ""}
        <div class="field"><label for="email">邮箱</label><input id="email" name="email" type="email" autocomplete="username" required placeholder="name@example.com"></div>
        <div class="field"><label for="password">密码</label><input id="password" name="password" type="password" autocomplete="current-password" required placeholder="请输入密码"></div>
        <button class="button primary full" type="submit" ${state.busy ? "disabled" : ""}>${state.busy ? "正在登录…" : "登录"}</button>
      </form></section>
    </main>`;
}

const navItems = [
  ["home", "⌂", "总览"], ["trips", "▤", "行程"], ["customers", "♙", "客户"],
  ["businessCard", "▤", "名片"], ["agencies", "▦", "旅行社"], ["wallet", "▣", "钱包"], ["settings", "⚙", "设置"],
];

function renderApp() {
  const [title, subtitle] = pageNames[state.page];
  document.getElementById("app").innerHTML = `
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand-lockup"><span class="brand-mark">云</span><span>云盛行程管家</span></div>
        <div class="nav-label">工作台</div>
        <nav class="nav-list">${navItems.map(([key, icon, label]) => `<button class="nav-item ${state.page === key ? "active" : ""}" data-action="navigate" data-page="${key}"><span class="nav-icon">${icon}</span><span>${label}</span></button>`).join("")}</nav>
        <div class="sidebar-bottom"><span class="avatar">${escapeHTML((state.user?.user_metadata?.salutation || state.user?.email || "云").slice(0, 1))}</span><span class="user-copy"><strong>${escapeHTML(state.user?.user_metadata?.salutation || "已登录")}</strong><small>${escapeHTML(state.user?.email || "")}</small></span></div>
      </aside>
      <main class="main">
        <header class="topbar"><div><h1>${title}</h1><p>${subtitle}</p></div><div class="top-actions"><span class="connection">云端已连接</span><button class="button quiet small" data-action="refresh-data">↻ 刷新</button><button class="button quiet small" data-action="signout">退出登录</button></div></header>
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
    .sort((a, b) => new Date(a.appointment_date) - new Date(b.appointment_date) || timeOnly(a.appointment_time).localeCompare(timeOnly(b.appointment_time)));
}

function tripMatchesSearch(trip) {
  const query = state.search.trim().toLocaleLowerCase();
  if (!query) return true;
  return [trip.customer_name, trip.customer_contact, trip.service_type, trip.location_start,
    ...(trip.stops || []).map(stop => stop.address), trip.location_end, trip.flight_info,
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
  return `<section class="trip-calendar"><div class="calendar-heading"><button class="button quiet small" data-action="calendar-month" data-step="-1" aria-label="上个月">‹</button><strong>${year}年${monthNumber + 1}月</strong><button class="button quiet small" data-action="calendar-month" data-step="1" aria-label="下个月">›</button></div><div class="calendar-grid calendar-weekdays">${["一", "二", "三", "四", "五", "六", "日"].map(day => `<span>${day}</span>`).join("")}</div><div class="calendar-grid">${cells.join("")}</div></section>`;
}

function statCard(icon, label, value, note) {
  return `<article class="stat-card"><div class="stat-top"><span>${label}</span><span class="stat-icon">${icon}</span></div><div class="stat-value">${value}</div><div class="stat-note">${note}</div></article>`;
}

function renderHome() {
  const upcoming = upcomingTrips();
  const monthStart = new Date(); monthStart.setDate(1); monthStart.setHours(0, 0, 0, 0);
  const monthTrips = state.trips.filter(trip => !trip.is_cancelled && new Date(trip.appointment_date) >= monthStart);
  const monthNet = monthTrips.reduce((sum, trip) => sum + netIncome(trip), 0);
  const unpaid = state.trips.filter(trip => !trip.is_paid && !trip.is_cancelled).reduce((sum, trip) => sum + Number(trip.price || 0) + Number(trip.tip || 0), 0);
  const visible = upcoming.filter(trip => (!state.homeDate || dateInput(trip.appointment_date) === state.homeDate) && tripMatchesSearch(trip));
  const dates = tripDates(upcoming);
  return `<div class="stats-grid">
      ${statCard("✦", "待执行行程", upcoming.length, "从今天开始的待执行安排")}
      ${statCard("♙", "客户", state.customers.length, "已保存的客户资料")}
      ${statCard("↗", "本月净收入", currency(monthNet), "车费、小费及费用调整")}
      ${statCard("◷", "未收款", currency(unpaid), "尚未结清的行程款项")}
    </div>
    <section class="trip-dashboard home-trip-dashboard">
      ${renderDateStrip(dates, state.homeDate, upcoming, upcoming.length, !state.homeDate)}
      <div class="page-tools trip-search-tools"><label class="search-wrap"><span>⌕</span><input class="search-input" data-search="home" value="${escapeHTML(state.search)}" placeholder="搜索客户、地点、航班"></label><button class="button primary" data-action="new-trip">＋ 新增行程</button></div>
      <div class="section-heading"><h2>待执行行程</h2><small>${visible.length}</small></div>
      ${visible.length ? `<div class="trip-list">${visible.map(renderTripCard).join("")}</div>` : emptyState(state.search ? "没有找到行程" : "目前没有待执行行程", state.search ? "请更换搜索内容。" : "新增行程后会显示在这里。", "trip")}
    </section>`;
}

function filteredTrips() {
  const today = dateInput(new Date());
  return state.trips.filter(trip => {
    if (state.tripFilter === "pending" && (trip.is_completed || trip.is_cancelled)) return false;
    if (state.tripFilter === "unpaid" && trip.is_paid) return false;
    if (state.tripFilter === "history" && dateInput(trip.appointment_date) >= today) return false;
    if (state.tripDate && dateInput(trip.appointment_date) !== state.tripDate) return false;
    return tripMatchesSearch(trip);
  }).sort((a, b) => new Date(a.appointment_date) - new Date(b.appointment_date) || timeOnly(a.appointment_time).localeCompare(timeOnly(b.appointment_time)));
}

function renderTrips() {
  const trips = filteredTrips();
  const filters = [["all", "全部"], ["pending", "待执行"], ["unpaid", "未收款"], ["history", "历史"]];
  const dates = tripDates(state.trips);
  const statuses = `<div class="tabs">${filters.map(([key, label]) => `<button class="tab ${state.tripFilter === key ? "active" : ""}" data-action="trip-filter" data-filter="${key}">${label}</button>`).join("")}</div>`;
  return `<section class="trip-dashboard">
    <div class="trip-mode-switch"><button class="${state.tripDateMode === "seven" ? "active" : ""}" data-action="trip-date-mode" data-mode="seven">周</button><button class="${state.tripDateMode === "month" ? "active" : ""}" data-action="trip-date-mode" data-mode="month">月历</button></div>
    ${state.tripDateMode === "seven" ? renderDateStrip(dates, state.tripDate, state.trips, state.trips.length, !state.tripDate) : renderMonthCalendar(state.trips)}
    <div class="page-tools trip-search-tools"><label class="search-wrap"><span>⌕</span><input class="search-input" data-search="trips" value="${escapeHTML(state.search)}" placeholder="搜索客户、地点、航班"></label><button class="button primary" data-action="new-trip">＋ 新增行程</button></div>
    ${statuses}
    <div class="section-heading"><h2>${filters.find(([key]) => key === state.tripFilter)?.[1]}行程</h2><small>${trips.length} 条</small></div>
    ${trips.length ? `<div class="trip-list">${trips.map(renderTripCard).join("")}</div>` : emptyState("没有符合条件的行程", "可以调整搜索内容，或新增行程。", "trip")}</section>`;
}

function renderTripCard(trip) {
  const isPending = !trip.is_completed && !trip.is_cancelled;
  const tripStops = (trip.stops || []).map(stop => stop.address).filter(Boolean);
  const expanded = state.expandedFlights.has(trip.id);
  const moneyRows = (trip.expenses || []).map(item => `<span>${escapeHTML(item.title)} ${item.is_addition ? "+" : "−"}${currency(item.amount)}</span>`).join("");
  return `<article class="trip-card trip-card-full" data-action="view-trip" data-id="${trip.id}">
    <div class="trip-time"><strong>${timeOnly(trip.appointment_time)}</strong><small>${dateOnly(trip.appointment_date)}</small></div>
    <div class="trip-main">
      <div class="trip-heading"><div class="trip-title"><strong>${escapeHTML(trip.customer_name || "未填写客户")}</strong><span class="trip-service">✈ ${escapeHTML(trip.service_type || "行程")}</span></div><strong class="trip-price">${currency(trip.price)}</strong></div>
      <div class="trip-facts"><span>♙ ${escapeHTML(trip.customer_count || "1")} 位乘客</span><span>▣ ${escapeHTML(trip.customer_stuff || "0")} 件行李</span>${trip.order_source ? `<span>订单：${escapeHTML(trip.order_source)}</span>` : ""}${trip.customer_contact ? `<span>联系：${escapeHTML(trip.customer_contact)}</span>` : ""}</div>
      <div class="trip-route trip-route-full"><div class="route-point start"><span class="route-icon">⌖</span><span class="trip-route-label">起始点</span><span class="trip-route-value">${escapeHTML(trip.location_start || "—")}</span></div>
        ${tripStops.map((stop, index) => `<div class="route-point stop"><span class="route-icon">⋯</span><span class="trip-route-label">停靠点 ${index + 1}</span><span class="trip-route-value">${escapeHTML(stop)}</span></div>`).join("")}
        <div class="route-point end"><span class="route-icon">⚑</span><span class="trip-route-label">目的地</span><span class="trip-route-value">${escapeHTML(trip.location_end || "—")}</span></div></div>
      ${trip.flight_info ? `<section class="trip-flight"><button class="flight-summary" data-action="flight-toggle" data-id="${trip.id}"><span class="flight-plane">✈</span><strong>${escapeHTML(trip.flight_info)}</strong><small>${dateOnly(trip.flight_date || trip.appointment_date)}</small>${trip.flight_departure_time ? `<span>${escapeHTML(timeDisplay(trip.flight_departure_time))}</span>` : ""}<b>航班</b><span class="flight-chevron">${expanded ? "⌃" : "⌄"}</span></button>${expanded ? `<div class="flight-details"><div><small>起飞时间</small><strong>${escapeHTML(timeDisplay(trip.flight_departure_time))}</strong></div><div><small>预计到达</small><strong>${escapeHTML(timeDisplay(trip.flight_estimated_arrival_time))}</strong></div><div><small>到达航站楼</small><strong>${escapeHTML(trip.flight_arrival_terminal || "—")}</strong></div><div><small>行李转盘</small><strong>${escapeHTML(trip.flight_baggage_carousel || "—")}</strong></div></div>` : ""}</section>` : ""}
      ${trip.memo ? `<p class="trip-memo">${escapeHTML(trip.memo)}</p>` : ""}
      <div class="trip-status-row">${tripStatus(trip)} ${paymentStatus(trip)}</div>
      <div class="trip-money-summary"><span><small>行程费用</small><strong>${currency(trip.price)}</strong></span><span><small>小费</small><strong>${currency(trip.tip)}</strong></span><span><small>净收入</small><strong class="trip-net">${currency(netIncome(trip))}</strong></span></div>
      ${moneyRows ? `<div class="trip-expense-summary">${moneyRows}</div>` : ""}
      <div class="trip-actions">${isPending ? `<button class="button small" data-action="edit-trip" data-id="${trip.id}">编辑</button><button class="button small complete-action" data-action="toggle-complete" data-id="${trip.id}">已完成</button><button class="button small danger" data-action="cancel-trip" data-id="${trip.id}">取消行程</button><button class="button small danger" data-action="delete-trip" data-id="${trip.id}">删除</button>` : trip.is_cancelled ? `<button class="button small" data-action="restore-trip" data-id="${trip.id}">恢复行程</button>` : ""}${!trip.is_paid ? `<button class="button small settle-action" data-action="toggle-paid" data-id="${trip.id}">财务结算</button>` : ""}</div>
    </div>
  </article>`;
}

function emptyState(title, detail, action) {
  const actionMarkup = action === "trip" ? `<button class="button primary" data-action="new-trip">＋ 新增行程</button>` : "";
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
    '<section class="form-section customer-trip-history"><div class="form-section-title"><div><h3>出行记录</h3><p>' + related.length + ' 次出行 · 总收入 ' + currency(customerStats(customer).income) + ' · 未收款 ' + currency(customerStats(customer).unpaid) + '</p></div></div><div class="customer-history-list">' + tripHTML + '</div></section>' +
    remark + '<div class="detail-actions"><button class="button small danger" data-action="delete-customer" data-id="' + customer.id + '">删除</button><button class="button small primary" data-action="edit-customer" data-id="' + customer.id + '">编辑资料</button></div>', "editor-modal detail-modal");
}

function openTripDetail(trip) {
  const pending = !trip.is_completed && !trip.is_cancelled;
  const tripRows = (trip.stops || []).map((stop, index) => '<div><small>停靠点 ' + (index + 1) + '</small><strong>' + escapeHTML(stop.address) + '</strong></div>').join("");
  const fields = '<div class="detail-grid"><div><small>客户</small><strong>' + escapeHTML(trip.customer_name || "—") + '</strong></div><div><small>联系方式</small><strong>' + escapeHTML(trip.customer_contact || "—") + '</strong></div><div><small>行程类型</small><strong>' + escapeHTML(trip.service_type || "接机") + '</strong></div><div><small>订单来源</small><strong>' + escapeHTML(trip.order_source || "普通客户") + '</strong></div><div><small>乘客人数</small><strong>' + escapeHTML(trip.customer_count || "1") + ' 位</strong></div><div><small>行李数量</small><strong>' + escapeHTML(trip.customer_stuff || "0") + ' 件</strong></div><div><small>行程状态</small><strong>' + tripStatus(trip) + '</strong></div><div><small>结算状态</small><strong>' + paymentStatus(trip) + '</strong></div><div><small>起始点</small><strong>' + escapeHTML(trip.location_start || "—") + '</strong></div>' + tripRows + '<div><small>目的地</small><strong>' + escapeHTML(trip.location_end || "—") + '</strong></div></div>';
  const flight = trip.flight_info ? '<section class="form-section"><div class="form-section-title"><div><h3>航班信息</h3></div></div><div class="detail-grid"><div><small>航班号</small><strong>' + escapeHTML(trip.flight_info) + '</strong></div><div><small>起飞日期</small><strong>' + dateOnly(trip.flight_date || trip.appointment_date) + '</strong></div><div><small>起飞时间</small><strong>' + escapeHTML(timeDisplay(trip.flight_departure_time)) + '</strong></div><div><small>预计到达时间</small><strong>' + escapeHTML(timeDisplay(trip.flight_estimated_arrival_time)) + '</strong></div><div><small>到达航站楼</small><strong>' + escapeHTML(trip.flight_arrival_terminal || "—") + '</strong></div><div><small>行李转盘</small><strong>' + escapeHTML(trip.flight_baggage_carousel || "—") + '</strong></div></div></section>' : "";
  const expenses = (trip.expenses || []).map(item => '<div class="finance-row"><span>' + escapeHTML(item.title) + (item.is_addition ? ' ＋' : ' −') + '</span><strong>' + currency(item.amount) + '</strong></div>').join("");
  const actions = '<button class="button small" data-action="copy-trip" data-id="' + trip.id + '">复制行程</button>' + (pending ? '<button class="button small" data-action="edit-trip" data-id="' + trip.id + '">编辑</button><button class="button small complete-action" data-action="toggle-complete" data-id="' + trip.id + '">已完成</button><button class="button small danger" data-action="cancel-trip" data-id="' + trip.id + '">取消行程</button><button class="button small danger" data-action="delete-trip" data-id="' + trip.id + '">删除</button>' : trip.is_cancelled ? '<button class="button small" data-action="restore-trip" data-id="' + trip.id + '">恢复行程</button>' : '') + (!trip.is_paid ? '<button class="button small settle-action" data-action="toggle-paid" data-id="' + trip.id + '">财务结算</button>' : "");
  showModal("行程详情", '<div class="detail-summary"><div><strong>' + escapeHTML(trip.customer_name || "未填写客户") + '</strong><small>' + dateOnly(trip.appointment_date) + ' · ' + timeOnly(trip.appointment_time) + ' · ' + escapeHTML(trip.service_type || "接机") + '</small></div><strong>' + currency(trip.price) + '</strong></div>' +
    formSection("行程信息", "", fields) + flight +
    formSection("财务结算", "", '<div class="detail-grid"><div><small>行程费用</small><strong>' + currency(trip.price) + '</strong></div><div><small>小费</small><strong>' + currency(trip.tip) + '</strong></div><div><small>净收入</small><strong>' + currency(netIncome(trip)) + '</strong></div></div>' + expenses) +
    (trip.memo ? '<p class="trip-memo">' + escapeHTML(trip.memo) + '</p>' : '') + '<div class="detail-actions">' + actions + '</div>', "editor-modal detail-modal");
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
    ${agencies.length ? `<div class="agency-grid">${agencies.map(agency => `<article class="agency-card"><div class="customer-id"><div class="customer-initial">▦</div><div class="customer-info"><strong>${escapeHTML(agency.name)}</strong><small>代码：${escapeHTML(agency.agency_code)}<br>${escapeHTML(agency.contact_person || "暂无联系人")} ${escapeHTML(agency.phone || "")}</small></div></div><div class="trip-meta"><button class="button small" data-action="edit-agency" data-id="${agency.id}">编辑</button><button class="button small danger" data-action="delete-agency" data-id="${agency.id}">删除</button></div></article>`).join("")}</div>` : emptyState("还没有合作旅行社", "新增旅行社资料后可以在行程中选择。", "agency")}`;
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
  const categories = new Map();
  const addCategory = (key, name, amount, expense) => { if (amount > 0) categories.set(key, { name, amount: (categories.get(key)?.amount || 0) + amount, expense }); };
  for (const trip of selected) {
    addCategory("__fare", "行程费用", Number(trip.price || 0), false);
    addCategory("__tip", "小费", Number(trip.tip || 0), false);
    for (const item of trip.expenses || []) addCategory(`${item.is_addition ? "income" : "expense"}|${item.title || "其他"}`, item.title || "其他", Math.abs(Number(item.amount || 0)), !item.is_addition);
  }
  const rows = [...categories.values()].sort((a, b) => Number(a.expense) - Number(b.expense) || b.amount - a.amount);
  const totalVolume = rows.reduce((sum, row) => sum + row.amount, 0);
  const income = rows.filter(row => !row.expense).reduce((sum, row) => sum + row.amount, 0);
  const expenses = rows.filter(row => row.expense).reduce((sum, row) => sum + row.amount, 0);
  const net = income - expenses;
  const colors = ["#4f7df5", "#2ebaa0", "#faa842", "#a86be8", "#f26378", "#40b0d6", "#c29945"];
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
      : `<circle cx="100" cy="100" r="80" fill="none" stroke="${depth ? "#a57b5c" : "#ded1c1"}" stroke-opacity="${depth ? 0.78 : 0.94}" stroke-width="24"/>`;
    return `<svg class="wallet-chart-svg" viewBox="0 0 200 200" aria-hidden="true"><g transform="rotate(-90 100 100)">${ring}</g></svg>`;
  };
  const dateTitle = period === "week" ? `${start.getFullYear()} 年\n${start.getMonth() + 1}/${start.getDate()} – ${new Date(end.getTime() - 86400000).getMonth() + 1}/${new Date(end.getTime() - 86400000).getDate()}` : period === "day" ? `${start.getFullYear()}年${start.getMonth() + 1}月${start.getDate()}日` : period === "month" ? `${start.getFullYear()}年${start.getMonth() + 1}月` : `${start.getFullYear()}年`;
  const periods = [["day", "天"], ["week", "本周"], ["month", "本月"], ["year", "年"]];
  return `<div class="tabs">${periods.map(([key, label]) => `<button class="tab ${period === key ? "active" : ""}" data-action="wallet-period" data-period="${key}">${label}</button>`).join("")}</div>
    <div class="wallet-date-navigator"><button class="button" data-action="wallet-shift" data-step="-1" aria-label="上一段日期">‹</button><strong>${escapeHTML(dateTitle).replace("\n", "<br>")}</strong><button class="button" data-action="wallet-shift" data-step="1" aria-label="下一段日期">›</button></div>
    <div class="wallet-layout"><section class="wallet-total"><small>净收入</small><strong>${currency(net)}</strong><small>${selected.length} 条行程 · 收入 ${currency(income)} · 支出 ${currency(expenses)}</small></section><section class="panel wallet-chart-panel"><div class="wallet-chart-shell"><div class="wallet-chart-depth-back">${chartLayer(true)}</div><div class="wallet-chart-depth">${chartLayer(true)}</div><div class="wallet-chart">${chartLayer()}<div class="wallet-chart-center"><small>总收入</small><strong>${currency(income)}</strong><span class="wallet-chart-divider"></span><small>净收入</small><strong class="wallet-net-value">${currency(net)}</strong></div></div></div><div class="finance-list">${rows.map((row, index) => `<div class="finance-row"><span><i style="--category-color:${colors[index % colors.length]}"></i>${escapeHTML(row.name)}${row.expense ? " · 支出" : " · 收入"}</span><strong>${currency(row.amount)}</strong><small>${totalVolume ? `${Math.round(row.amount / totalVolume * 100)}%` : "0%"}</small></div>`).join("") || `<div class="finance-row"><span>暂无收支记录</span><strong>${currency(0)}</strong><small>0%</small></div>`}</div></section></div>
    ${renderPaymentMethods()}`;
}

function imageDataURL(base64) { return base64 ? `data:image/jpeg;base64,${base64}` : ""; }
async function storageRequest(path, { method = "GET", body, contentType, queueOffline = true } = {}) {
  const requestUserID = state.user?.id;
  const session = await currentSession();
  if (!session) throw new Error("云端登录状态已失效，请重新登录。");
  if (!requestUserID || state.user?.id !== requestUserID || session.user?.id !== requestUserID) {
    throw new Error("账号已切换，请重新加载当前账号资料。");
  }
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
  let response;
  try {
    response = await fetch(`${SUPABASE_URL}/storage/v1/${path}`, {
      method,
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${session.access_token}`,
        ...(contentType ? { "Content-Type": contentType } : {}),
        ...(method === "POST" ? { "x-upsert": "true" } : {}),
      },
      body,
    });
  } catch (error) {
    if (!queueOffline || method !== "POST" || !isNetworkFailure(error)) throw error;
    await queueUpload();
    return { ok: true, queued: true };
  }
  if (state.user?.id !== requestUserID) throw new Error("账号已切换，请重新加载当前账号资料。");
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || payload.error || "云端图片存储失败，请确认已应用 Storage 配置。");
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
async function uploadAssetImage(base64, path) {
  const jpeg = await imageAsJpeg(base64);
  await storageRequest(`object/account-assets/${objectPath(path)}`, { method: "POST", body: jpeg, contentType: "image/jpeg" });
}
async function hydrateAccountAssets() {
  const getBase64 = async path => {
    const response = await storageRequest(`object/authenticated/account-assets/${objectPath(path)}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
    return btoa(binary);
  };
  const card = state.businessCard;
  if (card.portraitPath && !card.portraitData) card.portraitData = await getBase64(card.portraitPath);
  for (const qr of card.qrCodes) if (qr.imagePath && !qr.imageData) qr.imageData = await getBase64(qr.imagePath);
  for (const method of state.paymentMethods) if (method.qrImagePath && !method.qrImageData) method.qrImageData = await getBase64(method.qrImagePath);
}
function renderPaymentMethods() {
  return `<section class="panel account-asset-panel"><div class="section-heading"><h2>收款方式</h2><button class="button small" data-action="add-payment-method">＋ 添加</button></div>${state.paymentMethods.length ? `<div class="asset-list">${state.paymentMethods.map(method => `<article class="asset-row"><button class="asset-image-button" data-action="preview-payment-qr" data-id="${escapeHTML(method.id)}" ${method.qrImageData ? "" : "disabled"}>${method.qrImageData ? `<img src="${imageDataURL(method.qrImageData)}" alt="${escapeHTML(method.name || "收款二维码")}">` : `<span>添加二维码</span>`}</button><div class="asset-row-content"><label>收款方式名称<input data-payment-name="${escapeHTML(method.id)}" value="${escapeHTML(method.name || "")}" placeholder="例如：Zelle"></label><label class="button small asset-upload">${method.qrImageData ? "更换二维码" : "选择二维码图片"}<input type="file" accept="image/*" data-payment-image="${escapeHTML(method.id)}"></label></div><button class="button small danger" data-action="remove-payment-method" data-id="${escapeHTML(method.id)}" aria-label="删除收款方式">删除</button></article>`).join("")}</div>` : `<p class="empty-hint">添加收款方式名称和二维码，方便向客户展示。</p>`}</section>`;
}

function renderBusinessCard() {
  const card = state.businessCard;
  const metadata = state.user?.user_metadata || {};
  const name = metadata.salutation || "未填写";
  const phone = metadata.phone || "未填写";
  const email = state.user?.email || "未填写";
  const portrait = card.portraitData ? `<img src="${imageDataURL(card.portraitData)}" alt="名片头像">` : `<span>人像</span>`;
  const styleName = Number(card.style) === 1 ? "金属质感" : "简洁平版";
  return `<section class="business-card-editor"><div class="panel business-card-settings"><div class="business-card-photo"><label class="business-avatar-picker">${portrait}<span>更换头像<input type="file" accept="image/*" data-card-photo></span></label></div><div class="readonly-profile"><label>姓名<input readonly value="${escapeHTML(name)}"></label><label>电话<input readonly value="${escapeHTML(phone)}"></label><label>电子邮箱<input readonly value="${escapeHTML(email)}"></label></div><label class="field">昵称<input data-card-field="nickname" value="${escapeHTML(card.nickname || "")}" placeholder="输入名片上显示的昵称"></label><div class="field"><label>名片样式</label><div class="business-style-options"><button class="business-style-option ${Number(card.style) === 0 ? "selected" : ""}" data-action="card-style" data-style="0"><strong>样式一</strong><small>简洁平版</small></button><button class="business-style-option ${Number(card.style) === 1 ? "selected" : ""}" data-action="card-style" data-style="1"><strong>样式二</strong><small>金属质感</small></button></div></div><button class="button primary" data-action="save-business-card">保存名片</button></div><div class="business-card-preview ${Number(card.style) === 1 ? "metallic" : "flat"}"><div class="preview-heading">${card.portraitData ? `<img src="${imageDataURL(card.portraitData)}" alt="">` : `<span>${escapeHTML(String(name).slice(0, 1))}</span>`}<div><strong>${escapeHTML(card.nickname || name)}</strong><small>${escapeHTML(name)}</small></div></div><div class="preview-contact"><span>${escapeHTML(phone)}</span><span>${escapeHTML(email)}</span></div><small>${styleName}</small></div></section><section class="panel account-asset-panel"><div class="section-heading"><h2>二维码</h2><button class="button small" data-action="add-card-qr">＋ 添加</button></div>${card.qrCodes.length ? `<div class="asset-list">${card.qrCodes.map(qr => `<article class="asset-row"><button class="asset-image-button" data-action="preview-card-qr" data-id="${escapeHTML(qr.id)}" ${qr.imageData ? "" : "disabled"}>${qr.imageData ? `<img src="${imageDataURL(qr.imageData)}" alt="${escapeHTML(qr.name || "二维码")}">` : `<span>添加二维码</span>`}</button><div class="asset-row-content"><label>二维码名称<input data-card-qr-name="${escapeHTML(qr.id)}" value="${escapeHTML(qr.name || "")}" placeholder="例如：微信"></label><label class="button small asset-upload">${qr.imageData ? "更换二维码" : "选择二维码图片"}<input type="file" accept="image/*" data-card-qr-image="${escapeHTML(qr.id)}"></label></div><button class="button small danger" data-action="remove-card-qr" data-id="${escapeHTML(qr.id)}">删除</button></article>`).join("")}</div>` : `<p class="empty-hint">添加微信、LINE 或其他联系二维码。</p>`}</section>`;
}

async function cloudAssetValue(column, value, ownerID) {
  const cloudValue = structuredClone(value);
  const saveImage = async (item, dataKey, pathKey, path) => {
    if (!item[dataKey]) return;
    const objectName = item[pathKey] || `${ownerID}/${path}`;
    await uploadAssetImage(item[dataKey], objectName);
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
async function persistAccountAsset(column, value) {
  const ownerID = state.user?.id;
  if (!ownerID) throw new Error("请先登录云端账号。");
  const updatedAt = new Date().toISOString();
  const cloudValue = await cloudAssetValue(column, value, ownerID);
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
  const row = { ...(state.settings || defaultSettings()), owner_id: ownerID, [column]: cloudValue, [`${column}_updated_at`]: updatedAt, updated_at: updatedAt };
  await upsert("user_settings", row, "owner_id");
  if (state.user?.id !== ownerID) throw new Error("账号已切换，请重新加载当前账号资料。");
  state.settings = row;
}

async function saveBusinessCard(silent = false) {
  await persistAccountAsset("business_card_data", state.businessCard);
  if (!silent) showToast("名片已保存并同步到云端。");
}

async function savePaymentMethods(silent = false) {
  await persistAccountAsset("wallet_payment_methods", { methods: state.paymentMethods });
  if (!silent) showToast("收款方式已保存并同步到云端。");
}

async function readImageBase64(file) {
  if (!file.type.startsWith("image/")) throw new Error("请选择图片文件。");
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  return btoa(binary);
}

async function setCardPhoto(file) {
  try {
    state.businessCard.portraitData = await readImageBase64(file);
    await saveBusinessCard(); updatePageContent();
  } catch (error) { showToast(error.message || "头像保存失败。", true); }
}

async function setQRImage(kind, id, file) {
  try {
    const imageData = await readImageBase64(file);
    if (kind === "card") {
      const qr = state.businessCard.qrCodes.find(item => item.id === id);
      if (!qr) return;
      qr.imageData = imageData;
      await saveBusinessCard();
    } else {
      const method = state.paymentMethods.find(item => item.id === id);
      if (!method) return;
      method.qrImageData = imageData;
      await savePaymentMethods();
    }
    updatePageContent();
  } catch (error) { showToast(error.message || "二维码保存失败。", true); }
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

function renderSettings() {
  const settings = state.settings || defaultSettings();
  const countries = [["US", "美国", "美元", "US Dollar", "USD", "$"], ["CA", "加拿大", "加拿大元", "Canadian Dollar", "CAD", "CA$"], ["CN", "中国", "人民币", "Chinese Yuan", "CNY", "¥"], ["GB", "英国", "英镑", "British Pound", "GBP", "£"], ["JP", "日本", "日元", "Japanese Yen", "JPY", "¥"], ["KR", "韩国", "韩元", "South Korean Won", "KRW", "₩"], ["ES", "西班牙", "欧元", "Euro", "EUR", "€"], ["FR", "法国", "欧元", "Euro", "EUR", "€"], ["DE", "德国", "欧元", "Euro", "EUR", "€"], ["AU", "澳大利亚", "澳元", "Australian Dollar", "AUD", "A$"], ["HK", "中国香港", "港元", "Hong Kong Dollar", "HKD", "HK$"], ["TW", "中国台湾", "新台币", "New Taiwan Dollar", "TWD", "NT$"], ["SG", "新加坡", "新加坡元", "Singapore Dollar", "SGD", "S$"], ["MX", "墨西哥", "墨西哥比索", "Mexican Peso", "MXN", "MX$"], ["IN", "印度", "印度卢比", "Indian Rupee", "INR", "₹"], ["CH", "瑞士", "瑞士法郎", "Swiss Franc", "CHF", "CHF"]];
  const configuredNavigation = state.settings?.navigation_provider;
  const navigation = getAccountPreference("navigation") || (configuredNavigation === "apple_maps" ? "appleMaps" : configuredNavigation || "appleMaps");
  const flightKey = getAccountPreference("variflight-key");
  const selectedCurrency = countries.find(([code]) => code === settings.currency_country_code) || countries[0];
  const languageCode = normalizedLanguageCode(settings.language_code);
  return `<section class="panel" style="max-width:760px"><div class="section-heading" style="margin-top:0"><h2>账户偏好</h2></div><form id="settingsForm"><div class="form-grid"><div class="field"><label for="language">语言偏好</label><select id="language" name="language_code"><option value="zh-Hans" ${languageCode === "zh-Hans" ? "selected" : ""}>简体中文</option><option value="zh-Hant" ${languageCode === "zh-Hant" ? "selected" : ""}>繁體中文</option><option value="en" ${languageCode === "en" ? "selected" : ""}>English</option><option value="ja" ${languageCode === "ja" ? "selected" : ""}>日本語</option><option value="ko" ${languageCode === "ko" ? "selected" : ""}>한국어</option><option value="es" ${languageCode === "es" ? "selected" : ""}>Español</option></select><small>偏好保存至云端；Web 界面目前使用简体中文。</small></div><div class="field"><label for="currency">国家和地区 · 本位币</label><select id="currency" name="currency_country_code">${countries.map(([code, country, currencyName, currencyEnglish, currencyCode, symbol]) => `<option value="${code}" ${settings.currency_country_code === code ? "selected" : ""}>${country} · ${symbol} ${currencyName} (${currencyCode})</option>`).join("")}</select><small>${escapeHTML(selectedCurrency[3])} · ${escapeHTML(selectedCurrency[4])}</small></div><div class="field"><label for="navigation_provider">默认导航</label><select id="navigation_provider" name="navigation_provider"><option value="appleMaps" ${navigation === "appleMaps" ? "selected" : ""}>Apple 地图</option><option value="googleMaps" ${navigation === "googleMaps" ? "selected" : ""}>Google Maps</option></select></div><div class="field"><label for="variflight_key">飞友 API 密钥</label><input id="variflight_key" name="variflight_key" type="password" autocomplete="off" value="${escapeHTML(flightKey)}" placeholder="粘贴你的飞友 API 密钥"><small>仅保存在此浏览器，不会同步到云端。</small></div></div><button class="button primary" type="submit">保存设置</button></form></section>
    <section class="panel expense-catalog-panel" style="max-width:760px;margin-top:14px"><div class="section-heading" style="margin-top:0"><div><h2>费用项目</h2><p>这些名称会用于财务结算选择。默认包含居间费和高速通行费。</p></div><button class="button small" data-action="add-expense-name">＋ 添加项目</button></div><div class="expense-name-list">${expenseCatalog().map(name => `<div class="expense-name-row"><input data-expense-name value="${escapeHTML(name)}"><button class="button small danger" data-action="remove-expense-name">−</button></div>`).join("")}</div><button class="button primary" data-action="save-expense-catalog" style="margin-top:12px">保存费用项目</button></section>
    <section class="panel" style="max-width:760px;margin-top:14px"><div class="section-heading" style="margin-top:0"><h2>云端账户</h2></div><div class="customer-info"><strong>${escapeHTML(state.user?.email || "")}</strong><small>使用同一云端账号与 iPhone 应用同步。</small></div></section>`;
}

function showModal(title, content, className = "") {
  document.getElementById("modal-root")?.remove();
  const customerActions = className.includes("customer-editor-modal")
    ? `<button class="button quiet small" data-action="close-modal">取消</button><h2>${title}</h2><button class="button primary small" type="submit" form="customerForm">${title === "新增客户" ? "保存" : "保存修改"}</button>`
    : `<h2>${title}</h2><button class="button quiet small" data-action="close-modal" aria-label="关闭">✕</button>`;
  document.body.insertAdjacentHTML("beforeend", `<div id="modal-root" class="modal-backdrop"><section class="modal ${className}"><header class="modal-head">${customerActions}</header>${content}</section></div>`);
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

function formSection(title, subtitle, fields) {
  return `<section class="form-section"><div class="form-section-title"><div><h3>${title}</h3><p>${subtitle}</p></div></div><div class="form-grid">${fields}</div></section>`;
}

function serviceTypePicker(value = "接机") {
  const services = [["接机", "✈"], ["送机", "↗"], ["接送", "↔"], ["包车", "◷"], ["转机", "⇄"], ["其它", "•••"]];
  const selectedValue = value === "其他" ? "其它" : value;
  return `<fieldset class="field span-2 service-type-field"><legend>行程类型</legend><div class="service-type-picker">${services.map(([name, icon]) => `<label class="service-type-option ${name === selectedValue ? "selected" : ""}"><input type="radio" name="service_type" value="${name}" ${name === selectedValue ? "checked" : ""} required><span class="service-type-icon">${icon}</span><span>${name}</span><span class="service-type-check">✓</span></label>`).join("")}</div></fieldset>`;
}

function orderSourcePicker(value = "普通客户", code = "", name = "") {
  const agencyOrder = value === "旅行社订单";
  return `<fieldset class="field span-2 order-source-field"><legend>订单来源</legend><div class="order-source-picker">
    <label class="order-source-option ${agencyOrder ? "" : "selected"}"><input type="radio" name="order_source" value="普通客户" ${agencyOrder ? "" : "checked"}><span class="order-source-icon">♙</span><span><strong>普通客户</strong><small>熟客、散客或临时客人</small></span><span class="order-source-check">✓</span></label>
    <label class="order-source-option ${agencyOrder ? "selected" : ""}"><input type="radio" name="order_source" value="旅行社订单" ${agencyOrder ? "checked" : ""}><span class="order-source-icon">▦</span><span><strong>旅行社订单</strong><small>旅行社、地接或平台派单</small></span><span class="order-source-check">✓</span></label>
  </div><div class="agency-info-fields ${agencyOrder ? "" : "hidden"}"><div class="agency-selected-summary"><div><small>旅行社代码</small><strong data-agency-code-label>${escapeHTML(code || "尚未选择")}</strong></div><div><small>旅行社名称</small><strong data-agency-name-label>${escapeHTML(name || "点击选择旅行社")}</strong></div><button type="button" class="button small" data-action="pick-agency">选择</button></div><input type="hidden" name="travel_agency_code" value="${escapeHTML(code)}"><input type="hidden" name="travel_agency_name" value="${escapeHTML(name)}"></div>
  </fieldset>`;
}

function customerCategoryPicker(value = 1, code = "", name = "") {
  const agencyCustomer = Number(value) === 2;
  return `<fieldset class="field span-2 customer-category-field"><legend>客户类型</legend><div class="customer-category-picker"><label class="customer-category-option ${agencyCustomer ? "" : "selected"}"><input type="radio" name="category" value="1" ${agencyCustomer ? "" : "checked"}><span>普通客户</span></label><label class="customer-category-option ${agencyCustomer ? "selected" : ""}"><input type="radio" name="category" value="2" ${agencyCustomer ? "checked" : ""}><span>旅行社</span></label></div><div class="customer-agency-fields ${agencyCustomer ? "" : "hidden"}"><div class="agency-selected-summary"><div><small>旅行社代码</small><strong data-agency-code-label>${escapeHTML(code || "尚未选择")}</strong></div><div><small>旅行社名称</small><strong data-agency-name-label>${escapeHTML(name || "点击选择旅行社")}</strong></div><button type="button" class="button small" data-action="pick-agency" data-form="customerForm">选择</button></div><input type="hidden" name="travel_agency_code" value="${escapeHTML(code)}"><input type="hidden" name="travel_agency_name" value="${escapeHTML(name)}"></div></fieldset>`;
}

function addressFormField(label, name, value = "", target = name, span = true) {
  const id = `field-${name}`;
  return `<div class="field ${span ? "span-2" : ""}"><label for="${id}">${label}</label><div class="address-input-row"><input id="${id}" name="${name}" list="tripAddressSuggestions" value="${escapeHTML(value)}" placeholder="输入地址或从客户常用地址中选择"><button type="button" class="button address-pick-button" data-action="pick-address" data-target="${target}" aria-label="选择客户常用地址">⌖<span>地址</span></button><button type="button" class="button location-button" data-action="current-location" data-target="${target}" title="获取当前位置">➤</button><button type="button" class="button location-button" data-action="navigate-address" data-target="${target}" title="使用默认导航">↗</button></div></div>`;
}

function stopField(value = "", index = 0) {
  return `<div class="field span-2 stop-field"><label for="field-stop-address-${index}">停靠点 ${index + 1}</label><div class="address-input-row"><input id="field-stop-address-${index}" name="stop_address" list="tripAddressSuggestions" data-stop-input data-stop-index="${index}" value="${escapeHTML(value)}" placeholder="输入停靠地址或从客户常用地址中选择"><button type="button" class="button address-pick-button" data-action="pick-address" data-target="stop:${index}" aria-label="选择客户常用地址">⌖<span>地址</span></button><button type="button" class="button small danger stop-remove-button" data-action="remove-stop" aria-label="删除停靠点">−</button></div></div>`;
}

function flightTimeInput(value) {
  if (!value) return "";
  const match = String(value).match(/(?:^|T|\s)(\d{1,2}:\d{2})/);
  return match ? match[1].padStart(5, "0") : "";
}

function reminderDefaults(date, time) {
  const pickup = new Date(`${date}T${time || "09:00"}:00`);
  const first = new Date(pickup.getTime() - 24 * 60 * 60 * 1000);
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
  document.body.insertAdjacentHTML("beforeend", `<div id="picker-backdrop" class="modal-backdrop picker-backdrop"><section class="modal picker-modal"><header class="modal-head"><h2>${escapeHTML(title)}</h2><button class="button quiet small" data-action="close-picker">✕</button></header><div class="picker-list">${rows || `<p class="empty-hint">没有可选择的项目。</p>`}</div></section></div>`);
}

function openAddressPicker(form, target) {
  const customerID = form.elements.customer_id.value;
  const rows = addressRows(customerID).slice().sort((a, b) => Number(b.is_default) - Number(a.is_default));
  pickerOverlay("选择客户常用地址", rows.map(address => `<button type="button" class="picker-row address-picker-row" data-action="select-address" data-target="${escapeHTML(target)}" data-address="${escapeHTML(address.address || "")}"><span class="picker-row-icon">⌖</span><span class="address-picker-copy"><strong class="picker-address-main">${escapeHTML(address.address || "未填写地址")}</strong><span class="picker-address-meta"><span>${escapeHTML(address.label || "常用地址")}</span>${address.is_default ? '<span class="pill accent">默认</span>' : ""}</span></span></button>`).join(""));
}

function openAgencyPicker(formID = "tripForm") {
  pickerOverlay("选择旅行社", state.agencies.map(agency => `<button type="button" class="picker-row" data-action="select-agency" data-form="${formID}" data-code="${escapeHTML(agency.agency_code)}" data-name="${escapeHTML(agency.name)}"><span class="picker-row-icon">▦</span><span><strong>${escapeHTML(agency.name)}</strong><small>${escapeHTML(agency.agency_code)}${agency.contact_person ? ` · ${escapeHTML(agency.contact_person)}` : ""}</small></span></button>`).join(""));
}

function tripCustomerField(customerID = "", customerName = "") {
  const customer = customerByID(customerID);
  const label = customer ? customer.name : customerName || "选择或搜索客户";
  return `<div class="field span-2"><label>选择客户</label><div class="trip-customer-select"><button type="button" class="button" data-action="pick-trip-customer"><span data-trip-customer-label>${escapeHTML(label)}</span><span aria-hidden="true">⌄</span></button><button type="button" class="button quiet" data-action="clear-trip-customer">清除</button></div><input type="hidden" name="customer_id" value="${escapeHTML(customerID)}"></div>`;
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
    const picker = input.parentElement.querySelector('[data-action="pick-address"]');
    if (picker) picker.dataset.target = `stop:${index}`;
  });
}

function flattenFlightFields(value, output = {}) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    try { return flattenFlightFields(JSON.parse(trimmed), output); } catch { /* parse text response below */ }
    const patterns = {
      airline: /(?:FlightCompany|airline(?:\s*name)?|carrier)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      departure: /(?:FlightDeptimePlanDate|FlightDeptimeReadyDate|departure(?:\s*time)?|STD)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      arrival: /(?:FlightArrtimePlanDate|FlightArrtimeReadyDate|estimated\s*arrival|ETA|STA)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      departAirport: /(?:FlightDept|departureAirport|depAirport|departureStation)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      arriveAirport: /(?:FlightArr|arrivalAirport|arrAirport|arrivalStation)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      terminal: /(?:FlightArrTerminal(?:Name)?|arrivalTerminal|terminal)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
      carousel: /(?:FlightArrBaggageCarousel|baggageCarousel|carousel)["']?\s*[:：]\s*["']?([^"'\n,，;；}]+)/i,
    };
    for (const [key, pattern] of Object.entries(patterns)) output[key] ||= trimmed.match(pattern)?.[1]?.trim();
    return output;
  }
  if (Array.isArray(value)) { value.forEach(item => flattenFlightFields(item, output)); return output; }
  if (!value || typeof value !== "object") return output;
  const aliases = {
    flightcompany: "airline", airline: "airline", airlinename: "airline", carrier: "airline",
    flightdeptimeplandate: "departure", flightdeptimereadydate: "departure", departuretime: "departure", std: "departure",
    flightarrtimeplandate: "arrival", flightarrtimereadydate: "arrival", estimatedarrivaltime: "arrival", eta: "arrival", sta: "arrival",
    flightdept: "departAirport", departureairport: "departAirport", depairport: "departAirport", departurestation: "departAirport",
    flightarr: "arriveAirport", arrivalairport: "arriveAirport", arrairport: "arriveAirport", arrivalstation: "arriveAirport",
    flightarrterminal: "terminal", flightarrterminalname: "terminal", arrivalterminal: "terminal", terminal: "terminal",
    baggagecarousel: "carousel", flightarrbaggagecarousel: "carousel", carousel: "carousel",
  };
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, "");
    if (aliases[normalized] && typeof child === "string" && child.trim()) output[aliases[normalized]] ||= child.trim();
    flattenFlightFields(child, output);
  }
  return output;
}

async function lookupFlight(form) {
  const apiKey = getAccountPreference("variflight-key");
  const number = form?.elements.flight_info.value.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  const date = form?.elements.flight_date.value;
  if (!apiKey) throw new Error("请先在设置中保存飞友 API 密钥。");
  if (!number || !date) throw new Error("请填写航班号和航班起飞日期。");
  const button = form.querySelector('[data-action="lookup-flight"]');
  button.disabled = true; button.textContent = "查询中…";
  try {
    const response = await fetch("https://ai.variflight.com/servers/aviation/mcp", {
      method: "POST", headers: { "X-API-Key": apiKey, Accept: "application/json, text/event-stream", "Content-Type": "application/json", "MCP-Protocol-Version": "2025-03-26" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "searchFlightsByNumber", arguments: { fnum: number, date } } }),
    });
    const raw = await response.text();
    if (!response.ok) throw new Error(`飞友航班查询失败（HTTP ${response.status}）`);
    let payload;
    try { payload = JSON.parse(raw); } catch {
      const messages = raw.split(/\n\s*\n/).map(block => block.split("\n").filter(line => line.startsWith("data:")).map(line => line.slice(5).trim()).join("\n")).filter(Boolean);
      payload = messages.map(message => { try { return JSON.parse(message); } catch { return message; } });
    }
    const fields = flattenFlightFields(payload);
    if (!Object.values(fields).some(Boolean)) throw new Error("接口已返回，但暂未识别航班字段；可以手动填写航班详情。");
    if (fields.departure) form.elements.flight_departure_time.value = flightTimeInput(fields.departure);
    if (fields.arrival) form.elements.flight_estimated_arrival_time.value = flightTimeInput(fields.arrival);
    if (fields.terminal) form.elements.flight_arrival_terminal.value = fields.terminal;
    if (fields.carousel) form.elements.flight_baggage_carousel.value = fields.carousel;
    const details = [fields.airline, fields.departAirport && `起飞：${fields.departAirport}`, fields.arriveAirport && `到达：${fields.arriveAirport}`].filter(Boolean).join(" · ");
    const result = form.querySelector("[data-flight-result]");
    if (result) { result.classList.remove("hidden"); result.textContent = details || "航班信息已填入。"; }
    if (!details && !fields.departure && !fields.arrival) throw new Error("查询成功，但响应中没有可显示的航班信息。");
    showToast("航班信息已查询并填入表单。");
  } catch (error) {
    if (error instanceof TypeError) throw new Error("浏览器无法连接飞友接口。该接口可能不允许网页跨域请求；航班详情仍可手动填写。请勿把 API 密钥发给他人。");
    throw error;
  } finally { button.disabled = false; button.textContent = "查询航班"; }
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
          new Notification(`行程提醒：${current.customer_name || "客户"}`, { body: `${timeDisplay(current.appointment_time)} · ${current.location_start || "起始点"} → ${current.location_end || "目的地"}`, tag: key });
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
    <div class="settlement-trip-summary"><span class="form-emblem">＄</span><div><strong>${escapeHTML(trip.customer_name || "未填写客户")}</strong><p>${escapeHTML(trip.service_type || "行程")} · ${dateOnly(trip.appointment_date)} ${timeOnly(trip.appointment_time)}</p><small>${escapeHTML(route)}</small></div></div>
    ${formSection("财务信息", "净收入按行程费用 + 小费 ± 费用明细自动汇总", `<div class="field"><label for="settlement-price">行程费用</label><input id="settlement-price" name="price" type="number" min="0" step="0.01" value="${escapeHTML(draft.price)}" required></div><div class="field"><label for="settlement-tip">小费</label><input id="settlement-tip" name="tip" type="number" min="0" step="0.01" value="${escapeHTML(draft.tip)}" required></div>`)}
    <section class="form-section"><div class="form-section-title"><div><h3>费用明细</h3><p>例如居间费、高速通行费或其他调整</p></div><button type="button" class="button small" data-action="add-expense">＋ 添加费用</button></div><div class="settlement-expense-list">${expenseFields || `<p class="settlement-empty">暂无费用明细，可按需添加。</p>`}</div></section>
    <div class="settlement-net"><span>净收入</span><strong id="settlement-net-value">${currency(total)}</strong></div>
    ${modalActions("保存并结清")}</form>`, "editor-modal settlement-modal");
}

function captureSettlementDraft(form) {
  const data = new FormData(form);
  const rows = [...form.querySelectorAll("[data-expense-row]")];
  state.settlementDraft.price = Number(data.get("price") || 0);
  state.settlementDraft.tip = Number(data.get("tip") || 0);
  state.settlementDraft.expenses = rows.map((_, index) => ({
    id: state.settlementDraft.expenses[index]?.id,
    is_addition: data.get(`expense_addition_${index}`) === "true",
    title: String(data.get(`expense_title_${index}`) || ""),
    amount: Number(data.get(`expense_amount_${index}`) || 0),
  }));
}

async function submitSettlement(form) {
  captureSettlementDraft(form);
  const draft = state.settlementDraft;
  if (draft.price < 0 || draft.tip < 0 || draft.expenses.some(item => !item.title.trim() || item.amount <= 0)) {
    throw new Error("行程费用和小费不能小于 0；每条费用明细需填写名称和大于 0 的金额。");
  }
  const trip = state.trips.find(item => item.id === draft.tripID);
  if (!trip) throw new Error("找不到对应的行程记录。");
  const now = new Date().toISOString();
  await patch("trip_expenses", { trip_id: `eq.${trip.id}`, deleted_at: "is.null" }, { deleted_at: now, updated_at: now });
  for (const [position, item] of draft.expenses.entries()) {
    await upsert("trip_expenses", {
      id: item.id || crypto.randomUUID(), owner_id: state.user.id, trip_id: trip.id,
      is_addition: item.is_addition, title: item.title.trim(), amount: item.amount,
      position, created_at: item.created_at || now, updated_at: now, deleted_at: null,
    });
  }
  await patch("trips", { id: `eq.${trip.id}` }, { price: draft.price, tip: draft.tip, is_paid: true, updated_at: now });
  state.settlementDraft = null;
  document.getElementById("modal-root")?.remove();
  await loadData(); renderApp(); showToast("财务结算已保存并同步。");
}

function openCustomerForm(customer = null) {
  const language = [["zh-Hans", "简体中文"], ["zh-Hant", "繁體中文"], ["en", "English"], ["es", "Español"], ["ja", "日本語"], ["ko", "한국어"]];
  showModal(customer ? "编辑客户" : "新增客户", `<form id="customerForm" class="editor-form customer-form" data-id="${customer?.id || ""}">
    <div class="form-intro"><span class="form-emblem">♙</span><div><strong>${customer ? "更新客户资料" : "建立客户档案"}</strong><p>整理联系人信息，后续行程可以快速关联。</p></div></div>
    ${formSection("基本资料", "客户身份与沟通偏好", `${formField("客户名称 · 必填", "name", customer?.name || "", "text", { required: true, placeholder: "输入客户姓名" })}${customerCategoryPicker(customer?.category || 1, customer?.travel_agency_code || "", customer?.travel_agency_name || "")}${formField("语言喜好", "language_preference", customer?.language_preference || "zh-Hans", "text", { select: language })}${formField("称呼 / 来源", "source", customer?.source || "", "text", { placeholder: "选填" })}${formField("邮箱", "email", customer?.email || "", "email", { placeholder: "name@example.com" })}`)}
    ${formSection("联系方式", "可添加多条，并指定一个默认联系方式", `<div class="field span-2"><div class="dynamic-row-heading"><strong>联系方式</strong><button type="button" class="button small" data-action="add-customer-contact">＋ 添加联系方式</button></div><div class="customer-contact-rows">${(customer ? contactRows(customer.id) : [{ contact_type: "电话", value: "", is_default: true }]).map((item, index) => customerContactField(item, index)).join("")}</div></div>`)}
    ${formSection("常用地址", "可保存多个接送地址，并指定一个默认地址", `<div class="field span-2"><div class="dynamic-row-heading"><strong>常用地址</strong><button type="button" class="button small" data-action="add-customer-address">＋ 添加地址</button></div><div class="customer-address-rows">${(customer ? addressRows(customer.id) : [{ label: "家", address: "", is_default: true }]).map((item, index) => customerAddressField(item, index)).join("")}</div></div>`)}
    ${formSection("备注", "记录与服务相关的补充信息", formField("备注", "remark", customer?.remark || "", "textarea", { span: true, placeholder: "添加备注…" }))}
    </form>`, "editor-modal customer-editor-modal");
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
  showModal(agency ? "编辑旅行社" : "新增旅行社", `<form id="agencyForm" data-id="${agency?.id || ""}"><div class="form-grid">
    ${formField("旅行社代码 · 必填", "agency_code", agency?.agency_code || "", "text", { required: true })}
    ${formField("旅行社名称 · 必填", "name", agency?.name || "", "text", { required: true })}
    ${formField("联系人", "contact_person", agency?.contact_person || "")}
    ${formField("联系电话", "phone", agency?.phone || "", "tel")}
    ${formField("办公地址", "office_address", agency?.office_address || "", "text", { span: true })}
  </div>${modalActions()}</form>`);
}

function openTripForm(trip = null, copying = false) {
  const today = dateInput(new Date());
  const pickupDate = trip && !copying ? dateInput(trip.appointment_date) : today;
  const pickupTime = trip ? timeInput(trip.appointment_time) : "09:00";
  const stops = (trip?.stops || []).map(stop => stop.address).filter(Boolean);
  const statusLabel = !copying && trip?.is_cancelled ? "已取消" : !copying && trip?.is_completed ? "已完成" : "待执行";
  showModal(trip && !copying ? "编辑行程" : copying ? "复制行程" : "新增行程", `<form id="tripForm" class="editor-form trip-form" data-id="${trip && !copying ? trip.id : ""}">
    <div class="form-intro trip-intro"><span class="form-emblem">✈</span><div><strong>${trip && !copying ? "调整行程安排" : copying ? "以原行程信息新建一条行程" : "安排一次新行程"}</strong><p>填写时间和路线，客户与财务信息可以稍后补充。</p></div></div>
    <datalist id="tripAddressSuggestions">${addressRows(trip?.customer_id || "").map(address => `<option value="${escapeHTML(address.address)}">${escapeHTML(address.label || "常用地址")}</option>`).join("")}</datalist>
    ${formSection("行程安排", "选择服务类型与接载时间", `${serviceTypePicker(trip?.service_type || "接机")}${formField("接载日期", "appointment_date", pickupDate, "date", { required: true })}${formField("接载时间", "appointment_time", pickupTime, "time", { required: true })}${formField("乘客人数", "customer_count", trip?.customer_count || "1", "number")}${formField("行李数量", "customer_stuff", trip?.customer_stuff || "0", "number")}`)}
    ${formSection("客户信息", "关联客户后自动带入名称和默认联系方式", `${tripCustomerField(trip?.customer_id || "", trip?.customer_name || "")}${formField("客户名称 · 必填", "customer_name", trip?.customer_name || "", "text", { required: true, placeholder: "输入乘客或联系人姓名" })}${formField("联系方式", "customer_contact", trip?.customer_contact || "", "text", { placeholder: "电话或其他联系方式" })}${orderSourcePicker(trip?.order_source || "普通客户", trip?.travel_agency_code || "", trip?.travel_agency_name || "")}`)}
    ${formSection("接送路线", "可填写地址，或从所选客户的常用地址中选择", `<div class="field span-2"><div class="route-fields">${addressFormField("起始点", "location_start", trip?.location_start || "", "start", false)}<button type="button" class="button route-swap" data-action="swap-route" title="互换起始点和目的地">⇅<span>互换</span></button>${addressFormField("目的地", "location_end", trip?.location_end || "", "end", false)}</div></div><div class="field span-2"><div class="stops-heading"><div><label>停靠点</label><small>可选，可添加多个</small></div><button type="button" class="button small" data-action="add-stop">＋ 添加停靠点</button></div><div class="stops-list">${stops.map((stop, index) => stopField(stop, index)).join("")}</div></div>`)}
    ${formSection("航班信息", "手动填写航班详情；起飞日期与时间会与手机端同步", `${formField("航班号", "flight_info", trip?.flight_info || "", "text", { placeholder: "例如：DL3794" })}${formField("航班起飞日期", "flight_date", trip?.flight_date && !copying ? dateInput(trip.flight_date) : pickupDate, "date")}${`<div class="field span-2 flight-lookup-row"><button type="button" class="button" data-action="lookup-flight">查询航班</button><span data-flight-result class="flight-lookup-result ${trip?.flight_info ? "" : "hidden"}">${trip?.flight_info ? "查询后会在此显示航司和起降机场信息。" : ""}</span></div>`}${formField("起飞时间", "flight_departure_time", flightTimeInput(trip?.flight_departure_time), "time")}${formField("预计到达时间", "flight_estimated_arrival_time", flightTimeInput(trip?.flight_estimated_arrival_time), "time")}${formField("到达航站楼", "flight_arrival_terminal", trip?.flight_arrival_terminal || "")}${formField("行李转盘", "flight_baggage_carousel", trip?.flight_baggage_carousel || "")}`)}
    ${formSection("费用与状态", "行程状态由行程操作管理，结算状态可在此调整", `${formField("车费", "price", trip?.price ?? 0, "number")}${formField("小费", "tip", trip?.tip ?? 0, "number")}${`<div class="field"><label>行程状态</label><div class="readonly-status">${statusLabel}</div></div>`}${formField("结算状态", "is_paid", !copying && trip?.is_paid ? "true" : "false", "text", { select: [["false", "未收款"], ["true", "已结清"]] })}${formField("备注", "memo", trip?.memo || "", "textarea", { span: true, placeholder: "接载说明或其他备注…" })}`)}
    ${reminderFields(trip, pickupDate, pickupTime, copying)}
    ${modalActions(trip && !copying ? "保存行程" : copying ? "创建副本" : "创建行程")}</form>`, "editor-modal trip-editor-modal");
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
    const data = await authRequest("token?grant_type=password", { email: fields.get("email"), password: fields.get("password") });
    attemptedUserID = data.user.id;
    if (state.user && state.user.id !== data.user.id) resetAccountWorkspace();
    writeSession({ ...data, expires_at: Date.now() + (data.expires_in || 3600) * 1000 });
    state.user = data.user;
    await loadData();
    if (state.user?.id !== attemptedUserID) return;
    state.page = "home";
    renderApp();
    if (navigator.onLine && queuedOperationCount() > 0) void replayOfflineQueue();
  } catch (error) {
    if (attemptedUserID && state.user?.id !== attemptedUserID) return;
    state.error = error.message || "登录失败。";
    clearSession();
  } finally {
    state.busy = false;
    if (!state.session) renderLogin();
  }
}

async function initialize() {
  if (!state.session) { renderLogin(); return; }
  document.getElementById("app").innerHTML = `<div class="loading"><div><div class="spinner"></div>正在连接云端…</div></div>`;
  const session = await currentSession();
  if (!session) { renderLogin(); return; }
  const initializedUserID = session.user.id;
  state.user = session.user;
  try {
    await loadData();
    if (state.user?.id !== initializedUserID) return;
    renderApp();
    if (navigator.onLine) void replayOfflineQueue();
  } catch (error) {
    if (state.user?.id !== initializedUserID) return;
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

async function markTrip(id, updates) {
  await patch("trips", { id: `eq.${id}` }, { ...updates, updated_at: new Date().toISOString() });
  await loadData(); renderApp();
  showToast("行程已更新，并同步到云端。");
}

async function deleteTrip(id) {
  if (!confirm("确定删除这条行程吗？删除后会从各设备同步移除。")) return;
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
  await upsert("customers", row);
  const oldContacts = contactRows(id);
  const oldAddresses = addressRows(id);
  await Promise.all([
    patch("customer_contacts", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: now, updated_at: now }),
    patch("customer_addresses", { customer_id: `eq.${id}`, deleted_at: "is.null" }, { deleted_at: now, updated_at: now }),
  ]);
  const defaultContact = Number(new FormData(form).get("contact_default"));
  const defaultAddress = Number(new FormData(form).get("address_default"));
  const addressTasks = [...form.querySelectorAll("[data-address-row]")].map(async (record, index) => {
    const address = record.querySelector('[name="address_value"]').value.trim();
    if (!address) return;
    const prior = oldAddresses.find(item => item.id === record.dataset.id);
    await upsert("customer_addresses", { id: prior?.id || crypto.randomUUID(), owner_id: state.user.id, customer_id: id, label: record.querySelector('[name="address_label"]').value, address, is_default: index === defaultAddress, created_at: prior?.created_at || now, updated_at: now, deleted_at: null });
  });
  // Await all saved rows so customer edits are fully synchronized before the view refreshes.
  const contactTasks = [...form.querySelectorAll("[data-contact-row]")].map(async (record, index) => {
    const value = record.querySelector('[name="contact_value"]').value.trim();
    if (!value) return;
    const prior = oldContacts.find(item => item.id === record.dataset.id);
    await upsert("customer_contacts", { id: prior?.id || crypto.randomUUID(), owner_id: state.user.id, customer_id: id, label: record.querySelector('[name="contact_type"]').value, contact_type: record.querySelector('[name="contact_type"]').value, value, is_default: index === defaultContact, created_at: prior?.created_at || now, updated_at: now, deleted_at: null });
  });
  await Promise.all([...contactTasks, ...addressTasks]);
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
  const { stops: _stops, expenses: _expenses, ...existingColumns } = existing || {};
  const customer = customerByID(data.customer_id);
  const now = new Date().toISOString();
  const appointmentDate = dateAt(data.appointment_date);
  const appointmentTime = dateAt(data.appointment_date, data.appointment_time);
  const row = {
    ...existingColumns, id: existing?.id || crypto.randomUUID(), owner_id: state.user.id,
    service_type: data.service_type, order_source: data.order_source,
    travel_agency_code: data.order_source === "旅行社订单" ? (data.travel_agency_code || "") : "",
    travel_agency_name: data.order_source === "旅行社订单" ? (data.travel_agency_name || "") : "",
    customer_id: data.customer_id || null, customer_name: data.customer_name.trim(),
    customer_contact: data.customer_contact.trim(), customer_count: data.customer_count || "1",
    customer_stuff: data.customer_stuff || "0", appointment_date: appointmentDate, appointment_time: appointmentTime,
    location_start: data.location_start.trim(), location_end: data.location_end.trim(),
    flight_info: data.flight_info.trim(), flight_date: data.flight_date ? dateAt(data.flight_date) : appointmentDate,
    flight_departure_time: data.flight_departure_time || null,
    flight_estimated_arrival_time: data.flight_estimated_arrival_time || null,
    flight_arrival_terminal: data.flight_arrival_terminal.trim(),
    flight_baggage_carousel: data.flight_baggage_carousel.trim(),
    memo: data.memo.trim(), price: Number(data.price || 0), tip: Number(data.tip || 0),
    is_paid: data.is_paid === "true", is_completed: existing?.is_completed || false, is_cancelled: existing?.is_cancelled || false,
    reminder_enabled: form.elements.reminder_enabled.checked,
    reminder_at: form.elements.reminder_enabled.checked ? dateAt(data.reminder_date, data.reminder_time) : null,
    has_second_reminder: form.elements.reminder_enabled.checked && form.elements.has_second_reminder.checked,
    second_reminder_at: form.elements.reminder_enabled.checked && form.elements.has_second_reminder.checked ? dateAt(data.second_reminder_date, data.second_reminder_time) : null,
    currency_code: state.settings?.currency_code || "USD", created_at: existing?.created_at || now, updated_at: now, deleted_at: null,
  };
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
  await upsert("trips", row);
  if (existing) {
    const deletedAt = now;
    await patch("trip_stops", { trip_id: `eq.${row.id}`, deleted_at: "is.null" }, { deleted_at: deletedAt, updated_at: deletedAt });
  }
  for (const [position, address] of stopAddresses.entries()) {
    const prior = existing?.stops?.[position];
    await upsert("trip_stops", { id: prior?.id || crypto.randomUUID(), owner_id: state.user.id, trip_id: row.id, position, address, updated_at: now, deleted_at: null });
  }
  await loadData(); renderApp(); showToast(existing ? "行程已更新。" : "行程已新增。");
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
  if (data.variflight_key?.trim()) setAccountPreference("variflight-key", data.variflight_key.trim());
  else removeAccountPreference("variflight-key");
  state.settings = settings; renderApp(); showToast("设置已保存。");
}

async function logout() {
  try { await request("/auth/v1/logout", { method: "POST" }); } catch { /* local session is still cleared */ }
  clearSession(); state.error = ""; renderLogin();
}

document.addEventListener("submit", async event => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  event.preventDefault();
  try {
    if (form.id === "loginForm") return await doLogin(form);
    if (form.id === "customerForm") return await submitCustomer(form);
    if (form.id === "agencyForm") return await submitAgency(form);
    if (form.id === "tripForm") return await submitTrip(form);
    if (form.id === "settlementForm") return await submitSettlement(form);
    if (form.id === "settingsForm") return await submitSettings(form);
  } catch (error) { showToast(error.message || "操作失败，请重试。", true); }
});

document.addEventListener("input", event => {
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
  if (!(input instanceof HTMLInputElement) || input.type !== "number") return;
  const isMoney = ["price", "tip"].includes(input.name) || input.name.startsWith("expense_amount_");
  if (!isMoney) return;
  if (/^0+(?:\.0+)?$/.test(input.value.trim())) input.value = "";
  else input.select();
});

document.addEventListener("change", event => {
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
    picker?.querySelectorAll(".service-type-option").forEach(option => option.classList.toggle("selected", option.contains(event.target)));
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
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  try {
    if (action === "navigate") { state.page = button.dataset.page; state.search = ""; renderApp(); }
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
      state.paymentMethods = state.paymentMethods.filter(item => item.id !== button.dataset.id);
      updatePageContent();
      await savePaymentMethods();
    }
    else if (action === "add-card-qr") {
      state.businessCard.qrCodes.push({ id: crypto.randomUUID(), name: "", imageData: null });
      updatePageContent();
      await saveBusinessCard();
    }
    else if (action === "remove-card-qr") {
      state.businessCard.qrCodes = state.businessCard.qrCodes.filter(item => item.id !== button.dataset.id);
      updatePageContent();
      await saveBusinessCard();
    }
    else if (action === "card-style") {
      state.businessCard.style = Number(button.dataset.style);
      updatePageContent();
      await saveBusinessCard();
    }
    else if (action === "save-business-card") await saveBusinessCard();
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
    else if (action === "edit-agency") openAgencyForm(state.agencies.find(item => item.id === button.dataset.id));
    else if (action === "navigate-saved-address") {
      const encoded = encodeURIComponent(button.dataset.address || "");
      const url = (getAccountPreference("navigation") || "appleMaps") === "googleMaps" ? `https://www.google.com/maps/dir/?api=1&destination=${encoded}&travelmode=driving` : `https://maps.apple.com/?daddr=${encoded}&dirflg=d`;
      window.open(url, "_blank", "noopener");
    }
    else if (action === "close-modal") document.getElementById("modal-root")?.remove();
    else if (action === "close-picker") document.getElementById("picker-backdrop")?.remove();
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
      if (input) input.value = button.dataset.address || "";
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
      if (form) { const start = form.elements.location_start.value; form.elements.location_start.value = form.elements.location_end.value; form.elements.location_end.value = start; }
    }
    else if (action === "current-location") {
      const form = button.closest("form");
      if (!navigator.geolocation) throw new Error("此浏览器不支持定位功能。");
      button.disabled = true;
      navigator.geolocation.getCurrentPosition(position => {
        const target = button.dataset.target;
        const input = target === "start" ? form?.elements.location_start : target === "end" ? form?.elements.location_end : form?.querySelector(`[data-stop-index="${target.split(":")[1]}"]`);
        if (input) input.value = `${position.coords.latitude.toFixed(6)}, ${position.coords.longitude.toFixed(6)}`;
        button.disabled = false;
      }, error => { button.disabled = false; showToast(error.message || "无法获取当前位置，请检查浏览器定位权限。", true); }, { enableHighAccuracy: true, timeout: 12000 });
    }
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
    else if (action === "toggle-complete") {
      await markTrip(button.dataset.id, { is_completed: true, is_cancelled: false, updated_at: new Date().toISOString() });
      if (confirm("行程已结束，是否现在进行财务结算？")) {
        const trip = state.trips.find(item => item.id === button.dataset.id);
        if (trip) openSettlement(trip);
      }
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
      updatePageContent(); showToast("费用项目已保存。");
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
    else if (action === "wallet-period") { location.hash = `period=${button.dataset.period}&anchor=${dateInput(new Date())}`; updatePageContent(); }
    else if (action === "wallet-shift") {
      const params = new URLSearchParams(location.hash.slice(1));
      const period = params.get("period") || "day";
      const anchor = params.has("anchor") ? new Date(`${params.get("anchor")}T12:00:00`) : new Date();
      const amount = Number(button.dataset.step);
      if (period === "day") anchor.setDate(anchor.getDate() + amount);
      if (period === "week") anchor.setDate(anchor.getDate() + amount * 7);
      if (period === "month") anchor.setMonth(anchor.getMonth() + amount);
      if (period === "year") anchor.setFullYear(anchor.getFullYear() + amount);
      location.hash = `period=${period}&anchor=${dateInput(anchor)}`; updatePageContent();
    }
  } catch (error) { showToast(error.message || "操作失败，请重试。", true); }
});

initialize();
