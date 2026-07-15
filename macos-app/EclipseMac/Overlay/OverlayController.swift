import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let runtime: RuntimeModel
    private let panel: NSPanel

    init(runtime: RuntimeModel) {
        self.runtime = runtime
        panel = InputCapablePanel(
            contentRect: NSRect(origin: .zero, size: Self.compactSize),
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
        resizeForCurrentState()
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

    private func resizeForCurrentState() {
        let size = runtime.prefersExpandedOverlay ? Self.expandedSize : Self.compactSize
        guard panel.frame.size != size else { return }
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: size),
            display: true,
            animate: panel.isVisible
        )
    }

    private static let compactSize = NSSize(width: 430, height: 246)
    private static let expandedSize = NSSize(width: 540, height: 380)
}

private final class InputCapablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
