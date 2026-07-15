import Foundation

struct ContextSnapshot: Codable, Equatable, Sendable {
    let snapshotID: String
    let capturedAt: Date
    let activeApp: ActiveApplication?
    let window: ActiveWindow?
    let focusedElement: FocusedElement?
    let selectedText: String?
    let visibleElements: [VisibleElement]
    let screenshotReference: String?
    let redactions: [Redaction]
}

struct ActiveApplication: Codable, Equatable, Sendable {
    let bundleID: String
    let name: String
}

struct ActiveWindow: Codable, Equatable, Sendable {
    let id: UInt32?
    let title: String?
}

struct FocusedElement: Codable, Equatable, Sendable {
    let role: String
    let label: String?
    let valuePreview: String?
}

struct VisibleElement: Codable, Equatable, Sendable {
    let role: String
    let label: String?
}

enum Redaction: String, Codable, Equatable, Sendable {
    case secureFields = "secure_fields"
    case privateNotifications = "private_notifications"
    case blockedApplication = "blocked_application"
    case truncatedText = "truncated_text"
}
