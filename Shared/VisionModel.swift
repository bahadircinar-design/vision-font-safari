//  VisionModel.swift — Vision Font
//  Line-for-line Swift port of model.js (the web app's font-size model) plus the page-scale mapping
//  from Extension/Resources/scale.js. Pure Foundation, no UI: it also compiles on Linux for
//  Tests/ModelCheck, which compares it against Tests/vectors.json (generated from the JS model).
//  NOT A MEDICAL DEVICE. All values are approximate rules of thumb.

import Foundation

// MARK: - Prescription types (lens values only; never names, dates of birth or clinic details)

public enum LensType: String, Codable, CaseIterable, Identifiable {
    case none, single, progressive, bifocal
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "No glasses"
        case .single: return "Single vision"
        case .progressive: return "Progressive"
        case .bifocal: return "Bifocal"
        }
    }
}

public struct EyeRx: Codable, Equatable {
    public var sph: Double
    public var cyl: Double
    public var axis: Double?          // blank when there is no cylinder
    public var add: Double

    public init(sph: Double = 0, cyl: Double = 0, axis: Double? = nil, add: Double = 0) {
        self.sph = sph; self.cyl = cyl; self.axis = axis; self.add = add
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sph = (try? c.decodeIfPresent(Double.self, forKey: .sph)) ?? 0
        cyl = (try? c.decodeIfPresent(Double.self, forKey: .cyl)) ?? 0
        axis = (try? c.decodeIfPresent(Double.self, forKey: .axis)) ?? nil
        add = (try? c.decodeIfPresent(Double.self, forKey: .add)) ?? 0
    }
}

public struct Prescription: Codable, Equatable {
    public var od: EyeRx
    public var os: EyeRx
    public var age: Double
    public var wearing: Bool
    public var lens: LensType
    public var pdFar: Double?         // binocular distance PD (mm)
    public var pdNear: Double?        // binocular near PD (mm) — used for camera distance

    public init(od: EyeRx, os: EyeRx, age: Double, wearing: Bool, lens: LensType, pdFar: Double?, pdNear: Double?) {
        self.od = od; self.os = os; self.age = age; self.wearing = wearing; self.lens = lens; self.pdFar = pdFar; self.pdNear = pdNear
    }

    /// Neutral example default used until the user enters their own Rx in Settings. Must equal scale.js defaultRx().
    public static let `default` = Prescription(
        od: EyeRx(sph: 0, cyl: 0, axis: nil, add: 0),
        os: EyeRx(sph: 0, cyl: 0, axis: nil, add: 0),
        age: 45, wearing: false, lens: .single, pdFar: 66.0, pdNear: 63.0)

    /// Lens type "none" means no correction is worn, whatever the toggle says (same as scale.js effectiveRx).
    public var effectiveWearing: Bool { wearing && lens != .none }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Prescription.default
        od = (try? c.decodeIfPresent(EyeRx.self, forKey: .od)) ?? d.od
        os = (try? c.decodeIfPresent(EyeRx.self, forKey: .os)) ?? d.os
        age = (try? c.decodeIfPresent(Double.self, forKey: .age)) ?? d.age
        wearing = (try? c.decodeIfPresent(Bool.self, forKey: .wearing)) ?? d.wearing
        lens = (try? c.decodeIfPresent(LensType.self, forKey: .lens)) ?? .single
        pdFar = (try? c.decodeIfPresent(Double.self, forKey: .pdFar)) ?? nil
        pdNear = (try? c.decodeIfPresent(Double.self, forKey: .pdNear)) ?? nil
    }
}

// MARK: - Model (port of model.js)

public enum VisionModel {
    public enum C {
        public static let IRIS_MM = 11.7
        public static let X_HEIGHT_DEG = 0.25
        public static let X_HEIGHT_RATIO = 0.52
        public static let CSS_PX_PER_MM = 96.0 / 25.4
        public static let DEPTH_OF_FOCUS_D = 0.25
        public static let DIOPTERS_PER_LINE = 0.4
        public static let MAX_ENLARGE = 4.0
        public static let MIN_PX = 12.0
        public static let MAX_PX = 96.0
        public static let NEAR_REF_D = 2.5
    }

    @inline(__always) static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
    @inline(__always) static func num(_ v: Double?, _ d: Double = 0) -> Double { if let v = v, v.isFinite { return v }; return d }

    /// Hofstetter's average amplitude of accommodation (D).
    public static func amplitudeFromAge(_ age: Double?) -> Double { max(0, 18.5 - 0.3 * num(age, 40)) }

    public static func meanAdd(_ rx: Prescription) -> Double {
        let adds = [rx.od.add, rx.os.add].map { num($0) }.filter { $0 > 0 }
        return adds.isEmpty ? 0 : adds.reduce(0, +) / Double(adds.count)
    }

    /// `wearing` here is the model input (use Prescription.effectiveWearing — see compute).
    public static func hasNearZone(_ rx: Prescription, wearing: Bool) -> Bool {
        wearing && (rx.lens == .progressive || rx.lens == .bifocal) && meanAdd(rx) > 0
    }

    public struct Accommodation { public let value: Double; public let source: String }
    public static func usableAccommodation(_ rx: Prescription, wearing: Bool) -> Accommodation {
        let fromAge = amplitudeFromAge(rx.age) / 2
        let add = meanAdd(rx)
        var value = fromAge, source = "age"
        if add > 0 { value = min(fromAge, max(0, C.NEAR_REF_D - add)); source = "add" }
        if hasNearZone(rx, wearing: wearing) { value += add; source = "add+lens" }
        return Accommodation(value: value, source: source)
    }

    public static func sphericalEquivalent(_ eye: EyeRx) -> Double { num(eye.sph) + num(eye.cyl) / 2 }

