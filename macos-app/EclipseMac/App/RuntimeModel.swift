import AppKit
import Combine

@MainActor
final class RuntimeModel: ObservableObject {
    static let shared = RuntimeModel()

    @Published var state: AssistantState = .idle
    @Published var debugMessage = "Ready on this Mac"
    @Published var companionPrompt = ""
    @Published var companionLastPrompt = ""
    @Published var companionContextSummary = "Ask Hermes about the screen you are on."
    @Published var companionExpanded = false
    let permissions = PermissionCenter()
    let contextDiagnostics = ContextDiagnosticsModel()
    let setTextActions: SetTextActionController
    let localBridge: LocalBridgeController
    let speech = SpeechTranscriptionController()

    var needsApprovalOverlay: Bool {
        setTextActions.pendingAction != nil ||
            setTextActions.result != nil ||
            localBridge.pendingAutomationApproval != nil
    }

    var overlayPresentation: CompanionOverlayPresentation {
        if needsApprovalOverlay { return .approval }
        return companionExpanded ? .companion : .buddy
    }

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

    func expandCompanion() {
        companionExpanded = true
    }

    func collapseCompanion() {
        companionExpanded = false
    }

    func toggleCompanionVoiceInput() {
        if speech.isListening {
            speech.stopListening()
            let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                companionPrompt = transcript
            }
            state = .idle
            debugMessage = transcript.isEmpty ? "Voice stopped" : "Voice transcript ready for Hermes"
        } else {
            state = .listening
            debugMessage = "Listening for a Hermes prompt"
            speech.startListening()
        }
    }

    func prepareCompanionAskForHermes() {
        let prompt = companionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        state = .thinking
        debugMessage = "Packing screen context for Hermes"
        companionLastPrompt = prompt
        companionPrompt = ""

        do {
            let snapshot = try AccessibilityContextCollector().capture()
            let appName = snapshot.activeApp?.name ?? "Unknown app"
            let windowTitle = snapshot.window?.title?.isEmpty == false ? snapshot.window?.title : "active window"
            let focused = snapshot.focusedElement?.label ?? snapshot.focusedElement?.role ?? "no focused element"
            companionContextSummary = "Ready for Hermes · \(appName) · \(windowTitle ?? "active window") · \(focused)"
            state = .idle
            debugMessage = "Hermes ask endpoint is next; context package is ready"
        } catch {
            state = .error
            debugMessage = error.localizedDescription
            companionContextSummary = "Could not collect context for Hermes: \(error.localizedDescription)"
        }
    }

    func prepareDemoTextAction() {
        state = .thinking
        debugMessage = "Preparing mock bridge job"
        Task {
            await localBridge.submitMockSetTextJob(text: SetTextActionController.demoText)
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
    }

    func approveTextAction() {
        if localBridge.expirePendingJobIfNeeded() {
            setTextActions.cancel()
            state = .error
            debugMessage = localBridge.bridgeMessage
            return
        }

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

    func approveAutomationAction() {
        if localBridge.expirePendingJobIfNeeded() {
            state = .error
            debugMessage = localBridge.bridgeMessage
            return
        }

        state = .acting
        localBridge.completePendingAutomationJob()
        switch localBridge.latestResult?.status {
        case .succeeded:
            state = .idle
        case .failed, .rejected, .expired:
            state = .error
        case .pendingApproval, .none:
            state = .idle
        }
        debugMessage = localBridge.bridgeMessage
    }

    func cancelTextAction() {
        setTextActions.cancel()
        localBridge.cancelPendingJob()
        state = .idle
        debugMessage = "Text action cancelled"
    }

    func cancelAutomationAction() {
        localBridge.cancelPendingJob()
        state = .idle
        debugMessage = "Automation action cancelled"
    }

    func resetTextAction() {
        setTextActions.reset()
        state = .idle
        debugMessage = "Ready on this Mac"
    }

    func fetchLocalBridgeJob() {
        state = .thinking
        debugMessage = "Fetching next local bridge job"
        Task {
            let result = await localBridge.fetchNextRemoteJob()
            if localBridge.pendingJob != nil {
                state = .waitingForApproval
            } else if result?.status == .failed || result?.status == .rejected || result?.status == .expired {
                state = .error
            } else {
                state = .idle
            }
            debugMessage = localBridge.bridgeMessage
        }
    }

    func postLocalBridgeOutbox() {
        state = .acting
        debugMessage = "Posting local bridge outbox"
        Task {
            _ = await localBridge.postOutbox()
            state = .idle
            debugMessage = localBridge.bridgeMessage
        }
    }

    func saveLocalBridgeBaseURL() {
        if localBridge.saveBridgeBaseURL() {
            state = .idle
        } else {
            state = .error
        }
        debugMessage = localBridge.bridgeMessage
    }

    func startLocalBridgePollingOnLaunch() {
        guard !localBridge.isPolling else { return }
        localBridge.startPolling()
        state = localBridge.isPolling ? .idle : .error
        debugMessage = localBridge.bridgeMessage
    }

    func toggleLocalBridgePolling() {
        if localBridge.isPolling {
            localBridge.stopPolling()
            state = .idle
        } else {
            localBridge.startPolling()
            state = localBridge.isPolling ? .thinking : .error
        }
        debugMessage = localBridge.bridgeMessage
    }

    func pollLocalBridgeOnce() {
        state = .thinking
        debugMessage = "Polling local bridge once"
        Task {
            _ = await localBridge.pollOnce()
            if localBridge.pendingJob != nil {
                state = .waitingForApproval
            } else if localBridge.latestResult?.status == .expired {
                state = .error
            } else {
                state = localBridge.bridgeStatus.hasPrefix("Bridge unavailable") ? .error : .idle
            }
            debugMessage = localBridge.bridgeMessage
        }
    }
}

enum CompanionOverlayPresentation: Equatable {
    case buddy
    case companion
    case approval
}
