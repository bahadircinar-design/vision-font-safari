//  DistanceEstimator.swift — Vision Font
//  Camera distance from the pixel distance between the pupils (pinhole model), plus smoothing.
//  Pure Foundation (compiles on Linux for Tests/ModelCheck).
//
//      Z = f_px × PD_mm ÷ ipd_px          (PD = the user's real binocular near PD, default 63 mm)
//      calibration at a known distance:  f_px = ipd_px × Z_mm ÷ PD_mm
//  The focal length is stored normalised by frame width (fNorm = f_px / width) so it doesn't depend
//  on the capture resolution. Uncalibrated, we assume a 60° horizontal field of view.

import Foundation

public enum DistanceMath {
    public static let defaultHFOVDeg = 60.0
    public static let defaultNearPDmm = 63.0

    public static func defaultFocalNorm(hfovDeg: Double = defaultHFOVDeg) -> Double {
        0.5 / tan(hfovDeg * Double.pi / 360)
    }
    /// Distance in cm, or nil for impossible input.
    public static func distanceCm(ipdPx: Double, imageWidthPx: Double, focalNorm: Double, pdMm: Double) -> Double? {
        guard ipdPx > 0, imageWidthPx > 0, focalNorm > 0, pdMm > 0 else { return nil }
        return focalNorm * imageWidthPx * pdMm / ipdPx / 10
    }
    /// Normalised focal length from a measurement at a known distance.
    public static func focalNorm(ipdPx: Double, imageWidthPx: Double, knownCm: Double, pdMm: Double) -> Double? {
        guard ipdPx > 0, imageWidthPx > 0, knownCm > 0, pdMm > 0 else { return nil }
        return ipdPx * knownCm * 10 / pdMm / imageWidthPx
    }
    /// Equivalent horizontal field of view (degrees) of a normalised focal length.
    public static func hfovDeg(focalNorm: Double) -> Double { 2 * atan(0.5 / focalNorm) * 180 / Double.pi }
}

/// Median-of-N then exponential moving average. Reports "no face" after `noFaceAfter` seconds without a face.
public struct DistanceFilter {
    public var window: Int
    public var alpha: Double
    public var noFaceAfter: TimeInterval
    public private(set) var recent: [Double] = []
    public private(set) var smoothed: Double?
    public private(set) var lastFaceTime: TimeInterval?

    public init(window: Int = 5, alpha: Double = 0.35, noFaceAfter: TimeInterval = 1.0) {
        self.window = max(1, window); self.alpha = alpha; self.noFaceAfter = noFaceAfter
    }

    /// Feed a raw reading (cm) at time t (seconds). Returns the smoothed distance.
    @discardableResult
    public mutating func add(_ cm: Double, at t: TimeInterval) -> Double {
        // after a long gap, restart instead of easing in from an old value
        if let last = lastFaceTime, t - last > 2 * noFaceAfter { recent.removeAll(); smoothed = nil }
        recent.append(cm)
        if recent.count > window { recent.removeFirst(recent.count - window) }
        let sorted = recent.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        smoothed = smoothed.map { $0 + alpha * (median - $0) } ?? median
        lastFaceTime = t
        return smoothed!
    }

    public func faceFound(at t: TimeInterval) -> Bool {
        guard let last = lastFaceTime else { return false }
        return t - last <= noFaceAfter
    }

    /// Jump straight to a value (used right after calibration).
    public mutating func reset(to cm: Double? = nil, at t: TimeInterval? = nil) {
        recent = cm.map { [$0] } ?? []
        smoothed = cm
        lastFaceTime = cm == nil ? nil : t
    }
}
