/* Test double for the Safari WebExtension APIs + the native handler, used by Tests/test-extension.js (node)
 * and Tests/screenshots.py (Chrome). Not shipped in the extension.
 * Creates three API objects (background, content, popup) wired together like Safari would. */
(function (root) {
  'use strict';
  function makeEvent() { const ls = []; return { ls, addListener: f => ls.push(f), removeListener: f => { const i = ls.indexOf(f); if (i >= 0) ls.splice(i, 1); } }; }
  function dispatch(ev, msg, sender) {
    return new Promise(resolve => {
      let answered = false;
      for (const l of ev.ls) {
        const r = l(msg, sender, v => { if (!answered) { answered = true; resolve(v); } });
        if (r === true) return; // async response pending
      }
      if (!answered) resolve(undefined);
    });
  }

  function createMocks(opts = {}) {
    const now = opts.now || (() => Date.now());
    // What the Vision Font app last wrote (mirrors Shared/SharedStore.swift + NativeBridge)
    const native = {
      appRunning: true, tracking: true, faceFound: true, distanceCm: 50, liveAgeMs: 120, reachable: true,
      settings: {
        rx: { od: { sph: 0.5, cyl: -0.5, axis: 90, add: 2 }, os: { sph: 0.75, cyl: 0, add: 2 }, age: 60, wearing: false, lens: 'progressive', pdFar: 64, pdNear: 61 },
        comfort: 1, pxPerMm: 4.87, pxPerMmSource: 'detected', paused: false, focalNorm: 0.87, calibrationCm: 50, updatedAt: 1,
      },
      calls: [],
      ...(opts.native || {}),
    };
    function nativeReply(msg) {
      native.calls.push(msg);
      if (!native.reachable) return Promise.reject(new Error('Native messaging host not found'));
      if (msg.type === 'setPrefs') {
        if (msg.comfort != null) native.settings.comfort = msg.comfort;
        if (msg.paused != null) native.settings.paused = msg.paused;
        native.settings.updatedAt++;
      }
      return Promise.resolve(JSON.parse(JSON.stringify({
        ok: true, now: now(), store: 'appGroup', appRunning: native.appRunning, heartbeatAgeMs: native.appRunning ? 200 : 60000,
        live: { distanceCm: native.distanceCm, timestamp: now() - native.liveAgeMs, faceFound: native.faceFound, tracking: native.tracking, calibrated: true },
        liveAgeMs: native.liveAgeMs, settings: native.settings, errors: [],
      })));
    }

    const store = {};
    const storageChanged = makeEvent();
    const storage = {
      local: {
        get: k => Promise.resolve(typeof k === 'string' ? (k in store ? { [k]: JSON.parse(JSON.stringify(store[k])) } : {}) : JSON.parse(JSON.stringify(store))),
        set: o => { const changes = {}; for (const [k, v] of Object.entries(o)) { changes[k] = { oldValue: store[k], newValue: v }; store[k] = JSON.parse(JSON.stringify(v)); } storageChanged.ls.forEach(l => l(changes, 'local')); return Promise.resolve(); },
      },
      onChanged: storageChanged,
    };

    const bgMsg = makeEvent(), csMsg = makeEvent();
    const tab = { id: 1, active: true, url: opts.url || 'https://example.com/article' };
    const tabs = {
      query: () => Promise.resolve([tab]),
      sendMessage: (id, msg) => dispatch(csMsg, msg, { id: 'ext' }),
    };
    const bg = { runtime: { onMessage: bgMsg, sendNativeMessage: (id, msg) => nativeReply(msg), lastError: null }, storage, tabs };
    const cs = { runtime: { onMessage: csMsg, sendMessage: msg => dispatch(bgMsg, msg, { tab }) }, storage };
    const popup = { runtime: { onMessage: makeEvent(), sendMessage: msg => dispatch(bgMsg, msg, {}) }, storage, tabs };
    return { bg, cs, popup, native, store, tab };
  }
  const api = { createMocks };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.VFMock = api;
})(typeof window !== 'undefined' ? window : globalThis);
