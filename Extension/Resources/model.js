/*
 * Vision Font — font-size model (pure functions, no DOM).
 * Works in the browser (window.VisionModel) and in Node (module.exports).
 *
 * NOT A MEDICAL DEVICE. All values are approximate rules of thumb.
 */
(function (root) {
  'use strict';

  const C = Object.freeze({
    IRIS_MM: 11.7,             // average human visible iris diameter (HVID)
    X_HEIGHT_DEG: 0.25,        // target x-height visual angle (~3x reserve over 20/20 letter detail)
    X_HEIGHT_RATIO: 0.52,      // x-height / font-size for typical system UI fonts (SF Pro, Helvetica)
    CSS_PX_PER_MM: 96 / 25.4,  // CSS reference pixel (96 per inch) unless the user calibrates
    DEPTH_OF_FOCUS_D: 0.25,    // blur the eye tolerates without noticing (approx. +/-0.25 D)
    DIOPTERS_PER_LINE: 0.4,    // ~1 logMAR line (x1.259) of acuity lost per 0.4 D of residual blur
    MAX_ENLARGE: 4,            // cap on blur enlargement
    MIN_PX: 12,
    MAX_PX: 96,
    NEAR_REF_D: 2.5,           // ADD is usually prescribed for ~40 cm (2.5 D demand)
  });

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const num = (v, d = 0) => (Number.isFinite(+v) ? +v : d);

  /** Hofstetter's average amplitude of accommodation (D). */
  function amplitudeFromAge(age) {
    return Math.max(0, 18.5 - 0.3 * num(age, 40));
  }

  /**
   * Comfortable accommodation (D) the user can sustain while reading.
   * Rule: use half of the amplitude. If an ADD is given we trust it more than age:
   * an ADD is prescribed so that (40 cm demand - ADD) is what the eye can still do
   * comfortably, so usable = 2.5 - ADD.
   */
  function meanAdd(rx) {
    const adds = [rx.od, rx.os].map(e => num(e && e.add)).filter(a => a > 0);
    return adds.length ? adds.reduce((a, b) => a + b, 0) / adds.length : 0;
  }
  /** True when the user is wearing progressive / bifocal lenses whose near zone supplies the ADD. */
  function hasNearZone(rx) {
    return !!rx.wearing && (rx.lens === 'progressive' || rx.lens === 'bifocal') && meanAdd(rx) > 0;
  }
  function usableAccommodation(rx) {
    const fromAge = amplitudeFromAge(rx.age) / 2;
    const add = meanAdd(rx);
    let value = fromAge, source = 'age';
    if (add > 0) { value = Math.min(fromAge, Math.max(0, C.NEAR_REF_D - add)); source = 'add'; }
    // Progressive / bifocal near zone: lens adds up to ADD diopters of near focus on top of the eye's own.
    if (hasNearZone(rx)) { value += add; source = 'add+lens'; }
    return { value, source };
  }

  /** Spherical equivalent of one eye. */
  function sphericalEquivalent(eye) {
    return num(eye && eye.sph) + num(eye && eye.cyl) / 2;
  }

  /**
   * Residual blur (D) for one eye at distance dM (metres).
   *  - refraction R = spherical equivalent (myopia negative, hyperopia positive)
   *  - demand D = 1/d; accommodation needed = D + R
   *  - the eye can supply 0..A (A = usable accommodation)
   *  - needed < 0  -> beyond the myopic far point (can't relax further): blur = -needed
   *  - needed > A  -> not enough accommodation (presbyopia / hyperopia): blur = needed - A
   *  - astigmatism adds blur that accommodation can't fix: combine as sqrt(M^2 + (C/2)^2)
   *    (power-vector blur strength; axis does not change the magnitude)
   */
  function eyeBlur(eye, dM, A, wearing) {
    const R = wearing ? 0 : sphericalEquivalent(eye);
    const cyl = wearing ? 0 : num(eye && eye.cyl);
    const needed = 1 / dM + R;
    let sph = 0;
    if (needed < 0) sph = -needed;
    else if (needed > A) sph = needed - A;
    return Math.sqrt(sph * sph + (cyl / 2) * (cyl / 2));
  }

  /** Base CSS px so that the x-height subtends X_HEIGHT_DEG at distance dCm. */
  function basePx(dCm, pxPerMm = C.CSS_PX_PER_MM) {
    const xMm = 2 * dCm * 10 * Math.tan((C.X_HEIGHT_DEG * Math.PI) / 360);
    return (xMm / C.X_HEIGHT_RATIO) * pxPerMm;
  }

  /** Enlargement from residual blur: 1 logMAR line per DIOPTERS_PER_LINE beyond depth of focus. */
  function enlargementFromBlur(blurD) {
    const eff = Math.max(0, blurD - C.DEPTH_OF_FOCUS_D);
    return clamp(Math.pow(10, 0.1 * (eff / C.DIOPTERS_PER_LINE)), 1, C.MAX_ENLARGE);
  }

  /**
   * Full model.
   * rx = { od:{sph,cyl,axis,add}, os:{...}, age, wearing, lens: 'single'|'progressive'|'bifocal' }
 *  wearing = distance correction on (SPH/CYL neutralised); with progressive/bifocal the ADD is also
 *  available for near (modelled as extra accommodation, i.e. the near zone at full ADD).
   * opts = { pxPerMm, comfort (multiplier, default 1) }
   */
  function compute(rx, dCm, opts = {}) {
    const pxPerMm = num(opts.pxPerMm, C.CSS_PX_PER_MM) || C.CSS_PX_PER_MM;
    const comfort = num(opts.comfort, 1) || 1;
    const d = clamp(num(dCm, 50), 15, 300);
    const acc = usableAccommodation(rx);
    const blurOD = eyeBlur(rx.od, d / 100, acc.value, !!rx.wearing);
    const blurOS = eyeBlur(rx.os, d / 100, acc.value, !!rx.wearing);
    const blur = Math.min(blurOD, blurOS);           // binocular reading ~ better eye
    const base = basePx(d, pxPerMm);
    const enlarge = enlargementFromBlur(blur);
    const raw = base * enlarge * comfort;
    const px = clamp(raw, C.MIN_PX, C.MAX_PX);
    return {
      distanceCm: d, base, enlarge, comfort, blur, blurOD, blurOS,
      accommodation: acc.value, accommodationSource: acc.source,
      amplitude: amplitudeFromAge(rx.age), px, clamped: px !== raw,
      betterEye: blurOD <= blurOS ? 'OD' : 'OS',
    };
  }

  /** Distance range (cm) where blur stays within depth of focus, scanning 20–200 cm. */
  function clearRange(rx) {
    const ok = [];
    for (let d = 20; d <= 200; d += 1) {
      const r = compute(rx, d);
      if (r.blur <= C.DEPTH_OF_FOCUS_D) ok.push(d);
    }
    if (!ok.length) {
      let best = 20, bestB = Infinity;
      for (let d = 20; d <= 200; d++) { const b = compute(rx, d).blur; if (b < bestB) { bestB = b; best = d; } }
      return { min: null, max: null, best, bestBlur: bestB };
    }
    return { min: ok[0], max: ok[ok.length - 1], best: null };
  }

  /** Distance from iris diameter in pixels: Z = f * 11.7 mm / irisPx. Returns cm. */
  function distanceFromIris(irisPx, focalPx) {
    if (!(irisPx > 0)) return null;
    return (focalPx * C.IRIS_MM) / irisPx / 10;
  }
  /** Focal length (px) from a frame width and an assumed horizontal field of view. */
  function focalFromFov(widthPx, hfovDeg) {
    return widthPx / 2 / Math.tan((hfovDeg * Math.PI) / 360);
  }
  /** Calibrate focal length from iris px measured at a known distance (cm). */
  function focalFromKnownDistance(irisPx, knownCm) {
    return (irisPx * knownCm * 10) / C.IRIS_MM;
  }

  const api = { C, meanAdd, hasNearZone, amplitudeFromAge, usableAccommodation, sphericalEquivalent, eyeBlur, basePx,
    enlargementFromBlur, compute, clearRange, distanceFromIris, focalFromFov, focalFromKnownDistance };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.VisionModel = api;
})(typeof window !== 'undefined' ? window : globalThis);
