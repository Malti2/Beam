import AppKit

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case bothCommands = "bothCommands"
    case optionSpace = "optionSpace"
    case shiftOptionSpace = "shiftOptionSpace"
    case controlOptionSpace = "controlOptionSpace"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bothCommands: return "Left ⌘ + Right ⌘"
        case .optionSpace: return "⌥ Space"
        case .shiftOptionSpace: return "⇧⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        }
    }

    static var current: HotkeyChoice {
        HotkeyChoice(rawValue: UserDefaults.standard.string(forKey: "beam.hotkey") ?? "") ?? .bothCommands
    }
}

// Watches the keyboard globally (read-only monitor) and fires when the
// configured hotkey is pressed. Left+Right Command is detected through
// flagsChanged key codes 55 (left) and 54 (right).
final class HotkeyManager {
    var onTrigger: (() -> Void)?

    private var monitors: [Any] = []
    private var leftCommandDown = false
    private var rightCommandDown = false
    private var lastTrigger = Date.distantPast

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch HotkeyChoice.current {
        case .bothCommands:
            guard event.type == .flagsChanged else { return }
            if event.keyCode == 55 { leftCommandDown = event.modifierFlags.contains(.command) }
            if event.keyCode == 54 { rightCommandDown = event.modifierFlags.contains(.command) }
            if leftCommandDown && rightCommandDown { fire() }
        case .optionSpace:
            if matches(event, keyCode: 49, required: [.option]) { fire() }
        case .shiftOptionSpace:
            if matches(event, keyCode: 49, required: [.option, .shift]) { fire() }
        case .controlOptionSpace:
            if matches(event, keyCode: 49, required: [.option, .control]) { fire() }
        }
    }

    private func matches(_ event: NSEvent, keyCode: UInt16, required: NSEvent.ModifierFlags) -> Bool {
        guard event.type == .keyDown, event.keyCode == keyCode else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.modifierFlags.intersection(relevant) == required
    }

    private func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastTrigger) > 0.4 else { return }
        lastTrigger = now
        leftCommandDown = false
        rightCommandDown = false
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }
}
