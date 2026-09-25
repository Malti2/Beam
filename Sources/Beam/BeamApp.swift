import SwiftUI
import AppKit

@main
struct BeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Beam", systemImage: "command") {
            MenuBarView()
                .environmentObject(state)
        }
        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.endpoints)
                .environmentObject(state.updater)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Beam") { state.showPanel() }
        if let version = state.updater.availableVersion {
            Divider()
            Button("Update available: Beam \(version)") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Divider()
        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Beam") { NSApplication.shared.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppState.shared.start()
    }
}
