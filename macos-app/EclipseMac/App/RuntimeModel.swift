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
    @Published var companionResponseText: String?
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
        companionResponseText = nil

        do {
            let contextStartedAt = Date()
            let snapshot = try AccessibilityContextCollector().capture()
            let contextCaptureMS = Self.elapsedMilliseconds(since: contextStartedAt)
            let appName = snapshot.activeApp?.name ?? "Unknown app"
            let windowTitle = snapshot.window?.title?.isEmpty == false ? snapshot.window?.title : "active window"
            let focused = snapshot.focusedElement?.label ?? snapshot.focusedElement?.role ?? "no focused element"
            companionContextSummary = "Capturing screen for Hermes · \(appName) · \(windowTitle ?? "active window") · \(focused)"

            Task {
                let captureStartedAt = Date()
                var screenshot: BridgeCompanionScreenshotAttachment?
                var screenshotCaptureMS: Int?
                var screenshotEncodeMS: Int?

                do {
                    let capture = try await ActiveWindowCapturer(maximumPixelDimension: 1_280).capture(snapshot: snapshot)
                    screenshotCaptureMS = Self.elapsedMilliseconds(since: captureStartedAt)
                    let encodeStartedAt = Date()
                    screenshot = try Self.screenshotAttachment(from: capture)
                    screenshotEncodeMS = Self.elapsedMilliseconds(since: encodeStartedAt)
                    companionContextSummary = "Sending visual context to Hermes · \(appName) · \(windowTitle ?? "active window")"
                } catch {
                    screenshotCaptureMS = Self.elapsedMilliseconds(since: captureStartedAt)
                    debugMessage = "Screenshot unavailable; sending text context"
                }

                let timings = BridgeCompanionAskClientTimings(
                    contextCaptureMS: contextCaptureMS,
                    screenshotCaptureMS: screenshotCaptureMS,
                    screenshotEncodeMS: screenshotEncodeMS
                )

                if let response = await localBridge.askCompanion(
                    prompt: prompt,
                    context: snapshot,
                    screenshot: screenshot,
                    clientTimings: timings
                ) {
                    companionContextSummary = response.contextSummary ?? companionContextSummary
                    companionResponseText = response.answer
                    state = .idle
                    debugMessage = Self.companionDebugMessage(response: response, usedScreenshot: screenshot != nil)
                } else {
                    state = .error
                    debugMessage = localBridge.bridgeMessage
                    companionResponseText = nil
                }
            }
        } catch {
            state = .error
            debugMessage = error.localizedDescription
            companionContextSummary = "Could not collect context for Hermes: \(error.localizedDescription)"
            companionResponseText = nil
        }
    }

    private static func screenshotAttachment(from result: WindowCaptureResult) throws -> BridgeCompanionScreenshotAttachment {
        guard let data = NSBitmapImageRep(cgImage: result.image).representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.68]
        ) else {
            throw WindowCaptureError.captureFailed
        }
        return BridgeCompanionScreenshotAttachment(
            captureID: result.metadata.captureID,
            mimeType: "image/jpeg",
            dataBase64: data.base64EncodedString(),
            width: result.metadata.pixelWidth,
            height: result.metadata.pixelHeight,
            capturedAt: result.metadata.capturedAt
        )
    }

    private static func companionDebugMessage(
        response: BridgeCompanionAskResponse,
        usedScreenshot: Bool
    ) -> String {
        let path = usedScreenshot ? "vision" : "text"
        let latency = response.timings.flatMap { timings -> String? in
            guard let bridgeBackendMS = timings.bridgeBackendMS else { return nil }
            return " · Hermes \(bridgeBackendMS)ms"
        } ?? ""
        if response.mode == "hermes" {
            return "Hermes responded via \(path)\(latency)"
        }
        return "Bridge returned Hermes scaffold"
    }

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
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
