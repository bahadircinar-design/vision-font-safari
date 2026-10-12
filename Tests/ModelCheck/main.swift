// Vision Font — Swift side of the shared test vectors + store/bridge/filter checks.
// Built by Tests/run-swift-check.sh together with Shared/*.swift (Foundation only, runs on macOS or Linux).
import Foundation

var failures = 0
func check(_ ok: Bool, _ msg: @autoclosure () -> String) { if !ok { failures += 1; print("✗ " + msg()) } }

let here = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/vectors.json")
let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: here)) as! [String: Any]
let tol = root["tolerance"] as! Double
let profilesJSON = root["profiles"] as! [String: Any]
var profiles: [String: Prescription] = [:]
for (k, v) in profilesJSON {
    profiles[k] = try! JSONDecoder().decode(Prescription.self, from: JSONSerialization.data(withJSONObject: v))
}
let opts = root["opts"] as! [String: [String: Any]]
let cases = root["cases"] as! [[String: Any]]

// 1. vectors
var maxErr = 0.0
for c in cases {
    let p = profiles[c["profile"] as! String]!
    let o = opts[c["opts"] as! String]!
    let r = PageScale.compute(p, distanceCm: c["distanceCm"] as! Double,
                              pxPerMm: o["pxPerMm"] as? Double, comfort: o["comfort"] as? Double, cap: o["cap"] as? Double)
    let got: [String: Double] = ["px": r.model.px, "enlarge": r.model.enlarge, "blur": r.model.blur, "blurOD": r.model.blurOD,
                                 "blurOS": r.model.blurOS, "accommodation": r.model.accommodation, "base": r.model.base,
                                 "rawScale": r.rawScale, "scale": r.scale]
    for (k, v) in got {
        let want = c[k] as! Double
        let e = abs(v - want); maxErr = max(maxErr, e)
        check(e <= tol, "\(c["profile"]!)/\(c["opts"]!)@\(c["distanceCm"]!) \(k): swift \(v) vs js \(want)")
    }
}
print("✓ \(cases.count) shared vectors: Swift port matches the JS model (max |Δ| \(String(format: "%.1e", maxErr)))")

// 2. defaults agree with scale.js defaultRx()
let d = Prescription.default
check(d.od == EyeRx(sph: 0, cyl: 0, axis: nil, add: 0) && d.os == EyeRx(sph: 0, cyl: 0, axis: nil, add: 0)
      && d.age == 45 && d.lens == .single && d.pdFar == 66 && d.pdNear == 63 && !d.wearing, "default prescription")
check(profiles["default"]! == d, "vectors' default profile equals Prescription.default")
print("✓ default prescription matches the JS default")

// 3. distance math + filter
let f = DistanceMath.focalNorm(ipdPx: 80, imageWidthPx: 640, knownCm: 50, pdMm: 63.0)!
check(abs(DistanceMath.distanceCm(ipdPx: 80, imageWidthPx: 640, focalNorm: f, pdMm: 63.0)! - 50) < 1e-9, "calibration round trip")
check(abs(DistanceMath.distanceCm(ipdPx: 40, imageWidthPx: 640, focalNorm: f, pdMm: 63.0)! - 100) < 1e-9, "half the IPD => twice the distance")
check(abs(DistanceMath.hfovDeg(focalNorm: DistanceMath.defaultFocalNorm()) - 60) < 1e-9, "default HFOV 60°")
var flt = DistanceFilter()
for (i, v) in [50.0, 51, 49, 200, 50, 50.5].enumerated() { flt.add(v, at: Double(i) * 0.1) }  // 200 = outlier
check(abs(flt.smoothed! - 50) < 2, "median filter rejects a one-frame outlier (got \(flt.smoothed!))")
check(flt.faceFound(at: 0.5 + 0.9) && !flt.faceFound(at: 0.5 + 1.1), "no-face after 1 s")
print("✓ distance math, median+EMA filter, no-face timeout")

// 4. shared store round trip + native bridge
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vf-test-\(getpid())")
let a = tmp.appendingPathComponent("group"), b = tmp.appendingPathComponent("shared")
let store = SharedStore(directories: [.init(name: "appGroup", directory: a), .init(name: "sharedFolder", directory: b)])
let t0 = nowMs()
var settings = VFSettings.default; settings.updatedAt = t0 - 10_000; settings.pxPerMm = 4.87; settings.pxPerMmSource = "detected"
let state = SharedState(heartbeat: t0, live: LiveReading(distanceCm: 52.4, timestamp: t0 - 200, faceFound: true, tracking: true, calibrated: true), settings: settings)
check(store.writeState(state) == ["appGroup", "sharedFolder"], "write both locations: \(store.lastErrors)")
check(store.readState()?.value == state, "read back state")
// stale copy in one location: newest wins
var older = state; older.heartbeat = t0 - 60_000; older.live.distanceCm = 99
let onlyB = SharedStore(directories: [.init(name: "sharedFolder", directory: b)]); onlyB.writeState(older)
check(store.readState()?.location == "appGroup" && store.readState()?.value.live.distanceCm == 52.4, "newest copy wins")

var reply = NativeBridge.handle(["type": "get"], store: store, now: t0 + 100)
check(reply["ok"] as? Bool == true && reply["appRunning"] as? Bool == true, "bridge get: app running")
check(((reply["live"] as? [String: Any])?["distanceCm"] as? Double) == 52.4, "bridge get: distance")
check((reply["liveAgeMs"] as? Double) == 300, "bridge get: live age")
reply = NativeBridge.handle(["type": "setPrefs", "comfort": 1.25, "paused": true], store: store, now: t0 + 200)
let rs = reply["settings"] as? [String: Any]
check((rs?["comfort"] as? Double) == 1.25 && (rs?["paused"] as? Bool) == true, "bridge setPrefs merges popup comfort/pause: \(String(describing: rs))")
check(JSONSerialization.isValidJSONObject(reply), "bridge reply is JSON-serialisable")
reply = NativeBridge.handle(["type": "get"], store: store, now: t0 + 10_000)
check(reply["appRunning"] as? Bool == false, "bridge: heartbeat older than 3 s => app not running")
let empty = SharedStore(directories: [.init(name: "x", directory: tmp.appendingPathComponent("none"))])
reply = NativeBridge.handle(nil, store: empty)
check(reply["ok"] as? Bool == true && reply["store"] as? String == "none" && reply["appRunning"] as? Bool == false, "bridge with no app data falls back to defaults")
let defSettings = reply["settings"] as? [String: Any]
check(((defSettings?["rx"] as? [String: Any])?["age"] as? Double) == 45, "bridge default settings carry the default Rx")
try? FileManager.default.removeItem(at: tmp)
print("✓ shared store (two locations, newest wins, atomic rename) and native bridge replies")

if failures > 0 { print("\n\(failures) Swift check(s) FAILED"); exit(1) }
print("\nAll Swift model checks passed.")
