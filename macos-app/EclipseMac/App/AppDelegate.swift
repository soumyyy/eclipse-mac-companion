import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayController?
    private var hotKeyService: GlobalHotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayController = OverlayController(runtime: RuntimeModel.shared)
        let hotKeyService = GlobalHotKeyService { [weak overlayController] in
            overlayController?.toggle()
        }

        self.overlayController = overlayController
        self.hotKeyService = hotKeyService
        hotKeyService.registerOptionSpace()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleOverlay),
            name: .toggleEclipseOverlay,
            object: nil
        )
        RuntimeModel.shared.permissions.refresh()

        if ProcessInfo.processInfo.arguments.contains("--show-overlay") {
            overlayController.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                RuntimeModel.shared.openSettings()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        RuntimeModel.shared.permissions.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        hotKeyService?.unregister()
    }

    @objc private func toggleOverlay() {
        overlayController?.toggle()
    }
}
