import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private let runtime: RuntimeModel
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var cursorFollowTimer: Timer?

    init(runtime: RuntimeModel) {
        self.runtime = runtime
        panel = InputCapablePanel(
            contentRect: NSRect(origin: .zero, size: Self.buddySize),
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
        installResizeObserver()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        resizeForCurrentState(animate: false)
        positionForCurrentPresentation()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        updateCursorFollowing()
    }

    func hide() {
        stopCursorFollowing()
        panel.orderOut(nil)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func installResizeObserver() {
        runtime.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resizeForCurrentState(animate: true)
                }
            }
            .store(in: &cancellables)
    }

    private func resizeForCurrentState(animate: Bool) {
        let size = switch runtime.overlayPresentation {
        case .buddy:
            Self.buddySize
        case .companion:
            Self.companionSize
        case .approval:
            Self.approvalSize
        }
        guard panel.frame.size != size else { return }
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: size),
            display: true,
            animate: animate && panel.isVisible
        )
        if panel.isVisible {
            positionForCurrentPresentation()
            updateCursorFollowing()
        }
    }

    private func positionForCurrentPresentation() {
        switch runtime.overlayPresentation {
        case .buddy:
            positionBuddyNearCursor(allowFreezeNearPanel: false)
        case .companion, .approval:
            positionPanelOnLeftSide()
        }
    }

    private func updateCursorFollowing() {
        if panel.isVisible, runtime.overlayPresentation == .buddy {
            startCursorFollowing()
        } else {
            stopCursorFollowing()
        }
    }

    private func startCursorFollowing() {
        guard cursorFollowTimer == nil else { return }
        cursorFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.positionBuddyNearCursor(allowFreezeNearPanel: true)
            }
        }
    }

    private func stopCursorFollowing() {
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = nil
    }

    private func positionBuddyNearCursor(allowFreezeNearPanel: Bool) {
        let mouseLocation = NSEvent.mouseLocation
        if allowFreezeNearPanel, panel.frame.insetBy(dx: -28, dy: -28).contains(mouseLocation) {
            return
        }
        guard let screen = screen(containing: mouseLocation) else { return }
        let visibleFrame = screen.visibleFrame
        let preferredOrigin = NSPoint(
            x: mouseLocation.x + 18,
            y: mouseLocation.y - panel.frame.height - 18
        )
        panel.setFrameOrigin(clamped(origin: preferredOrigin, inside: visibleFrame))
    }

    private func positionPanelOnLeftSide() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) else { return }
        let visibleFrame = screen.visibleFrame
        let preferredOrigin = NSPoint(
            x: visibleFrame.minX + 18,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(clamped(origin: preferredOrigin, inside: visibleFrame))
    }

    private func clamped(origin: NSPoint, inside visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: Self.clamp(
                origin.x,
                lower: visibleFrame.minX + 12,
                upper: visibleFrame.maxX - panel.frame.width - 12
            ),
            y: Self.clamp(
                origin.y,
                lower: visibleFrame.minY + 12,
                upper: visibleFrame.maxY - panel.frame.height - 12
            )
        )
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static let buddySize = NSSize(width: 238, height: 74)
    private static let companionSize = NSSize(width: 430, height: 246)
    private static let approvalSize = NSSize(width: 540, height: 380)
}

private final class InputCapablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
