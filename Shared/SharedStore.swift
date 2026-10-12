//  SharedStore.swift — Vision Font
//  How the companion app and the Safari extension's native handler share data.
//
//  Both are sandboxed, so neither can see the other's container. We write the same small JSON file to TWO
//  places and readers take whichever copy is newest:
//   1. App Group container  ~/Library/Group Containers/<TEAMID>.com.bahacinar.visionfont/state.json
//      (macOS-style, Team-ID-prefixed group: no provisioning profile or paid account needed; macOS checks the
//       prefix against the signing Team ID, so a free Personal Team works.)
//   2. Shared folder        ~/Library/Application Support/VisionFontShared/state.json
//      (reachable from both sandboxes through a temporary-exception file entitlement; independent of
//       App Groups, so it keeps working if App Groups are switched off — see Config/Shared.xcconfig.)
//
//  Files:
//   state.json      written only by the app: live distance (a few times a second) + settings + heartbeat
//   ext-prefs.json  written only by the extension handler: comfort + pause changed from the Safari popup
//  Single writer per file + write-to-temp-then-rename => readers never see half-written JSON.
//  Pure Foundation (compiles on Linux for Tests/ModelCheck).

import Foundation
#if canImport(Security)
import Security
#endif

// MARK: - Data shapes (JSON). Keep in sync with Extension/Resources/background.js.

public struct LiveReading: Codable, Equatable {
    public var distanceCm: Double?
    public var timestamp: Double          // ms since 1970 of the last camera reading
    public var faceFound: Bool
    public var tracking: Bool
    public var calibrated: Bool
    public init(distanceCm: Double? = nil, timestamp: Double = 0, faceFound: Bool = false, tracking: Bool = false, calibrated: Bool = false) {
        self.distanceCm = distanceCm; self.timestamp = timestamp; self.faceFound = faceFound; self.tracking = tracking; self.calibrated = calibrated
    }
}

public struct VFSettings: Codable, Equatable {
    public var rx: Prescription
    public var comfort: Double            // 0.70 … 1.60
    public var pxPerMm: Double?           // CSS px (= macOS points) per mm on screen; nil = model default (96/in)
    public var pxPerMmSource: String      // "detected" | "card" | "default"
    public var paused: Bool
    public var focalNorm: Double?         // camera focal length / frame width (nil = assume 60° HFOV)
    public var calibrationCm: Double
    public var updatedAt: Double          // ms since 1970

    public static let `default` = VFSettings(rx: .default, comfort: 1, pxPerMm: nil, pxPerMmSource: "default",
                                             paused: false, focalNorm: nil, calibrationCm: 50, updatedAt: 0)

    public init(rx: Prescription, comfort: Double, pxPerMm: Double?, pxPerMmSource: String, paused: Bool, focalNorm: Double?, calibrationCm: Double, updatedAt: Double) {
        self.rx = rx; self.comfort = comfort; self.pxPerMm = pxPerMm; self.pxPerMmSource = pxPerMmSource
        self.paused = paused; self.focalNorm = focalNorm; self.calibrationCm = calibrationCm; self.updatedAt = updatedAt
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VFSettings.default
        rx = (try? c.decodeIfPresent(Prescription.self, forKey: .rx)) ?? d.rx
        comfort = (try? c.decodeIfPresent(Double.self, forKey: .comfort)) ?? d.comfort
        pxPerMm = (try? c.decodeIfPresent(Double.self, forKey: .pxPerMm)) ?? nil
        pxPerMmSource = (try? c.decodeIfPresent(String.self, forKey: .pxPerMmSource)) ?? d.pxPerMmSource
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? d.paused
        focalNorm = (try? c.decodeIfPresent(Double.self, forKey: .focalNorm)) ?? nil
        calibrationCm = (try? c.decodeIfPresent(Double.self, forKey: .calibrationCm)) ?? d.calibrationCm
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
    }
}

public struct SharedState: Codable, Equatable {
    public var schema: Int = 1
    public var heartbeat: Double          // ms since 1970; the app rewrites at least once a second while running
    public var live: LiveReading
    public var settings: VFSettings
    public init(heartbeat: Double, live: LiveReading, settings: VFSettings) { self.heartbeat = heartbeat; self.live = live; self.settings = settings }
}

public struct ExtensionPrefs: Codable, Equatable {
    public var comfort: Double?
    public var paused: Bool?
    public var updatedAt: Double
    public init(comfort: Double? = nil, paused: Bool? = nil, updatedAt: Double) { self.comfort = comfort; self.paused = paused; self.updatedAt = updatedAt }
}

public func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

// MARK: - Store

public final class SharedStore {
    public static let appGroupSuffix = "com.bahacinar.visionfont"
    public static let sharedFolderRelative = "Library/Application Support/VisionFontShared"
    public static let stateFile = "state.json"
    public static let extPrefsFile = "ext-prefs.json"

    public struct Location { public let name: String; public let directory: URL }
    public private(set) var locations: [Location] = []
    public private(set) var lastErrors: [String] = []

    /// `directories` overrides discovery (used by tests).
    public init(directories: [Location]? = nil, bundle: Bundle = .main) {
        if let directories = directories { locations = directories; return }
        let useGroup = (bundle.object(forInfoDictionaryKey: "VFUseAppGroup") as? String)?.uppercased() != "NO"
        if useGroup, let gid = SharedStore.appGroupIdentifier(bundle: bundle), let url = SharedStore.groupContainer(gid) {
            locations.append(Location(name: "appGroup", directory: url))
        }
        locations.append(Location(name: "sharedFolder", directory: SharedStore.realHome().appendingPathComponent(SharedStore.sharedFolderRelative, isDirectory: true)))
    }

    // MARK: discovery

