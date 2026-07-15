import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: NSPanel

    init(runtime: RuntimeModel) {
        panel = InputCapablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 380),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: OverlayView(runtime: runtime))
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let preferredOrigin = NSPoint(
            x: mouseLocation.x + 18,
            y: mouseLocation.y - panel.frame.height - 18
        )
        let origin = NSPoint(
            x: Self.clamp(
                preferredOrigin.x,
                lower: visibleFrame.minX + 12,
                upper: visibleFrame.maxX - panel.frame.width - 12
            ),
            y: Self.clamp(
                preferredOrigin.y,
                lower: visibleFrame.minY + 12,
                upper: visibleFrame.maxY - panel.frame.height - 12
            )
        )
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private final class InputCapablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
