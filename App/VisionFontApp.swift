//  VisionFontApp.swift — Vision Font
//  Menu-bar companion app for the Vision Font Safari extension. No Dock icon (LSUIElement).

import AppKit
import SwiftUI

@main
struct VisionFontApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.menu)

        Window("Vision Font Settings", id: "settings") {
            SettingsView().environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The text in the menu bar, e.g. "Eye 52 cm". Also opens Settings on the very first launch.
struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.menuTitle)
            .monospacedDigit()
            .task {
                if model.isFirstLaunch {
                    model.markOnboarded()
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.tracking {
            if model.faceFound, let d = model.distanceCm {
                Text(String(format: "Distance: %.0f cm%@", d, model.isCalibrated ? "" : " (not calibrated)"))
            } else {
                Text("Distance: no face in view")
            }
        } else {
            Text(model.cameraError ?? "Tracking is off")
        }
        if let s = model.currentScale {
            Text(String(format: "Web text scale: %.2f× · blur %.2f D", model.settings.paused ? 1 : s.scale, s.model.blur))
        }
        Divider()
        Toggle("Tracking", isOn: Binding(get: { model.tracking }, set: { model.setTracking($0) }))
        Toggle("Wearing my glasses", isOn: $model.settings.rx.wearing)
        Toggle("Pause resizing", isOn: $model.settings.paused)
        Divider()
        Button("Calibrate (sit at \(Int(model.settings.calibrationCm)) cm)…") {
            openSettings()
            model.startCalibration()
        }
        Button("Open Settings…") { openSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Vision Font") { model.quit() }
            .keyboardShortcut("q")
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