    /// "<TEAMID>.com.bahacinar.visionfont". Info.plist key VFAppGroupIdentifier first (Xcode fills in
    /// $(TeamIdentifierPrefix)), otherwise derived from the Team ID in our own code signature.
    public static func appGroupIdentifier(bundle: Bundle = .main) -> String? {
        if let s = bundle.object(forInfoDictionaryKey: "VFAppGroupIdentifier") as? String,
           !s.contains("$("), !s.hasPrefix("."), s.hasSuffix(appGroupSuffix), s.count > appGroupSuffix.count + 1 {
            return s
        }
        if let team = signingTeamID() { return "\(team).\(appGroupSuffix)" }
        return nil
    }

    public static func signingTeamID() -> String? {
        #if os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code = code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let sc = staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { return nil }
        return team
        #else
        return nil
        #endif
    }

    static func groupContainer(_ id: String) -> URL? {
        #if os(macOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        #else
        return nil
        #endif
    }

    /// The real home folder (inside the sandbox, NSHomeDirectory() points into the app's container).
    public static func realHome() -> URL {
        #if os(macOS) || os(Linux)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // MARK: IO

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()

    /// Writes to every location; returns the names that succeeded.
    @discardableResult
    public func write<T: Encodable>(_ value: T, file: String) -> [String] {
        var ok: [String] = []
        var errs: [String] = []
        guard let data = try? SharedStore.encoder.encode(value) else { lastErrors = ["encode failed"]; return [] }
        for loc in locations {
            do {
                try FileManager.default.createDirectory(at: loc.directory, withIntermediateDirectories: true)
                let dest = loc.directory.appendingPathComponent(file)
                let tmp = loc.directory.appendingPathComponent(".\(file).\(getpid()).tmp")
                try data.write(to: tmp)
                if rename(tmp.path, dest.path) != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                ok.append(loc.name)
            } catch {
                errs.append("\(loc.name): \((error as NSError).localizedDescription)")
            }
        }
        lastErrors = errs
        return ok
    }

    public func read<T: Decodable>(_ type: T.Type, file: String, newest: (T) -> Double) -> (value: T, location: String)? {
        var best: (T, String)?
        var errs: [String] = []
        for loc in locations {
            let url = loc.directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let v = try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
                if best == nil || newest(v) > newest(best!.0) { best = (v, loc.name) }
            } catch {
                errs.append("\(loc.name): \((error as NSError).localizedDescription)")
            }
        }
        lastErrors = errs
        return best.map { (value: $0.0, location: $0.1) }
    }

    @discardableResult public func writeState(_ s: SharedState) -> [String] { write(s, file: SharedStore.stateFile) }
    public func readState() -> (value: SharedState, location: String)? { read(SharedState.self, file: SharedStore.stateFile) { $0.heartbeat } }
    @discardableResult public func writeExtensionPrefs(_ p: ExtensionPrefs) -> [String] { write(p, file: SharedStore.extPrefsFile) }
    public func readExtensionPrefs() -> ExtensionPrefs? { read(ExtensionPrefs.self, file: SharedStore.extPrefsFile) { $0.updatedAt }?.value }

    /// Settings with the popup's comfort/pause applied when they are newer than the app's settings.
    public static func merged(_ s: VFSettings, _ p: ExtensionPrefs?) -> VFSettings {
        guard let p = p, p.updatedAt > s.updatedAt else { return s }
        var out = s
        if let c = p.comfort { out.comfort = min(1.6, max(0.7, c)) }
        if let paused = p.paused { out.paused = paused }
        out.updatedAt = p.updatedAt
        return out
    }
}

// MARK: - Native message handling (used by SafariWebExtensionHandler; kept here so it is testable)

public enum NativeBridge {
    public static let appRunningWindowMs = 3000.0

    /// Handles {type:"get"} and {type:"setPrefs", comfort?, paused?}. Returns a JSON-compatible dictionary.
    public static func handle(_ message: [String: Any]?, store: SharedStore, now: Double = nowMs()) -> [String: Any] {
        let type = message?["type"] as? String ?? "get"
        var errors: [String] = []
        if type == "setPrefs" {
            let existing = store.readExtensionPrefs()
            var p = ExtensionPrefs(comfort: existing?.comfort, paused: existing?.paused, updatedAt: now)
            if let c = (message?["comfort"] as? NSNumber)?.doubleValue { p.comfort = min(1.6, max(0.7, c)) }
            if let b = message?["paused"] as? Bool { p.paused = b }
            if store.writeExtensionPrefs(p).isEmpty { errors.append(contentsOf: store.lastErrors.isEmpty ? ["could not save popup settings"] : store.lastErrors) }
        } else if type != "get" {
            return ["ok": false, "error": "unknown message type \(type)"]
        }

        let state = store.readState()
        errors.append(contentsOf: store.lastErrors)
        let extPrefs = store.readExtensionPrefs()
        let settings = SharedStore.merged(state?.value.settings ?? .default, extPrefs)
        var reply: [String: Any] = [
            "ok": true,
            "now": now,
            "store": state?.location ?? "none",
            "appRunning": state.map { now - $0.value.heartbeat <= appRunningWindowMs } ?? false,
            "heartbeatAgeMs": state.map { max(0, now - $0.value.heartbeat) } ?? -1,
            "settings": jsonObject(settings) ?? [:],
            "errors": errors,
        ]
        if let live = state?.value.live {
            reply["live"] = jsonObject(live) ?? [:]
            reply["liveAgeMs"] = max(0, now - live.timestamp)
        } else {
            reply["live"] = ["tracking": false, "faceFound": false, "timestamp": 0, "calibrated": false]
            reply["liveAgeMs"] = 1e12
        }
        return reply
    }

    static func jsonObject<T: Encodable>(_ v: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(v) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
