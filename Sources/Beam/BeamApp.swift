import SwiftUI
import AppKit

@main
struct BeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Beam", systemImage: "command") {
            Button("Open Beam") { state.showPanel() }
            if let version = state.updater.availableVersion {
                Divider()
                Button("Update available: Beam \(version)") { state.openSettings() }
            }
            Divider()
            Button("Settings…") { state.openSettings() }
            Button("Quit Beam") { NSApplication.shared.terminate(nil) }
        }
        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.endpoints)
                .environmentObject(state.updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppState.shared.start()
    }
}
