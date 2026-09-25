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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func promptAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
