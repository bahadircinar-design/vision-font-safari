/*
 * Vision Font — background service worker.
 *
 * Every ~500 ms while a tab is visible, the content script in that tab sends a "vf:tick".
 * That keeps this (non-persistent) worker awake and drives the poll of the native handler
 * (SafariWebExtensionHandler.swift) via browser.runtime.sendNativeMessage, throttled to one
 * call per POLL_MS for all tabs. The worker turns distance + prescription into a page scale with
 * the ported model (model.js + scale.js) and answers the tick; it also pushes a refresh to the
 * active tab whenever settings change. Not a medical device.
 */
importScripts('model.js', 'scale.js');

const api = globalThis.browser || globalThis.chrome;
const M = globalThis.VisionModel;
const VS = globalThis.VisionScale;
const POLL_MS = 450;
const NATIVE_APP_ID = 'com.bahacinar.VisionFont'; // Safari ignores this and talks to the containing app

const DEFAULT_PREFS = Object.freeze({
  mode: 'zoom',            // 'zoom' (CSS zoom on <html>) | 'font' (text-only)
  zoomCap: VS.S.DEFAULT_ZOOM_CAP,
  fontCap: VS.S.DEFAULT_FONT_CAP,
  disabledSites: {},       // { 'example.com': true }
  manualCm: 60,            // used when there's no live distance (and nothing to hold)
  fallback: 'hold',        // 'hold' last live distance | 'manual'
  localComfort: 1,         // only used if the native handler can't be reached at all
  localPaused: false,
});

const st = {
  prefs: { ...DEFAULT_PREFS },
  prefsLoaded: null,
  native: null,            // last successful native reply
  nativeOkAt: 0,
  nativeError: null,
  lastPollAt: 0,
  inflight: null,
  held: null,              // { distanceCm, at } last live reading
  epoch: 1,                // bumps whenever a setting changes => content applies immediately
  settingsStamp: null,
};

/* ---------------- prefs ---------------- */
function loadPrefs() {
  if (!st.prefsLoaded) {
    st.prefsLoaded = api.storage.local.get('prefs').then(o => {
      st.prefs = { ...DEFAULT_PREFS, ...((o && o.prefs) || {}) };
    }).catch(() => {});
  }
  return st.prefsLoaded;
}
async function savePrefs(patch) {
  await loadPrefs();
  st.prefs = { ...st.prefs, ...patch };
  st.epoch++;
  try { await api.storage.local.set({ prefs: st.prefs }); } catch (e) { console.warn('Vision Font: storage failed', e); }
}
api.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.prefs && changes.prefs.newValue) {
    st.prefs = { ...DEFAULT_PREFS, ...changes.prefs.newValue };
  }
});

/* ---------------- native polling ---------------- */
function sendNative(message) {
  return new Promise((resolve, reject) => {
    try {
      const p = api.runtime.sendNativeMessage(NATIVE_APP_ID, message, reply => {
        // callback style (only used if the promise form isn't available)
        const err = api.runtime.lastError;
        if (err) reject(new Error(err.message)); else resolve(reply);
      });
      if (p && typeof p.then === 'function') p.then(resolve, reject);
    } catch (e) { reject(e); }
  });
}

async function poll(force = false) {
  const now = Date.now();
  if (st.inflight) return st.inflight;
  if (!force && now - st.lastPollAt < POLL_MS) return;
  st.lastPollAt = now;
  st.inflight = sendNative({ type: 'get', sentAt: now })
    .then(reply => {
      if (!reply || reply.ok !== true) throw new Error((reply && reply.error) || 'Empty reply from Vision Font app extension');
      st.native = reply; st.nativeOkAt = Date.now(); st.nativeError = null;
      const stamp = JSON.stringify(reply.settings || {});
      if (stamp !== st.settingsStamp) { st.settingsStamp = stamp; st.epoch++; }
    })
    .catch(e => { st.nativeError = String((e && e.message) || e); })
    .finally(() => { st.inflight = null; });
  return st.inflight;
}

/* ---------------- state -> scale ---------------- */
function companionStatus() {
  const n = st.native;
  if (!n || Date.now() - st.nativeOkAt > 5000) return st.nativeError ? 'unreachable' : 'starting';
  if (!n.appRunning) return 'notRunning';
  const live = n.live || {};
  if (!live.tracking) return 'trackingOff';
  if (!(n.liveAgeMs <= VS.S.STALE_MS)) return 'stale';
  if (!live.faceFound || !(live.distanceCm > 0)) return 'noFace';
  return 'live';
}

