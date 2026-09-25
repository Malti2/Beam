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

    var body: some View {
        Button("Open Beam") { state.showPanel() }
        if let version = state.updater.availableVersion {
            Divider()
            SettingsLink {
                Text("Update available: Beam \(version)")
            }
        }
        Divider()
        SettingsLink {
            Text("Settings…")
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
