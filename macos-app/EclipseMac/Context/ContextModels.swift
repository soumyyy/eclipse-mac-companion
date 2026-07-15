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

    enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case capturedAt = "captured_at"
        case activeApp = "active_app"
        case window
        case focusedElement = "focused_element"
        case selectedText = "selected_text"
        case visibleElements = "visible_elements"
        case screenshotReference = "screenshot_ref"
        case redactions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotID, forKey: .snapshotID)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(activeApp, forKey: .activeApp)
        try container.encode(window, forKey: .window)
        try container.encode(focusedElement, forKey: .focusedElement)
        try container.encode(selectedText, forKey: .selectedText)
        try container.encode(visibleElements, forKey: .visibleElements)
        try container.encode(screenshotReference, forKey: .screenshotReference)
        try container.encode(redactions, forKey: .redactions)
    }
}

struct ActiveApplication: Codable, Equatable, Sendable {
    let bundleID: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case name
    }
}

struct ActiveWindow: Codable, Equatable, Sendable {
    let id: UInt32?
    let title: String?
}

struct FocusedElement: Codable, Equatable, Sendable {
    let role: String
    let label: String?
    let valuePreview: String?

    enum CodingKeys: String, CodingKey {
        case role
        case label
        case valuePreview = "value_preview"
    }
}

struct VisibleElement: Codable, Equatable, Sendable {
    let role: String
    let label: String?
}

enum Redaction: String, Codable, Equatable, Sendable {
    case secureFields = "secure_fields"
    case privateNotifications = "private_notifications"
    case blockedApplication = "blocked_application"
    case blockedWindow = "blocked_window"
    case truncatedText = "truncated_text"
}
