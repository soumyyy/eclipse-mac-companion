import Foundation
import UserNotifications

@MainActor
protocol LocalNotificationDelivering: AnyObject {
    func deliver(title: String, body: String?) async throws -> BridgeNotificationReceipt
}

@MainActor
final class UserNotificationDeliverer: LocalNotificationDelivering {
    func deliver(title: String, body: String?) async throws -> BridgeNotificationReceipt {
        let center = UNUserNotificationCenter.current()
        let granted = try await requestAuthorization(center: center)
        guard granted else {
            throw BridgeProcessorError.notificationPermissionDenied
        }

        let identifier = "notif_\(UUID().uuidString.lowercased())"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body ?? ""

        try await addNotification(
            center: center,
            request: UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
        return BridgeNotificationReceipt(notificationID: identifier, deliveredAt: Date())
    }

    private func requestAuthorization(center: UNUserNotificationCenter) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func addNotification(
        center: UNUserNotificationCenter,
        request: UNNotificationRequest
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
final class LocalBridgeProcessor {
    private let deviceID: String
    private let collector: any ContextCollecting
    private let capturer: any WindowCapturing
    private let notifier: any LocalNotificationDelivering
    private let keyPressExecutor: any KeyPressExecuting
    private let textActions: any SetTextActionControlling
    private let policy: BridgeJobPolicy
    private let store: any BridgeResultStoring

    init(
        deviceID: String,
        collector: any ContextCollecting = AccessibilityContextCollector(),
        capturer: any WindowCapturing = ActiveWindowCapturer(),
        notifier: any LocalNotificationDelivering = UserNotificationDeliverer(),
        keyPressExecutor: any KeyPressExecuting = KeyPressActionExecutor(),
        textActions: any SetTextActionControlling,
        policy: BridgeJobPolicy = .default,
        store: any BridgeResultStoring
    ) {
        self.deviceID = deviceID
        self.collector = collector
        self.capturer = capturer
        self.notifier = notifier
        self.keyPressExecutor = keyPressExecutor
        self.textActions = textActions
        self.policy = policy
        self.store = store
    }

    func process(_ job: BridgeJobEnvelope, now: Date = Date()) async -> BridgeJobResultEnvelope {
        do {
            if let existingResult = try store.result(for: job.idempotencyKey) {
                return existingResult
            }

            try policy.validate(job, now: now)

            switch job.kind {
            case .contextGetActiveWindow:
                let snapshot = try collector.capture()
                return try persistedResult(
                    for: job,
                    status: .succeeded,
                    output: .context(snapshot),
                    completedAt: now
                )

            case .contextCaptureWindow:
                let snapshot = try collector.capture()
                let capture = try await capturer.capture(snapshot: snapshot)
                return try persistedResult(
                    for: job,
                    status: .succeeded,
                    output: .capture(capture.metadata),
                    completedAt: now
                )

            case .notificationShow:
                let receipt = try await notifier.deliver(
                    title: try requiredNotificationTitle(from: job),
                    body: job.input.body
                )
                return try persistedResult(
                    for: job,
                    status: .succeeded,
                    output: .notification(receipt),
                    completedAt: now
                )

            case .uiPressKey:
                let snapshot = try collector.capture()
                return try persistedResult(
                    for: job,
                    status: .pendingApproval,
                    output: .automationApproval(
                        automationApproval(
                            for: job,
                            snapshot: snapshot,
                            summary: "Press \(keySummary(from: job)) in the current focused window",
                            now: now
                        )
                    ),
                    completedAt: now
                )

            case .uiSetText:
                let text = try requiredText(from: job)
                try textActions.prepareAction(text: text)
                guard let pending = textActions.pendingPresentation else {
                    throw BridgeProcessorError.missingApprovalPresentation
                }
                let approval = BridgeApprovalRequest(
                    approvalID: "appr_\(UUID().uuidString.lowercased())",
                    actionID: pending.actionID,
                    risk: job.risk,
                    target: pending.target,
                    proposedText: pending.proposedText,
                    expiresAt: pending.createdAt.addingTimeInterval(SetTextActionPolicy.default.maximumApprovalAge)
                )
                return try persistedResult(
                    for: job,
                    status: .pendingApproval,
                    output: .approval(approval),
                    completedAt: now
                )

            case .uiClickElement:
                let snapshot = try collector.capture()
                return try persistedResult(
                    for: job,
                    status: .pendingApproval,
                    output: .automationApproval(
                        automationApproval(
                            for: job,
                            snapshot: snapshot,
                            summary: "Click \(clickTargetSummary(from: job)) in the current window",
                            now: now
                        )
                    ),
                    completedAt: now
                )
            }
        } catch let error as BridgeJobPolicyError {
            return storedErrorResult(
                for: job,
                status: error == .expiredJob ? .expired : .rejected,
                error: BridgeErrorPayload(code: error.bridgeCode, message: error.localizedDescription),
                completedAt: now
            )
        } catch {
            return result(
                for: job,
                status: .failed,
                error: BridgeErrorPayload(code: "processor_error", message: error.localizedDescription),
                completedAt: now
            )
        }
    }

    func completionResult(
        for job: BridgeJobEnvelope,
        actionResult: SetTextActionResult,
        completedAt: Date = Date()
    ) -> BridgeJobResultEnvelope {
        do {
            return try persistedResult(
                for: job,
                status: .succeeded,
                output: .actionResult(actionResult),
                completedAt: completedAt
            )
        } catch {
            return result(
                for: job,
                status: .failed,
                error: BridgeErrorPayload(code: "storage_error", message: error.localizedDescription),
                completedAt: completedAt
            )
        }
    }

    func automationCompletionResult(
        for job: BridgeJobEnvelope,
        approval: BridgeAutomationApprovalRequest,
        completedAt: Date = Date()
    ) -> BridgeJobResultEnvelope {
        do {
            switch job.kind {
            case .uiPressKey:
                let result = try keyPressExecutor.execute(
                    approval: approval,
                    input: job.input,
                    now: completedAt
                )
                return try persistedResult(
                    for: job,
                    status: .succeeded,
                    output: .keyPress(result),
                    completedAt: completedAt
                )
            case .uiClickElement:
                return try persistedResult(
                    for: job,
                    status: .rejected,
                    error: BridgeErrorPayload(
                        code: "executor_not_enabled",
                        message: "ui.click_element approval is modeled, but real click execution is not enabled yet."
                    ),
                    completedAt: completedAt
                )
            case .contextGetActiveWindow, .contextCaptureWindow, .notificationShow, .uiSetText:
                return try persistedResult(
                    for: job,
                    status: .rejected,
                    error: BridgeErrorPayload(
                        code: "not_automation_action",
                        message: "\(job.kind.rawValue) is not an automation approval action."
                    ),
                    completedAt: completedAt
                )
            }
        } catch {
            return storedErrorResult(
                for: job,
                status: .failed,
                error: BridgeErrorPayload(code: "automation_execution_failed", message: error.localizedDescription),
                completedAt: completedAt
            )
        }
    }

    func rejectionResult(
        for job: BridgeJobEnvelope,
        code: String = "user_cancelled",
        message: String = "User cancelled the approval",
        completedAt: Date = Date()
    ) -> BridgeJobResultEnvelope {
        storedErrorResult(
            for: job,
            status: .rejected,
            error: BridgeErrorPayload(code: code, message: message),
            completedAt: completedAt
        )
    }

    func unpostedResults(limit: Int = 50) -> [BridgeJobResultEnvelope] {
        (try? store.unpostedResults(limit: limit)) ?? []
    }

    func markPosted(jobID: String) {
        try? store.markPosted(jobID: jobID)
    }

    private func persistedResult(
        for job: BridgeJobEnvelope,
        status: BridgeJobStatus,
        output: BridgeJobOutput? = nil,
        error: BridgeErrorPayload? = nil,
        completedAt: Date
    ) throws -> BridgeJobResultEnvelope {
        let bridgeResult = result(
            for: job,
            status: status,
            output: output,
            error: error,
            completedAt: completedAt
        )
        try store.save(job: job, result: bridgeResult)
        return bridgeResult
    }

    private func storedErrorResult(
        for job: BridgeJobEnvelope,
        status: BridgeJobStatus,
        error: BridgeErrorPayload,
        completedAt: Date
    ) -> BridgeJobResultEnvelope {
        do {
            return try persistedResult(
                for: job,
                status: status,
                error: error,
                completedAt: completedAt
            )
        } catch {
            return result(
                for: job,
                status: .failed,
                error: BridgeErrorPayload(code: "storage_error", message: error.localizedDescription),
                completedAt: completedAt
            )
        }
    }

    private func requiredText(from job: BridgeJobEnvelope) throws -> String {
        guard let text = job.input.text else {
            throw BridgeJobPolicyError.invalidInput("ui.set_text requires input.text")
        }
        return text
    }

    private func requiredNotificationTitle(from job: BridgeJobEnvelope) throws -> String {
        let title = job.input.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw BridgeJobPolicyError.invalidInput("notification.show requires input.title")
        }
        return title
    }

    private func automationApproval(
        for job: BridgeJobEnvelope,
        snapshot: ContextSnapshot,
        summary: String,
        now: Date
    ) -> BridgeAutomationApprovalRequest {
        BridgeAutomationApprovalRequest(
            approvalID: "appr_\(UUID().uuidString.lowercased())",
            actionID: "act_\(UUID().uuidString.lowercased())",
            kind: job.kind,
            risk: job.risk,
            summary: summary,
            targetApp: snapshot.activeApp,
            targetWindow: snapshot.window,
            expiresAt: now.addingTimeInterval(SetTextActionPolicy.default.maximumApprovalAge)
        )
    }

    private func keySummary(from job: BridgeJobEnvelope) -> String {
        let modifiers = (job.input.modifiers ?? []).map { $0.lowercased() }
        let key = job.input.key ?? "key"
        return (modifiers + [key]).joined(separator: "+")
    }

    private func clickTargetSummary(from job: BridgeJobEnvelope) -> String {
        let role = job.input.elementRole?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = job.input.elementLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (role?.isEmpty == false ? role : nil, label?.isEmpty == false ? label : nil) {
        case let (role?, label?):
            return "\(role) labeled “\(label)”"
        case let (role?, nil):
            return "\(role)"
        case let (nil, label?):
            return "element labeled “\(label)”"
        case (nil, nil):
            return "target element"
        }
    }

    private func result(
        for job: BridgeJobEnvelope,
        status: BridgeJobStatus,
        output: BridgeJobOutput? = nil,
        error: BridgeErrorPayload? = nil,
        completedAt: Date
    ) -> BridgeJobResultEnvelope {
        BridgeJobResultEnvelope(
            jobID: job.jobID,
            protocolVersion: BridgeProtocol.currentVersion,
            deviceID: deviceID,
            status: status,
            output: output,
            error: error,
            completedAt: completedAt,
            idempotencyKey: job.idempotencyKey
        )
    }
}

enum BridgeProcessorError: LocalizedError {
    case missingApprovalPresentation
    case notificationPermissionDenied

    var errorDescription: String? {
        switch self {
        case .missingApprovalPresentation:
            "The text action did not produce an approval presentation."
        case .notificationPermissionDenied:
            "Notification permission is required to show local notifications."
        }
    }
}
