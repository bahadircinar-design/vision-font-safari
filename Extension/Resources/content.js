/*
 * Vision Font — content script (top frame only, all URLs).
 * Asks the background worker for the target scale ~every 500 ms while this tab is visible and applies it:
 *   zoom mode : CSS `zoom` on <html> (Safari supports it), animated over ~250 ms
 *   font mode : text-only. Each element that directly holds text is tagged once with its original
 *               font-size/line-height; one root CSS variable (--vf-scale) then scales them all, with a short
 *               CSS transition. New content is tagged as it appears.
 * Live changes under 5% are ignored (dead-band); setting changes apply immediately. Not a medical device.
 */
(() => {
  'use strict';
  if (window.top !== window) return;
  if (window.__visionFontLoaded) return;
  window.__visionFontLoaded = true;

  const api = globalThis.browser || globalThis.chrome;
  const HOST = location.hostname || '';
  const TICK_MS = 500;
  const ZOOM_ANIM_MS = 250;
  const MAX_TAGGED = 25000;

  // <html> may not exist yet at document_start in some engines, so look it up when needed.
  const R = () => document.documentElement;
  const st = { mode: null, applied: 1, epoch: -1, anim: 0, alive: true, timer: 0, origZoom: null, fontReady: false };

  /* ---------------- zoom mode ---------------- */
  function setZoomNow(z) {
    if (st.origZoom === null) st.origZoom = R().style.getPropertyValue('zoom') || '';
    const doc = document.scrollingElement || R();
    const maxBefore = Math.max(1, doc.scrollHeight - window.innerHeight);
    const ratio = doc.scrollTop / maxBefore;
    if (Math.abs(z - 1) < 0.001) {
      if (st.origZoom) R().style.setProperty('zoom', st.origZoom); else R().style.removeProperty('zoom');
    } else {
      R().style.setProperty('zoom', z.toFixed(3), 'important');
    }
    // keep the reading position roughly where it was
    if (ratio > 0) doc.scrollTop = ratio * Math.max(1, doc.scrollHeight - window.innerHeight);
  }
  function animateZoom(from, to) {
    cancelAnimationFrame(st.anim);
    const t0 = performance.now();
    const step = now => {
      const k = Math.min(1, (now - t0) / ZOOM_ANIM_MS);
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2; // easeInOutQuad
      setZoomNow(from + (to - from) * e);
      if (k < 1) st.anim = requestAnimationFrame(step);
    };
    if (document.hidden) setZoomNow(to); else st.anim = requestAnimationFrame(step);
  }

  /* ---------------- font (text-only) mode ---------------- */
  const STYLE_ID = 'vision-font-style';
  const CSS = `
    [data-vf-fs] { font-size: calc(var(--vf-fs) * var(--vf-scale, 1)) !important; transition: font-size .22s ease-out, line-height .22s ease-out; }
    [data-vf-lh] { line-height: calc(var(--vf-lh) * var(--vf-scale, 1)) !important; }
    html.vf-measuring [data-vf-fs] { transition: none !important; }
  `;
  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'svg', 'IFRAME', 'CANVAS', 'VIDEO', 'AUDIO', 'IMG', 'PICTURE', 'HEAD', 'META', 'LINK', 'TITLE', 'BR', 'HR']);
  const FORM = new Set(['INPUT', 'TEXTAREA', 'SELECT', 'BUTTON']);
  let tagged = 0;
  let pending = new Set();
  let flushTimer = 0;
  let observer = null;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const s = document.createElement('style');
    s.id = STYLE_ID; s.textContent = CSS;
    (document.head || R()).appendChild(s);
  }
  function hasOwnText(el) {
    if (FORM.has(el.tagName)) return true;
    for (let n = el.firstChild; n; n = n.nextSibling) if (n.nodeType === 3 && n.nodeValue.trim()) return true;
    return false;
  }
  function collect(rootEl, out) {
    if (!rootEl || rootEl.nodeType !== 1) return;
    const walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_ELEMENT, {
      acceptNode: el => (SKIP.has(el.tagName) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    let el = walker.currentNode;
    while (el && out.length + tagged < MAX_TAGGED) {
      if (el.nodeType === 1 && !el.hasAttribute('data-vf-fs') && !SKIP.has(el.tagName) && hasOwnText(el)) out.push(el);
      el = walker.nextNode();
    }
  }
  /** Measure original (unscaled) sizes in one synchronous pass: set --vf-scale to 1, read, restore. */
  function tagElements(list) {
    if (!list.length) return;
    const current = R().style.getPropertyValue('--vf-scale') || '1';
    R().classList.add('vf-measuring');
    R().style.setProperty('--vf-scale', '1');
    const sizes = list.map(el => { const cs = getComputedStyle(el); return [parseFloat(cs.fontSize), cs.lineHeight]; });
    list.forEach((el, i) => {
      const [fs, lh] = sizes[i];
      if (!(fs > 0)) return;
      el.style.setProperty('--vf-fs', fs + 'px');
      el.setAttribute('data-vf-fs', '');
      if (lh && lh.endsWith('px')) { el.style.setProperty('--vf-lh', lh); el.setAttribute('data-vf-lh', ''); }
      tagged++;
    });
    R().style.setProperty('--vf-scale', current);
    void getComputedStyle(R()).fontSize; // flush with transitions off so nothing animates from 1x
    R().classList.remove('vf-measuring');
  }
  function startFontMode() {
    if (st.fontReady) return;
    st.fontReady = true;
    ensureStyle();
    const run = () => {
      const list = []; collect(document.body || R(), list); tagElements(list);
      observer = new MutationObserver(muts => {
        for (const m of muts) for (const n of m.addedNodes) if (n.nodeType === 1) pending.add(n); else if (n.nodeType === 3 && n.parentElement) pending.add(n.parentElement);
        if (!flushTimer) flushTimer = setTimeout(flushPending, 300);
      });
      observer.observe(document.body || R(), { childList: true, subtree: true });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run, { once: true }); else run();
  }
  function flushPending() {
    flushTimer = 0;
    const list = [];
    for (const n of pending) if (n.isConnected) collect(n, list);
    pending = new Set();
    tagElements(list);
  }
  function stopFontMode() {
    if (!st.fontReady) return;
    st.fontReady = false;
    if (observer) observer.disconnect();
    observer = null; pending = new Set(); clearTimeout(flushTimer); flushTimer = 0;
    R().style.removeProperty('--vf-scale');
    document.querySelectorAll('[data-vf-fs],[data-vf-lh]').forEach(el => {
      el.removeAttribute('data-vf-fs'); el.removeAttribute('data-vf-lh');
      el.style.removeProperty('--vf-fs'); el.style.removeProperty('--vf-lh');
    });
    tagged = 0;
    const s = document.getElementById(STYLE_ID); if (s) s.remove();
  }
  function setFontScale(s) { R().style.setProperty('--vf-scale', s.toFixed(3)); }

  /* ---------------- apply ---------------- */
  function apply(state) {
    if (!state || state.type !== 'vf:state') return;
    const target = state.active ? Math.max(1, state.scale) : 1;
    const modeChanged = state.mode !== st.mode;
    const epochChanged = state.epoch !== st.epoch;
    st.epoch = state.epoch;

    if (modeChanged) {
      // reset whatever the previous mode did
      if (st.mode === 'zoom') { cancelAnimationFrame(st.anim); setZoomNow(1); }
      if (st.mode === 'font') stopFontMode();
      st.mode = state.mode; st.applied = 1;
    }
    const needed = modeChanged || epochChanged || (state.live ? VisionDeadband(st.applied, target, state.deadband) : Math.abs(target - st.applied) > 0.001);
    if (!needed) return;
    if (Math.abs(target - st.applied) < 0.001 && !modeChanged) return;

    if (st.mode === 'zoom') animateZoom(st.applied, target);
    else {
      if (target > 1.001) { startFontMode(); setFontScale(target); } else { stopFontMode(); }
    }
    st.applied = target;
  }
  function VisionDeadband(applied, target, band) {
    if (!(applied > 0)) return true;
    return Math.abs(target - applied) / applied >= (band || 0.05);
  }

  /* ---------------- messaging ---------------- */
  function stop() { st.alive = false; clearInterval(st.timer); }
  async function tick() {
    if (!st.alive || document.hidden) return;
    try {
      const state = await api.runtime.sendMessage({ type: 'vf:tick', host: HOST });
      apply(state);
    } catch (e) {
      // extension reloaded/disabled: the old content script can no longer talk to it
      if (String(e && e.message).match(/invalidated|disconnected|Could not establish/i)) stop();
    }
  }
  api.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || typeof msg.type !== 'string') return false;
    if (msg.type === 'vf:refresh') { tick(); return false; }
    if (msg.type === 'vf:whoami') { sendResponse({ host: HOST, applied: st.applied, mode: st.mode }); return false; }
    return false;
  });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });
  window.addEventListener('focus', tick);
  st.timer = setInterval(tick, TICK_MS);
  tick();
})();