function computeFor(host) {
  const p = st.prefs;
  const n = st.native;
  const status = companionStatus();
  const settings = (n && n.settings) || VS.defaultSettings();
  const comfort = n && n.settings ? settings.comfort : p.localComfort;
  const paused = n && n.settings ? !!settings.paused : !!p.localPaused;

  let distanceCm, source;
  if (status === 'live') {
    distanceCm = n.live.distanceCm; source = 'live';
    st.held = { distanceCm, at: Date.now() };
  } else if (p.fallback === 'hold' && st.held) {
    distanceCm = st.held.distanceCm; source = 'held';
  } else {
    distanceCm = p.manualCm; source = 'manual';
  }

  const cap = p.mode === 'font' ? p.fontCap : p.zoomCap;
  const r = VS.pageScale(settings.rx, distanceCm, { pxPerMm: settings.pxPerMm, comfort, cap });
  const siteDisabled = !!(host && p.disabledSites[host]);
  const active = !paused && !siteDisabled;
  return {
    type: 'vf:state',
    epoch: st.epoch,
    host: host || null,
    mode: p.mode,
    active, paused, siteDisabled,
    scale: active ? r.scale : 1,
    modelScale: r.scale, rawScale: r.rawScale, cap,
    distanceCm: r.distanceCm, source, status,
    blur: r.blur, enlarge: r.enlarge, px: r.px, comfort,
    wearing: !!VS.effectiveRx(settings.rx).wearing,
    lens: (settings.rx && settings.rx.lens) || 'single',
    pxPerMm: r.pxPerMm, pxPerMmSource: settings.pxPerMm ? settings.pxPerMmSource || 'app' : 'default',
    fallback: p.fallback, manualCm: p.manualCm,
    zoomCap: p.zoomCap, fontCap: p.fontCap,
    store: n ? n.store : null,
    storeErrors: n ? n.errors || [] : [],
    nativeError: st.nativeError,
    liveAgeMs: n ? n.liveAgeMs : null,
    deadband: VS.S.DEADBAND,
    live: source === 'live',
  };
}

/* ---------------- push to tabs ---------------- */
async function refreshActiveTabs() {
  try {
    const tabs = await api.tabs.query({ active: true });
    for (const t of tabs) {
      if (t.id == null) continue;
      api.tabs.sendMessage(t.id, { type: 'vf:refresh', epoch: st.epoch }).catch(() => {});
    }
  } catch (e) { /* no tabs permission needed for query by state; ignore */ }
}

/* ---------------- messages ---------------- */
api.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg.type !== 'string' || !msg.type.startsWith('vf:')) return false;
  (async () => {
    await loadPrefs();
    switch (msg.type) {
      case 'vf:tick': {               // from content scripts in visible tabs
        await poll(false);
        return computeFor(msg.host);
      }
      case 'vf:popup': {              // popup wants a fresh snapshot
        await poll(true);
        return computeFor(msg.host);
      }
      case 'vf:setPrefs': {           // extension-only prefs (mode, caps, sites, fallback, manual distance)
        const patch = {};
        if (msg.mode === 'zoom' || msg.mode === 'font') patch.mode = msg.mode;
        if (Number.isFinite(msg.zoomCap)) patch.zoomCap = Math.min(VS.S.MAX_CAP, Math.max(1.1, msg.zoomCap));
        if (Number.isFinite(msg.fontCap)) patch.fontCap = Math.min(VS.S.MAX_CAP, Math.max(1.1, msg.fontCap));
        if (Number.isFinite(msg.manualCm)) patch.manualCm = Math.min(150, Math.max(25, Math.round(msg.manualCm)));
        if (msg.fallback === 'hold' || msg.fallback === 'manual') patch.fallback = msg.fallback;
        if (typeof msg.site === 'string' && msg.site && typeof msg.siteEnabled === 'boolean') {
          const ds = { ...st.prefs.disabledSites };
          if (msg.siteEnabled) delete ds[msg.site]; else ds[msg.site] = true;
          patch.disabledSites = ds;
        }
        await savePrefs(patch);
        refreshActiveTabs();
        return computeFor(msg.host);
      }
      case 'vf:setShared': {          // comfort / global pause: shared with the Mac app
        const out = { type: 'setPrefs' };
        if (Number.isFinite(msg.comfort)) out.comfort = Math.round(Math.min(1.6, Math.max(0.7, msg.comfort)) * 100) / 100;
        if (typeof msg.paused === 'boolean') out.paused = msg.paused;
        let wrote = false;
        try { const r = await sendNative(out); wrote = !!(r && r.ok); if (wrote) { st.native = r; st.nativeOkAt = Date.now(); } } catch (e) { st.nativeError = String(e.message || e); }
        // Always mirror locally so the extension still works if the app/handler is unavailable.
        const patch = {};
        if (out.comfort != null) patch.localComfort = out.comfort;
        if (out.paused != null) patch.localPaused = out.paused;
        await savePrefs(patch);
        if (wrote && st.native && st.native.settings) {
          if (out.comfort != null) st.native.settings.comfort = out.comfort;
          if (out.paused != null) st.native.settings.paused = out.paused;
        }
        refreshActiveTabs();
        return computeFor(msg.host);
      }
      default: return { type: 'vf:error', error: 'unknown message ' + msg.type };
    }
  })().then(sendResponse, e => sendResponse({ type: 'vf:error', error: String(e) }));
  return true; // async response
});

loadPrefs();
