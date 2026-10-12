/* Playwright init script: boots background.js (with an importScripts shim) and exposes window.__vf for tests.
 * window.__VF_ROLE = 'content' | 'popup' is set by the caller before this runs. */
(function () {
  const RES = '/Extension/Resources/';
  function loadSync(src) {
    const x = new XMLHttpRequest(); x.open('GET', src, false); x.send();
    if (x.status !== 200) throw new Error('load ' + src + ' ' + x.status);
    (0, eval)(x.responseText + '\n//# sourceURL=' + src);
  }
  loadSync('/Tests/harness/mock-browser.js');
  const m = window.VFMock.createMocks(window.__VF_OPTS || {});
  window.__vf = m;
  self.importScripts = (...files) => files.forEach(f => loadSync(RES + f));
  window.browser = m.bg;
  importScripts('background.js');
  window.browser = window.__VF_ROLE === 'popup' ? m.popup : m.cs;
  if (window.__VF_ROLE === 'content') loadSync(RES + 'content.js');
})();
