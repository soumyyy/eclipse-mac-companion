import AppKit
import Combine

@MainActor
final class RuntimeModel: ObservableObject {
    static let shared = RuntimeModel()

    @Published var state: AssistantState = .idle
    @Published var debugMessage = "Ready on this Mac"
    let permissions = PermissionCenter()
    let contextDiagnostics = ContextDiagnosticsModel()
    let setTextActions = SetTextActionController()

    private init() {}

    func cycleDebugState() {
        state = state.nextDebugState
        debugMessage = state.debugMessage
    }

    func openSettings() {
        NotificationCenter.default.post(name: .openEclipseSettings, object: nil)
    }

    func prepareDemoTextAction() {
        do {
            try setTextActions.prepareDemoAction()
            state = .waitingForApproval
            debugMessage = "Review the exact field and text before approving"
        } catch {
            setTextActions.record(error: error)
            state = .error
            debugMessage = error.localizedDescription
        }
    }

    func approveTextAction() {
        state = .acting
        do {
            try setTextActions.approve()
            state = .idle
            debugMessage = "Approved text action completed"
        } catch {
            setTextActions.record(error: error)
            state = .error
            debugMessage = error.localizedDescription
        }
    }

    func cancelTextAction() {
        setTextActions.cancel()
        state = .idle
        debugMessage = "Text action cancelled"
    }

    func resetTextAction() {
        setTextActions.reset()
        state = .idle
        debugMessage = "Ready on this Mac"
    }
}
