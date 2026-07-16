import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayController?
    private var hotKeyService: GlobalHotKeyService?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayController = OverlayController(runtime: RuntimeModel.shared)
        let hotKeyService = GlobalHotKeyService { [weak overlayController] in
            overlayController?.summonVoiceInput()
        }

        self.overlayController = overlayController
        self.hotKeyService = hotKeyService
        hotKeyService.registerOptionSpace()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(summonVoiceInput),
            name: .toggleEclipseOverlay,
            object: nil
        )
        RuntimeModel.shared.permissions.refresh()
        installApprovalPresentationHandler(overlayController: overlayController)

        if !ProcessInfo.processInfo.arguments.contains("--capture-window-once") {
            RuntimeModel.shared.startLocalBridgePollingOnLaunch()
        }

        if ProcessInfo.processInfo.arguments.contains("--show-overlay") {
            overlayController.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                RuntimeModel.shared.openSettings()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--capture-window-once") {
            runOneShotWindowCapture()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        RuntimeModel.shared.permissions.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        hotKeyService?.unregister()
    }

    @objc private func summonVoiceInput() {
        overlayController?.summonVoiceInput()
    }

    private func installApprovalPresentationHandler(overlayController: OverlayController) {
        let runtime = RuntimeModel.shared
        runtime.localBridge.$pendingJob
            .sink { [weak overlayController] pendingJob in
                if pendingJob != nil {
                    runtime.state = .waitingForApproval
                    runtime.debugMessage = runtime.localBridge.bridgeMessage
                    overlayController?.show()
                } else if runtime.state == .waitingForApproval {
                    runtime.state = .idle
                    runtime.debugMessage = runtime.localBridge.bridgeMessage
                }
            }
            .store(in: &cancellables)
    }

    private func runOneShotWindowCapture() {
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
                let snapshot = try AccessibilityContextCollector().capture()
                let result = try await ActiveWindowCapturer().capture(snapshot: snapshot)
                print(
                    "Eclipse capture succeeded: window=\(result.metadata.windowID) " +
                    "pixels=\(result.metadata.pixelWidth)x\(result.metadata.pixelHeight)"
                )
            } catch {
                print("Eclipse capture failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }
}
