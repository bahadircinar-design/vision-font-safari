//  AppModel.swift — Vision Font
//  Owns the camera tracker, the smoothing filter, the settings, and the shared store the Safari extension reads.

import AppKit
import Combine
import Foundation
import SafariServices

@MainActor
final class AppModel: ObservableObject {
    /// The embedded extension's bundle id (app id + ".Extension"), so it still works if the ids are changed in Xcode.
    static let extensionBundleID = (Bundle.main.bundleIdentifier ?? "com.bahacinar.VisionFont") + ".Extension"

    enum Calibration: Equatable {
        case idle
        case countdown(Int)
        case measuring
        case done(String)
        case failed(String)
    }

    // MARK: published state
    @Published var settings: VFSettings { didSet { settingsDidChange(oldValue) } }
    @Published private(set) var tracking = false
    @Published private(set) var distanceCm: Double?
    @Published private(set) var faceFound = false
    @Published private(set) var lastIpdPx: Double?
    @Published private(set) var cameraError: String?
    @Published private(set) var calibration: Calibration = .idle
    @Published private(set) var storeStatus = "Not written yet"
    @Published private(set) var storeOK = false
    @Published private(set) var screen: ScreenInfo?
    @Published private(set) var extensionEnabled: Bool?
    @Published var loginError: String?

    // MARK: private
    private let tracker = DistanceTracker()
    private var filter = DistanceFilter(window: 5, alpha: 0.35, noFaceAfter: 1.0)
    private let store = SharedStore()
    private var settingsUpdatedAt: Double
    private var adopting = false
    private var lastFrameMs: Double = 0
    private var lastStateWrite: Double = 0
    private var calibrationSamples: [Double]?    // ipd / frame width
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?

