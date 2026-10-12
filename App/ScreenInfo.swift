//  ScreenInfo.swift — Vision Font
//  Auto-detects how many points (= CSS px in Safari at 100% page zoom) fit in a millimetre on the screen.
//  Physical size from CGDisplayScreenSize, logical width from NSScreen. Prefers the built-in display.

import AppKit
import CoreGraphics

struct ScreenInfo: Equatable {
    let name: String
    let pointsWide: Double
    let pixelsWide: Double
    let mmWide: Double
    let backingScale: Double
    let builtIn: Bool

    /// Points per mm, or nil when macOS doesn't report a physical size (some projectors / TVs).
    var pointsPerMm: Double? { mmWide > 10 ? pointsWide / mmWide : nil }
    var pointsPerInch: Double? { pointsPerMm.map { $0 * 25.4 } }
    var pixelsPerInch: Double? { pointsPerInch.map { $0 * backingScale } }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func info(for screen: NSScreen) -> ScreenInfo? {
        guard let id = displayID(screen) else { return nil }
        let mm = CGDisplayScreenSize(id)  // millimetres
        let scale = Double(screen.backingScaleFactor)
        return ScreenInfo(name: screen.localizedName,
                          pointsWide: Double(screen.frame.width),
                          pixelsWide: Double(screen.frame.width) * scale,
                          mmWide: Double(mm.width),
                          backingScale: scale,
                          builtIn: CGDisplayIsBuiltin(id) != 0)
    }

    /// The built-in display if there is one, otherwise the main screen.
    static func preferred() -> ScreenInfo? {
        let all = NSScreen.screens.compactMap(info(for:))
        return all.first(where: { $0.builtIn && $0.pointsPerMm != nil }) ?? NSScreen.main.flatMap(info(for:)) ?? all.first
    }
}
