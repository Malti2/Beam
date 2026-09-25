import AppKit
import SwiftUI

final class PanelController: NSObject {
    private var panel: NSPanel?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        centerOnScreen(panel)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func makePanel() -> NSPanel {
        let content = BarView()
            .environmentObject(state)
            .environmentObject(state.orchestrator)
        let hosting = NSHostingController(rootView: content)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func centerOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y = visible.origin.y + visible.height * 0.68 - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