    private enum Keys { static let settings = "vf.settings.v1", updatedAt = "vf.settings.updatedAt", tracking = "vf.tracking", onboarded = "vf.onboarded" }

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Keys.settings), let s = try? JSONDecoder().decode(VFSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
        }
        settingsUpdatedAt = d.double(forKey: Keys.updatedAt)
        screen = ScreenInfo.preferred()
        // First run (or never calibrated with a card): use the detected screen size.
        if settings.pxPerMmSource != "card", let ppm = screen?.pointsPerMm {
            adopting = true; settings.pxPerMm = ppm; settings.pxPerMmSource = "detected"; adopting = false
        }

        tracker.onSample = { [weak self] s in self?.handle(s) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenChanged() }
        }
        let wantsTracking = d.object(forKey: Keys.tracking) as? Bool ?? true
        if wantsTracking { setTracking(true) }
        writeState(force: true)
        refreshExtensionState()
    }

    var isFirstLaunch: Bool { !UserDefaults.standard.bool(forKey: Keys.onboarded) }
    func markOnboarded() { UserDefaults.standard.set(true, forKey: Keys.onboarded) }

    // MARK: derived values

    var focalNorm: Double { settings.focalNorm ?? DistanceMath.defaultFocalNorm() }
    var pdMm: Double { settings.rx.pdNear ?? DistanceMath.defaultNearPDmm }
    var isCalibrated: Bool { settings.focalNorm != nil }

    /// Scale the extension will apply in zoom mode at the current (or last) distance.
    var currentScale: PageScale.Result? {
        guard let d = distanceCm else { return nil }
        return PageScale.compute(settings.rx, distanceCm: d, pxPerMm: settings.pxPerMm, comfort: settings.comfort, cap: PageScale.DEFAULT_ZOOM_CAP)
    }

    var menuTitle: String {
        var t: String
        if !tracking { t = "Eye off" }
        else if faceFound, let d = distanceCm { t = "Eye \(Int(d.rounded())) cm" }
        else { t = "Eye –" }
        if settings.paused { t += " ⏸" }
        return t
    }

    // MARK: tracking

    func setTracking(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Keys.tracking)
        if !on {
            tracker.stop(); tracking = false; faceFound = false
            if isCalibrating { calibration = .failed("Tracking was turned off.") }
            writeState(force: true); return
        }
        cameraError = nil
        DistanceTracker.requestAccess { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.cameraError = DistanceTracker.TrackerError.denied.localizedDescription
                    self.tracking = false; self.writeState(force: true); return
                }
                do { try self.tracker.start(); self.tracking = true }
                catch { self.cameraError = error.localizedDescription; self.tracking = false }
                self.writeState(force: true)
            }
        }
    }

    private func handle(_ s: DistanceTracker.Sample) {
        guard tracking else { return }
        lastFrameMs = nowMs()
        if let ipd = s.ipdPx {
            lastIpdPx = ipd
            calibrationSamples?.append(ipd / s.imageWidth)
            if let d = DistanceMath.distanceCm(ipdPx: ipd, imageWidthPx: s.imageWidth, focalNorm: focalNorm, pdMm: pdMm), (15...300).contains(d) {
                distanceCm = filter.add(d, at: s.time)
            }
        }
        let found = filter.faceFound(at: s.time)
        if found != faceFound { faceFound = found }
    }

    // MARK: calibration ("Measure at 50 cm")

    var isCalibrating: Bool {
        switch calibration {
        case .countdown, .measuring: return true
        default: return false
        }
    }

    func startCalibration() {
        guard !isCalibrating else { return }
        if !tracking { setTracking(true) }
        Task { @MainActor in
            for n in stride(from: 3, through: 1, by: -1) {
                calibration = .countdown(n)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !tracking && cameraError != nil { calibration = .failed(cameraError ?? "Camera unavailable."); return }
            }
            calibration = .measuring
            calibrationSamples = []
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let samples = (calibrationSamples ?? []).sorted()
            calibrationSamples = nil
            guard samples.count >= 8 else {
                calibration = .failed("Couldn't see both eyes clearly (\(samples.count) good frames). Face the camera in good light and try again.")
                return
            }
            let median = samples[samples.count / 2]
            let cm = settings.calibrationCm
            guard let f = DistanceMath.focalNorm(ipdPx: median, imageWidthPx: 1, knownCm: cm, pdMm: pdMm) else {
                calibration = .failed("Calibration failed."); return
            }
            settings.focalNorm = f
            filter.reset(to: cm, at: ProcessInfo.processInfo.systemUptime)
            distanceCm = cm
            let fov = DistanceMath.hfovDeg(focalNorm: f)
            calibration = .done(String(format: "Calibrated at %.0f cm (%ld frames, camera field of view ≈ %.0f°).", cm, samples.count, fov))
        }
    }

    func resetCameraCalibration() { settings.focalNorm = nil; calibration = .idle }

    // MARK: screen size

    func useDetectedScreen() {
        screen = ScreenInfo.preferred()
        if let ppm = screen?.pointsPerMm { settings.pxPerMm = ppm; settings.pxPerMmSource = "detected" }
        else { settings.pxPerMm = nil; settings.pxPerMmSource = "default" }
    }
    func setCardMatch(pointsPerMm: Double) {
        settings.pxPerMm = min(12, max(2, pointsPerMm)); settings.pxPerMmSource = "card"
    }
    private func screenChanged() {
        screen = ScreenInfo.preferred()
        if settings.pxPerMmSource == "detected", let ppm = screen?.pointsPerMm { settings.pxPerMm = ppm }
    }

    func resetAllSettings() {
        settings = .default
        useDetectedScreen()
        calibration = .idle
    }

    // MARK: Safari extension

    func refreshExtensionState() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.extensionBundleID) { state, _ in
            let on = state?.isEnabled
            Task { @MainActor [weak self] in self?.extensionEnabled = on }
        }
    }
    func openSafariExtensionSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionBundleID) { _ in }
    }

    // MARK: login item

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set { loginError = LoginItem.set(newValue); objectWillChange.send() }
    }

    // MARK: persistence + shared store

    private func settingsDidChange(_ old: VFSettings) {
        guard settings != old else { return }
        if !adopting { settingsUpdatedAt = nowMs() }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.persist() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func persist() {
        var s = settings; s.updatedAt = settingsUpdatedAt
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Keys.settings) }
        UserDefaults.standard.set(settingsUpdatedAt, forKey: Keys.updatedAt)
        writeState(force: true)
    }

    private func tick() {
        if tracking {
            let found = filter.faceFound(at: ProcessInfo.processInfo.systemUptime)
            if found != faceFound { faceFound = found }
        }
        adoptExtensionPrefs()
        writeState(force: false)
    }

    /// Comfort / pause changed from the Safari popup (ext-prefs.json) win if they're newer.
    private func adoptExtensionPrefs() {
        guard let p = store.readExtensionPrefs(), p.updatedAt > settingsUpdatedAt else { return }
        let merged = SharedStore.merged(settings, p)
        adopting = true
        settings.comfort = merged.comfort
        settings.paused = merged.paused
        adopting = false
        settingsUpdatedAt = p.updatedAt
    }

    /// While tracking: 4×/s. Otherwise a 1 s heartbeat so the extension knows the app is running.
    private func writeState(force: Bool) {
        let now = nowMs()
        let interval: Double = tracking ? 240 : 950
        guard force || now - lastStateWrite >= interval else { return }
        lastStateWrite = now
        var s = settings; s.updatedAt = settingsUpdatedAt
        let live = LiveReading(distanceCm: distanceCm.map { ($0 * 10).rounded() / 10 },
                               timestamp: tracking ? lastFrameMs : 0,
                               faceFound: tracking && faceFound,
                               tracking: tracking,
                               calibrated: isCalibrated)
        let ok = store.writeState(SharedState(heartbeat: now, live: live, settings: s))
        storeOK = !ok.isEmpty
        let names = ok.map { $0 == "appGroup" ? "App Group" : "shared folder" }
        storeStatus = ok.isEmpty ? "Couldn't write: " + store.lastErrors.joined(separator: "; ")
                                 : "Sharing via " + names.joined(separator: " + ") + (store.lastErrors.isEmpty ? "" : " (other: \(store.lastErrors.joined(separator: "; ")))")
    }

    func quit() {
        tracker.stop()
        var s = settings; s.updatedAt = settingsUpdatedAt
        store.writeState(SharedState(heartbeat: 0, live: LiveReading(), settings: s))  // tell the extension we're gone
        NSApp.terminate(nil)
    }
}
