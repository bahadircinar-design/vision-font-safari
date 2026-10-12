//  SettingsView.swift — Vision Font
//  Prescription editor, comfort, camera + screen calibration, pause, open-at-login, privacy.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            StatusTab().tabItem { Label("Status", systemImage: "eye") }
            PrescriptionTab().tabItem { Label("Prescription", systemImage: "eyeglasses") }
            CalibrateTab().tabItem { Label("Calibrate", systemImage: "ruler") }
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(width: 600, height: 600)
        .onAppear { model.refreshExtensionState() }
    }
}

// MARK: - Status

private struct StatusTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Live") {
                Toggle("Track my distance with the camera", isOn: Binding(get: { model.tracking }, set: { model.setTracking($0) }))
                if let err = model.cameraError { Text(err).foregroundStyle(.red) }
                LabeledContent("Distance") {
                    if model.tracking, model.faceFound, let d = model.distanceCm { Text(String(format: "%.0f cm", d)).monospacedDigit() }
                    else if model.tracking { Text("No face in view").foregroundStyle(.secondary) }
                    else { Text("Tracking off").foregroundStyle(.secondary) }
                }
                if let s = model.currentScale {
                    LabeledContent("Residual blur") { Text(String(format: "%.2f D", s.model.blur)).monospacedDigit() }
                    LabeledContent("Web page scale (zoom mode)") {
                        Text(model.settings.paused ? "Paused" : String(format: "%.2f×%@", s.scale, s.rawScale > s.cap ? " (at max)" : "")).monospacedDigit()
                    }
                }
                LabeledContent("Camera calibration") {
                    Text(model.isCalibrated ? "Calibrated" : "Not calibrated — readings may be 10–20% off").foregroundStyle(model.isCalibrated ? Color.secondary : Color.orange)
                }
            }
            Section("Safari extension") {
                LabeledContent("Vision Font extension") {
                    switch model.extensionEnabled {
                    case .some(true): Text("Enabled ✓").foregroundStyle(.green)
                    case .some(false): Text("Not enabled yet").foregroundStyle(.orange)
                    case .none: Text("Unknown")
                    }
                }
                HStack {
                    Button("Open Safari Extensions Settings…") { model.openSafariExtensionSettings() }
                    Button("Refresh") { model.refreshExtensionState() }
                }
                Text("Building it yourself? In Safari ▸ Settings ▸ Developer, tick “Allow unsigned extensions” each time Safari starts. Then tick Vision Font in Settings ▸ Extensions and allow it on all websites.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Data sharing") {
                    Text(model.storeStatus).foregroundStyle(model.storeOK ? Color.secondary : Color.red).multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Prescription

private struct PrescriptionTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("SPH").bold(); Text("CYL").bold(); Text("AXIS").bold(); Text("ADD").bold()
                    }
                    eyeRow("OD (right)", $model.settings.rx.od)
                    eyeRow("OS (left)", $model.settings.rx.os)
                }
                HStack {
                    Button("Copy right eye to left") { model.settings.rx.os = model.settings.rx.od }
                    Spacer()
                    Button("Restore default prescription") { model.settings.rx = .default }
                }
            } header: { Text("Prescription") } footer: {
                Text("Values from your glasses prescription. Leave AXIS blank when CYL is 0. Only lens values are stored — no name, date of birth or clinic details.")
            }

            Section("Glasses") {
                Picker("Lens type", selection: $model.settings.rx.lens) {
                    ForEach(LensType.allCases) { Text($0.label).tag($0) }
                }
                Toggle("I'm wearing my glasses right now", isOn: $model.settings.rx.wearing)
                    .disabled(model.settings.rx.lens == .none)
                Stepper(value: $model.settings.rx.age, in: 5...100, step: 1) {
                    LabeledContent("Age") { Text("\(Int(model.settings.rx.age))") }
                }
                PDField(title: "PD, distance (mm)", value: $model.settings.rx.pdFar)
                PDField(title: "PD, near (mm) — used to measure distance", value: $model.settings.rx.pdNear)
            }

            Section {
                HStack {
                    Slider(value: $model.settings.comfort, in: 0.7...1.6, step: 0.05) { Text("Comfort") }
                    Text("\(Int((model.settings.comfort * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            } header: { Text("Comfort") } footer: {
                Text("Multiplies the size the model suggests. Lower it if pages feel too big, raise it for extra room.")
            }

            Section("What this means") {
                Text(clearRangeText)
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow { Text("Distance").bold(); Text("Blur").bold(); Text("Page scale").bold() }
                    ForEach([30.0, 40, 50, 70, 100], id: \.self) { d in
                        let r = PageScale.compute(model.settings.rx, distanceCm: d, pxPerMm: model.settings.pxPerMm, comfort: model.settings.comfort)
                        GridRow {
                            Text("\(Int(d)) cm")
                            Text(String(format: "%.2f D", r.model.blur))
                            Text(String(format: "%.2f×", r.scale))
                        }
                    }
                }
                .monospacedDigit()
                Text("Not a medical device. Rule-of-thumb sizes only.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var clearRangeText: String {
        let cr = VisionModel.clearRange(model.settings.rx)
        guard let lo = cr.min, let hi = cr.max else {
            return "No distance from 20–200 cm is fully sharp; least blur near \(cr.best ?? 0) cm."
        }
        let top = hi >= 200 ? "200+" : String(hi)
        return "Sharpest range: \(lo)–\(top) cm."
    }

    /// One prescription row, returned as a GridRow so Grid lays it out as a row.
    private func eyeRow(_ label: String, _ eye: Binding<EyeRx>) -> some View {
        GridRow {
            Text(label)
            DiopterField(value: eye.sph, range: -20...20)
            DiopterField(value: eye.cyl, range: -10...10)
            AxisField(value: eye.axis)
            DiopterField(value: eye.add, range: 0...4)
        }
    }
}

/// Diopter entry: text field (+1.00 style) plus a 0.25 D stepper.
private struct DiopterField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { value = snap($0) }),
                      format: .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Stepper("", value: Binding(get: { value }, set: { value = snap($0) }), in: range, step: 0.25).labelsHidden()
        }
    }
    private func snap(_ v: Double) -> Double { (min(range.upperBound, max(range.lowerBound, v)) * 4).rounded() / 4 }
}