    public static func eyeBlur(_ eye: EyeRx, _ dM: Double, _ A: Double, _ wearing: Bool) -> Double {
        let R = wearing ? 0 : sphericalEquivalent(eye)
        let cyl = wearing ? 0 : num(eye.cyl)
        let needed = 1 / dM + R
        var sph = 0.0
        if needed < 0 { sph = -needed } else if needed > A { sph = needed - A }
        return (sph * sph + (cyl / 2) * (cyl / 2)).squareRoot()
    }

    public static func basePx(_ dCm: Double, pxPerMm: Double = C.CSS_PX_PER_MM) -> Double {
        let xMm = 2 * dCm * 10 * tan((C.X_HEIGHT_DEG * Double.pi) / 360)
        return (xMm / C.X_HEIGHT_RATIO) * pxPerMm
    }

    public static func enlargementFromBlur(_ blurD: Double) -> Double {
        let eff = max(0, blurD - C.DEPTH_OF_FOCUS_D)
        return clamp(pow(10, 0.1 * (eff / C.DIOPTERS_PER_LINE)), 1, C.MAX_ENLARGE)
    }

    public struct Result {
        public let distanceCm, base, enlarge, comfort, blur, blurOD, blurOS, accommodation, amplitude, px: Double
        public let accommodationSource: String
        public let clamped: Bool
        public let betterEye: String
    }

    /// Same as model.js compute(rx, dCm, {pxPerMm, comfort}). The rx's `wearing` is taken from effectiveWearing
    /// (identical to scale.js effectiveRx; for lens != none this is exactly rx.wearing as in model.js).
    public static func compute(_ rx: Prescription, _ dCm: Double?, pxPerMm: Double? = nil, comfort: Double? = nil) -> Result {
        let ppm = num(pxPerMm, C.CSS_PX_PER_MM) == 0 ? C.CSS_PX_PER_MM : num(pxPerMm, C.CSS_PX_PER_MM)
        let cf = num(comfort, 1) == 0 ? 1 : num(comfort, 1)
        let d = clamp(num(dCm, 50), 15, 300)
        let wearing = rx.effectiveWearing
        let acc = usableAccommodation(rx, wearing: wearing)
        let bOD = eyeBlur(rx.od, d / 100, acc.value, wearing)
        let bOS = eyeBlur(rx.os, d / 100, acc.value, wearing)
        let blur = min(bOD, bOS)
        let base = basePx(d, pxPerMm: ppm)
        let enlarge = enlargementFromBlur(blur)
        let raw = base * enlarge * cf
        let px = clamp(raw, C.MIN_PX, C.MAX_PX)
        return Result(distanceCm: d, base: base, enlarge: enlarge, comfort: cf, blur: blur, blurOD: bOD, blurOS: bOS,
                      accommodation: acc.value, amplitude: amplitudeFromAge(rx.age), px: px,
                      accommodationSource: acc.source, clamped: px != raw, betterEye: bOD <= bOS ? "OD" : "OS")
    }

    public struct ClearRange { public let min: Int?; public let max: Int?; public let best: Int?; public let bestBlur: Double? }
    public static func clearRange(_ rx: Prescription) -> ClearRange {
        var ok: [Int] = []
        for d in 20...200 where compute(rx, Double(d)).blur <= C.DEPTH_OF_FOCUS_D { ok.append(d) }
        if ok.isEmpty {
            var best = 20, bestB = Double.infinity
            for d in 20...200 { let b = compute(rx, Double(d)).blur; if b < bestB { bestB = b; best = d } }
            return ClearRange(min: nil, max: nil, best: best, bestBlur: bestB)
        }
        return ClearRange(min: ok.first, max: ok.last, best: nil, bestBlur: nil)
    }

    public static func distanceFromIris(_ irisPx: Double, _ focalPx: Double) -> Double? {
        guard irisPx > 0 else { return nil }
        return (focalPx * C.IRIS_MM) / irisPx / 10
    }
    public static func focalFromFov(_ widthPx: Double, _ hfovDeg: Double) -> Double {
        widthPx / 2 / tan((hfovDeg * Double.pi) / 360)
    }
    public static func focalFromKnownDistance(_ irisPx: Double, _ knownCm: Double) -> Double {
        (irisPx * knownCm * 10) / C.IRIS_MM
    }
}

// MARK: - Page scale (port of scale.js)

public enum PageScale {
    public static let BASELINE_PX = 16.0
    public static let MIN_SCALE = 1.0
    public static let DEFAULT_ZOOM_CAP = 2.5
    public static let DEFAULT_FONT_CAP = 3.0
    public static let MAX_CAP = 4.0
    public static let STALE_MS = 3000.0
    public static let DEADBAND = 0.05

    public struct Result { public let model: VisionModel.Result; public let rawScale: Double; public let scale: Double; public let cap: Double }

    public static func compute(_ rx: Prescription, distanceCm: Double, pxPerMm: Double?, comfort: Double?, cap: Double? = nil) -> Result {
        let c = VisionModel.clamp(VisionModel.num(cap, DEFAULT_ZOOM_CAP), MIN_SCALE, MAX_CAP)
        let ppm = VisionModel.num(pxPerMm, 0) > 0 ? pxPerMm! : VisionModel.C.CSS_PX_PER_MM
        let r = VisionModel.compute(rx, distanceCm, pxPerMm: ppm, comfort: VisionModel.num(comfort, 1))
        let raw = r.px / BASELINE_PX
        return Result(model: r, rawScale: raw, scale: VisionModel.clamp(raw, MIN_SCALE, c), cap: c)
    }

    public static func passesDeadband(applied: Double, target: Double, band: Double = DEADBAND) -> Bool {
        guard applied > 0 else { return true }
        return abs(target - applied) / applied >= band
    }
}
