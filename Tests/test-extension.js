// Vision Font — background worker behaviour test (node, no browser needed): node Tests/test-extension.js
// Boots Extension/Resources/background.js in a VM with mocked Safari APIs + native handler and walks through
// live / no-face / stale / app-not-running / unreachable states, per-site disable, pause, comfort, mode + cap.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const RES = path.join(__dirname, '..', 'Extension', 'Resources');
const { createMocks } = require('./harness/mock-browser.js');
const VS = require(path.join(RES, 'scale.js'));
const expect = (rx, d, comfort = 1, cap = 2.5) => VS.pageScale(rx, d, { pxPerMm: 4.87, comfort, cap }).scale;

let clock = 1_800_000_000_000;
const m = createMocks({ now: () => clock });
const ctx = vm.createContext({ console, setTimeout, clearTimeout, setInterval, clearInterval, Promise });
ctx.globalThis = ctx;
ctx.browser = m.bg;
ctx.importScripts = (...files) => files.forEach(f => vm.runInContext(fs.readFileSync(path.join(RES, f), 'utf8'), ctx, { filename: f }));
vm.runInContext('Date.now = () => __clock()', Object.assign(ctx, { __clock: () => clock }));
vm.runInContext(fs.readFileSync(path.join(RES, 'background.js'), 'utf8'), ctx, { filename: 'background.js' });

const send = msg => m.cs.runtime.sendMessage({ host: 'example.com', ...msg });
const step = (ms = 500) => { clock += ms; };
const near = (a, b, t = 0.005) => Math.abs(a - b) <= t;

(async () => {
  m.native.settings.rx.wearing = true;               // progressives on
  let s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'live'); assert.strictEqual(s.source, 'live');
  assert(near(s.scale, expect(m.native.settings.rx, 50), 1e-12), `50 cm, progressives on, MacBook: ~1.28x (got ${s.scale})`);
  console.log(`✓ live 50 cm → ${s.scale.toFixed(2)}× (blur ${s.blur.toFixed(2)} D)`);

  m.native.distanceCm = 70; step();
  s = await send({ type: 'vf:tick' });
  assert(near(s.scale, expect(m.native.settings.rx, 70), 1e-12), `70 cm (got ${s.scale})`);
  console.log(`✓ live 70 cm → ${s.scale.toFixed(2)}×`);

  const throttled = m.native.calls.length; await send({ type: 'vf:tick' });
  assert.strictEqual(m.native.calls.length, throttled, 'native polls are throttled (~450 ms)');
  console.log('✓ native polling throttled to one call per ~450 ms across tabs');

  m.native.faceFound = false; step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'noFace'); assert.strictEqual(s.source, 'held'); assert.strictEqual(s.distanceCm, 70);
  console.log('✓ no face → holds last live distance (70 cm)');

  m.native.faceFound = true; m.native.liveAgeMs = 3500; step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'stale'); assert.strictEqual(s.source, 'held');
  console.log('✓ data older than 3 s → stale, holds last distance');

  await send({ type: 'vf:setPrefs', fallback: 'manual', manualCm: 40 }); step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.source, 'manual'); assert.strictEqual(s.distanceCm, 40);
  console.log(`✓ fallback "manual" → popup distance 40 cm → ${s.scale.toFixed(2)}×`);

  m.native.appRunning = false; m.native.tracking = false; step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'notRunning');
  console.log('✓ heartbeat gone → "Companion app not running"');

  m.native.reachable = false; step(6000);
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'unreachable'); assert(s.nativeError);
  assert.strictEqual(s.source, 'manual');
  console.log('✓ native handler unreachable → manual distance, error surfaced');

  m.native.reachable = true; m.native.appRunning = true; m.native.tracking = true; m.native.liveAgeMs = 100; m.native.distanceCm = 50;
  await send({ type: 'vf:setPrefs', fallback: 'hold' }); step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.status, 'live');
  const e0 = s.epoch;
  s = await send({ type: 'vf:setPrefs', site: 'example.com', siteEnabled: false });
  assert.strictEqual(s.active, false); assert.strictEqual(s.scale, 1); assert(s.epoch > e0, 'epoch bumps on change');
  const other = await m.cs.runtime.sendMessage({ type: 'vf:tick', host: 'other.org' });
  assert.strictEqual(other.active, true);
  s = await send({ type: 'vf:setPrefs', site: 'example.com', siteEnabled: true });
  assert.strictEqual(s.active, true);
  console.log('✓ per-site disable (only that host), epoch bump forces immediate apply');

  s = await send({ type: 'vf:setShared', paused: true });
  assert.strictEqual(s.paused, true); assert.strictEqual(s.scale, 1); assert.strictEqual(m.native.settings.paused, true);
  s = await send({ type: 'vf:setShared', paused: false });
  s = await send({ type: 'vf:setShared', comfort: 0.8 });
  assert.strictEqual(m.native.settings.comfort, 0.8); assert(near(s.scale, expect(m.native.settings.rx, 50, 0.8), 1e-12), `comfort 80% at 50 cm (got ${s.scale})`);
  s = await send({ type: 'vf:setShared', comfort: 5 });
  assert.strictEqual(m.native.settings.comfort, 1.6, 'comfort clamped to 160%');
  await send({ type: 'vf:setShared', comfort: 1 });
  console.log('✓ pause + comfort go to the native app (shared), comfort clamped 70–160%');

  m.native.settings.rx.wearing = false; m.native.distanceCm = 30; step();
  s = await send({ type: 'vf:tick' });
  assert.strictEqual(s.scale, 2.5, 'zoom mode capped at 2.5x');
  s = await send({ type: 'vf:setPrefs', mode: 'font' });
  assert.strictEqual(s.mode, 'font'); assert.strictEqual(s.scale, 3.0, 'font mode default cap 3.0x');
  s = await send({ type: 'vf:setPrefs', fontCap: 9 });
  assert.strictEqual(s.fontCap, 4, 'cap clamped to 4x');
  console.log('✓ no glasses at 30 cm: zoom capped 2.5×, text-only capped 3.0×, caps clamp at 4×');

  assert.deepStrictEqual(Object.keys(m.store), ['prefs']);
  console.log('\nAll extension background checks passed.');
})().catch(e => { console.error('✗', e.message); process.exit(1); });
