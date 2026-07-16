import AppKit

@MainActor
final class MenuBarController {
    static func activateAppForWindowPresentation() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

