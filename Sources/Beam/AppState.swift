import SwiftUI
import AppKit
import ApplicationServices

final class AppState: ObservableObject {
    static let shared = AppState()

    let endpoints = EndpointStore()
    lazy var orchestrator = Orchestrator(endpoints: self.endpoints)
    let updater = Updater()
    private lazy var panel = PanelController(state: self)
    private let hotkey = HotkeyManager()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        hotkey.onTrigger = { [weak self] in self?.togglePanel() }
        hotkey.start()
        promptAccessibilityIfNeeded()
        if UserDefaults.standard.object(forKey: "beam.autoUpdate") as? Bool ?? true {
            updater.checkForUpdates(automatic: true)
        }
    }

    func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() { panel.show() }
    func hidePanel() { panel.hide() }
    func restartHotkey() { hotkey.start() }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // The selector name changed across macOS versions; try both.
        for name in ["showSettingsWindow:", "showPreferencesWindow:"] {
            if NSApp.sendAction(Selector(name), to: nil, from: nil) { break }
        }
        // Accessory apps do not come forward on their own; make sure the
        // settings window is visible and key.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window != NSApp.keyWindow && window.canBecomeKey && window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func promptAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
