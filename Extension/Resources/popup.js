/* Vision Font — toolbar popup. Talks only to the background worker. */
(() => {
  'use strict';
  const api = globalThis.browser || globalThis.chrome;
  const $ = s => document.querySelector(s);
  let host = null;
  let last = null;
  let dragging = false;

  async function activeHost() {
    try {
      const [tab] = await api.tabs.query({ active: true, currentWindow: true });
      if (!tab) return null;
      try { const r = await api.tabs.sendMessage(tab.id, { type: 'vf:whoami' }); if (r && r.host) return r.host; } catch (e) { /* no content script on this page */ }
      if (tab.url) { try { return new URL(tab.url).hostname || null; } catch (e) { /* ignore */ } }
    } catch (e) { /* ignore */ }
    return null;
  }

  const STATUS = {
    live: ['Live', 'live'], noFace: ['No face', ''], stale: ['Stale data', 'bad'], trackingOff: ['Tracking off', ''],
    notRunning: ['App not running', 'bad'], unreachable: ['App not reachable', 'bad'], starting: ['Connecting…', ''],
  };
  const WARN = {
    notRunning: ['Companion app not running', 'Open <b>Vision Font</b> from your Applications folder (or press Run in Xcode), then turn on <b>Tracking</b> from the eye in the menu bar. Until then the extension keeps the last size, or uses the manual distance below.'],
    unreachable: ['Can\'t reach the Vision Font app', 'Safari couldn\'t talk to the app\'s extension. Make sure the Vision Font app is installed (run it once from Xcode), then reopen this popup. Using the last size or the manual distance meanwhile.'],
    trackingOff: ['Camera tracking is off', 'Click the eye in the menu bar and turn on <b>Tracking</b> to resize by live distance.'],
    stale: ['Distance data is stale', 'The app stopped sending distance readings. Check that tracking is on and the camera isn\'t used by another app.'],
  };

  function render(s) {
    if (!s || s.type !== 'vf:state') { $('#diag').textContent = (s && s.error) || 'No response from the extension.'; return; }
    last = s;
    const [label, cls] = STATUS[s.status] || [s.status, ''];
    const pill = $('#statusPill'); pill.textContent = label; pill.className = 'pill ' + cls;
    const w = WARN[s.status];
    $('#companionWarn').hidden = !w;
    if (w) { $('#warnTitle').textContent = w[0]; $('#warnBody').innerHTML = w[1]; }

    $('#dist').textContent = Math.round(s.distanceCm);
    $('#distSrc').textContent = { live: 'camera', held: 'last measured', manual: 'manual' }[s.source] || '';
    $('#blur').textContent = s.blur.toFixed(2);
    $('#wearing').textContent = s.wearing ? 'glasses on' : 'no glasses';
    $('#scale').textContent = s.scale.toFixed(2);
    $('#capNote').textContent = !s.active ? (s.paused ? 'paused' : 'off for site') : (s.rawScale > s.cap + 1e-6 ? 'at max' : '');

    $('#siteName').textContent = s.host || 'this site';
    $('#siteOn').checked = !s.siteDisabled; $('#siteOn').disabled = !s.host;
    $('#paused').checked = !!s.paused;
    document.querySelectorAll('.seg button').forEach(b => b.setAttribute('aria-checked', String(b.dataset.mode === s.mode)));
    if (!dragging) {
      $('#comfort').value = s.comfort; $('#comfortOut').textContent = Math.round(s.comfort * 100) + '%';
      const cap = s.mode === 'font' ? s.fontCap : s.zoomCap;
      $('#cap').value = cap; $('#capOut').textContent = cap.toFixed(1) + '×';
      $('#manualCm').value = s.manualCm; $('#manualCmOut').textContent = s.manualCm + ' cm';
    }
    $('#fallback').value = s.fallback;
    const ppi = (s.pxPerMm * 25.4).toFixed(0);
    $('#diag').textContent = `Screen ${ppi} px/in (${s.pxPerMmSource}) · store: ${s.store || '—'}` + (s.nativeError ? ` · ${s.nativeError}` : '');
  }

  const send = msg => api.runtime.sendMessage({ host, ...msg }).then(render).catch(e => render({ error: String(e) }));
  const refresh = () => send({ type: 'vf:popup' });

  $('#siteOn').addEventListener('change', e => send({ type: 'vf:setPrefs', site: host, siteEnabled: e.target.checked }));
  $('#paused').addEventListener('change', e => send({ type: 'vf:setShared', paused: e.target.checked }));
  document.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => send({ type: 'vf:setPrefs', mode: b.dataset.mode })));
  const live = (id, fmt) => $(id).addEventListener('input', e => { dragging = true; $(id + 'Out').textContent = fmt(+e.target.value); });
  live('#comfort', v => Math.round(v * 100) + '%');
  live('#cap', v => v.toFixed(1) + '×');
  live('#manualCm', v => v + ' cm');
  $('#comfort').addEventListener('change', e => { dragging = false; send({ type: 'vf:setShared', comfort: +e.target.value }); });
  $('#cap').addEventListener('change', e => { dragging = false; send({ type: 'vf:setPrefs', [last && last.mode === 'font' ? 'fontCap' : 'zoomCap']: +e.target.value }); });
  $('#manualCm').addEventListener('change', e => { dragging = false; send({ type: 'vf:setPrefs', manualCm: +e.target.value }); });
  $('#fallback').addEventListener('change', e => send({ type: 'vf:setPrefs', fallback: e.target.value }));

  activeHost().then(h => { host = h; refresh(); setInterval(refresh, 500); });
})();
