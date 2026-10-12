/*
 * Vision Font (Safari) — page-scale mapping on top of the unchanged web-app model (model.js).
 *
 * model.js answers "what font size (CSS px) should body text be at this distance for these eyes?".
 * Web pages are designed for ~16 CSS px body text, so the page scale is
 *     scale = clamp(model px / 16, 1.0, cap)
 * 1.0 = leave the page alone (we never shrink pages). cap defaults to 2.5x (zoom) / 3.0x (text-only).
 *
 * The Swift port (Shared/VisionModel.swift, PageScale) must produce the same numbers:
 * see Tests/vectors.json, checked by Tests/test-model.js (node) and Tests/ModelCheck (swift).
 * NOT A MEDICAL DEVICE.
 */
(function (root) {
  'use strict';
  const M = root.VisionModel || (typeof require === 'function' ? require('./model.js') : null);
  if (!M) throw new Error('scale.js needs model.js loaded first');

  const S = Object.freeze({
    BASELINE_PX: 16,          // typical designed body-text size on the web (CSS px)
    MIN_SCALE: 1.0,
    DEFAULT_ZOOM_CAP: 2.5,
    DEFAULT_FONT_CAP: 3.0,
    MAX_CAP: 4.0,
    STALE_MS: 3000,           // companion data older than this is treated as stale
    DEADBAND: 0.05,           // ignore live changes under 5%
  });

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const fin = (v, d) => (typeof v === 'number' && Number.isFinite(v) ? v : d);

  /** Default prescription (lens values only, no personal details). Must equal Swift Prescription.default. */
  function defaultRx() {
    return {
      od: { sph: 0, cyl: 0, axis: null, add: 0 },
      os: { sph: 0, cyl: 0, axis: null, add: 0 },
      age: 45, wearing: false, lens: 'single', pdFar: 66.0, pdNear: 63.0,
    };
  }
  function defaultSettings() {
    return { rx: defaultRx(), comfort: 1, pxPerMm: null, pxPerMmSource: 'default', paused: false, updatedAt: 0 };
  }

  /** The rx object passed to model.js: lens 'none' means no glasses, whatever the toggle says. */
  function effectiveRx(rx) {
    const r = rx || defaultRx();
    const lens = r.lens || 'single';
    return { ...r, lens, wearing: !!r.wearing && lens !== 'none' };
  }

  /**
   * opts = { pxPerMm, comfort, cap }
   * returns model.compute() fields + { rawScale, scale, cap }
   */
  function pageScale(rx, distanceCm, opts = {}) {
    const cap = clamp(fin(opts.cap, S.DEFAULT_ZOOM_CAP), S.MIN_SCALE, S.MAX_CAP);
    const pxPerMm = fin(opts.pxPerMm, 0) > 0 ? opts.pxPerMm : M.C.CSS_PX_PER_MM;
    const comfort = fin(opts.comfort, 1);
    const r = M.compute(effectiveRx(rx), distanceCm, { pxPerMm, comfort });
    const rawScale = r.px / S.BASELINE_PX;
    return { ...r, rawScale, scale: clamp(rawScale, S.MIN_SCALE, cap), cap, pxPerMm };
  }

  /** Hysteresis: should a live change from `applied` to `target` be applied? */
  function passesDeadband(applied, target, band = S.DEADBAND) {
    if (!(applied > 0)) return true;
    return Math.abs(target - applied) / applied >= band;
  }

  const api = { S, defaultRx, defaultSettings, effectiveRx, pageScale, passesDeadband };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.VisionScale = api;
})(typeof window !== 'undefined' ? window : globalThis);
