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
    @available(macOS 14.0, *)
    @Environment(\.openSettings) private var openSettings

    private func showSettings() {
        if #available(macOS 14.0, *) {
            openSettings()
        } else {
            state.openSettings()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        Button("Open Beam") { state.showPanel() }
        if let version = state.updater.availableVersion {
            Divider()
            Button("Update available: Beam \(version)") { showSettings() }
        }
        Divider()
        Button("Settings…") { showSettings() }
        Button("Quit Beam") { NSApplication.shared.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppState.shared.start()
    }
}