private struct AxisField: View {
    @Binding var value: Double?
    @State private var text = ""
    var body: some View {
        TextField("—", text: $text)
            .multilineTextAlignment(.trailing)
            .frame(width: 50)
            .onAppear { text = value.map { String(Int($0)) } ?? "" }
            .onChange(of: value) { _, v in let t = v.map { String(Int($0)) } ?? ""; if t != text { text = t } }
            .onSubmit(commit)
            .onChange(of: text) { _, _ in commit() }
    }
    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { if value != nil { value = nil }; return }
        if let n = Double(t), (0...180).contains(n) { if value != n.rounded() { value = n.rounded() } }
    }
}

private struct PDField: View {
    let title: String
    @Binding var value: Double?
    var body: some View {
        LabeledContent(title) {
            TextField("", value: Binding(get: { value ?? 0 }, set: { v in value = v > 0 ? min(80, max(40, (v * 2).rounded() / 2)) : nil }),
                      format: .number.precision(.fractionLength(1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
    }
}

// MARK: - Calibrate

private struct CalibrateTab: View {
    @EnvironmentObject var model: AppModel
    @State private var cardPoints: Double = 0

    private let cardMm = 85.6, cardHmm = 53.98

    var body: some View {
        Form {
            Section {
                Stepper(value: $model.settings.calibrationCm, in: 25...150, step: 5) {
                    LabeledContent("Sit at this distance from the screen") { Text("\(Int(model.settings.calibrationCm)) cm") }
                }
                HStack {
                    Button(action: { model.startCalibration() }) { Text("Measure at \(Int(model.settings.calibrationCm)) cm") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isCalibrating)
                    Button("Reset") { model.resetCameraCalibration() }
                    Spacer()
                    calibrationStatus
                }
                if let ipd = model.lastIpdPx, model.tracking {
                    Text(String(format: "Pupils %.0f px apart · %@", ipd, model.faceFound ? "face found" : "no face")).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("1 · Camera distance") } footer: {
                Text("Measure with a tape from your eyes to the screen, look straight at the camera, and click Measure. It uses your near PD (\(String(format: "%.1f", model.pdMm)) mm) — change it on the Prescription tab.")
            }

            Section {
                if let s = model.screen {
                    LabeledContent("Detected display") { Text(s.name) }
                    if let ppi = s.pointsPerInch, let px = s.pixelsPerInch {
                        LabeledContent("Size") { Text(String(format: "%.0f mm wide · %.0f pt/in · %.0f px/in (%.0f× Retina)", s.mmWide, ppi, px, s.backingScale)) }
                    }
                }
                LabeledContent("In use") {
                    Text(String(format: "%.0f CSS px per inch (%@)", (model.settings.pxPerMm ?? VisionModel.C.CSS_PX_PER_MM) * 25.4, model.settings.pxPerMmSource))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold a bank or ID card against the screen and drag until the blue card is the same width.").font(.callout)
                    RoundedRectangle(cornerRadius: 3.18 * ppm)
                        .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: cardMm * ppm, height: cardHmm * ppm)
                        .overlay(Text("85.6 mm").foregroundStyle(.white).font(.caption))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Slider(value: Binding(get: { cardPoints == 0 ? cardMm * (model.settings.pxPerMm ?? VisionModel.C.CSS_PX_PER_MM) : cardPoints },
                                          set: { cardPoints = $0 }),
                           in: cardMm * 2.5...cardMm * 7.5,
                           onEditingChanged: { editing in if !editing && cardPoints > 0 { model.setCardMatch(pointsPerMm: cardPoints / cardMm) } })
                    HStack {
                        Button("Use detected size") { cardPoints = 0; model.useDetectedScreen() }
                        Spacer()
                    }
                }
            } header: { Text("2 · Screen size") } footer: {
                Text("Safari measures text in points. Knowing how big a point is on your screen lets the extension aim for a true on-screen size. MacBook sizes are detected automatically; the card check fixes anything off.")
            }
        }
        .formStyle(.grouped)
    }

    private var ppm: Double { (cardPoints > 0 ? cardPoints : cardMm * (model.settings.pxPerMm ?? VisionModel.C.CSS_PX_PER_MM)) / cardMm }

    @ViewBuilder private var calibrationStatus: some View {
        switch model.calibration {
        case .idle: EmptyView()
        case .countdown(let n): Text("Hold still… \(n)").bold()
        case .measuring: HStack { ProgressView().controlSize(.small); Text("Measuring…") }
        case .done(let msg): Text(msg).foregroundStyle(.green).font(.callout)
        case .failed(let msg): Text(msg).foregroundStyle(.red).font(.callout)
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Pause resizing on all websites", isOn: $model.settings.paused)
                Toggle("Open Vision Font at login", isOn: $model.launchAtLogin)
                if let e = model.loginError { Text(e).foregroundStyle(.red).font(.callout) }
                Text("Open at login works best after you drag Vision Font into your Applications folder.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("The camera runs only while Tracking is on. Each frame is analysed in memory on this Mac to find your pupils, then discarded. Frames are never saved, shown or sent anywhere, and Vision Font makes no network connections.")
                Text("Only a distance number, a timestamp and your settings are shared with the Safari extension, through a small file on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset all settings…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset prescription, comfort and calibration to the defaults?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { model.resetAllSettings() }
                    }
            } footer: {
                Text("Vision Font is not a medical device. It gives rule-of-thumb text sizes and doesn't replace an eye exam.")
            }
        }
        .formStyle(.grouped)
    }
}
