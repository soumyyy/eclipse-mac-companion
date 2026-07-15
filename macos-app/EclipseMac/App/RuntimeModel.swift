import AppKit
import Combine

@MainActor
final class RuntimeModel: ObservableObject {
    static let shared = RuntimeModel()

    @Published var state: AssistantState = .idle
    @Published var debugMessage = "Ready on this Mac"
    let permissions = PermissionCenter()
    let contextDiagnostics = ContextDiagnosticsModel()
    let setTextActions: SetTextActionController
    let localBridge: LocalBridgeController

    private init() {
        let setTextActions = SetTextActionController()
        self.setTextActions = setTextActions
        localBridge = LocalBridgeController(setTextActions: setTextActions)
    }

    func cycleDebugState() {
        state = state.nextDebugState
        debugMessage = state.debugMessage
    }

    func openSettings() {
        NotificationCenter.default.post(name: .openEclipseSettings, object: nil)
    }

    func prepareDemoTextAction() {
        localBridge.submitMockSetTextJob(text: SetTextActionController.demoText)
        if let result = localBridge.latestResult, result.status == .pendingApproval {
            state = .waitingForApproval
            debugMessage = "Mock bridge job is waiting for approval"
        } else if let error = localBridge.latestResult?.error {
            state = .error
            debugMessage = error.message
            setTextActions.record(error: NSError(
                domain: "EclipseMac.LocalBridge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: error.message]
            ))
        } else {
            state = .error
            debugMessage = "Mock bridge job did not produce an approval"
        }
    }

    func approveTextAction() {
        state = .acting
        do {
            let actionResult = try setTextActions.approve()
            localBridge.completePendingSetTextJob(with: actionResult)
            state = .idle
            debugMessage = "Approved bridge job completed"
        } catch {
            setTextActions.record(error: error)
            state = .error
            debugMessage = error.localizedDescription
        }
    }

    func cancelTextAction() {
        setTextActions.cancel()
        localBridge.cancelPendingJob()
        state = .idle
        debugMessage = "Text action cancelled"
    }

    func resetTextAction() {
        setTextActions.reset()
        state = .idle
        debugMessage = "Ready on this Mac"
    }
}
