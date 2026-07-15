import SwiftUI

enum AssistantState: String, CaseIterable, Codable, Sendable {
    case idle
    case listening
    case thinking
    case acting
    case waitingForApproval = "waiting_for_approval"
    case error

    var title: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .acting: "Acting"
        case .waitingForApproval: "Needs approval"
        case .error: "Something went wrong"
        }
    }

    var debugMessage: String {
        switch self {
        case .idle: "Ready on this Mac"
        case .listening: "Listening is a visual state only for now"
        case .thinking: "Preparing a safe local capability"
        case .acting: "Executing an approved local action"
        case .waitingForApproval: "Review is required before anything changes"
        case .error: "Open diagnostics for details"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "circle.hexagongrid.fill"
        case .listening: "waveform.circle.fill"
        case .thinking: "sparkles"
        case .acting: "cursorarrow.motionlines"
        case .waitingForApproval: "checkmark.shield.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: EclipseTheme.ink
        case .listening: EclipseTheme.violet
        case .thinking: EclipseTheme.blue
        case .acting: EclipseTheme.mint
        case .waitingForApproval: EclipseTheme.amber
        case .error: EclipseTheme.coral
        }
    }

    var nextDebugState: AssistantState {
        guard let index = Self.allCases.firstIndex(of: self) else { return .idle }
        return Self.allCases[(index + 1) % Self.allCases.count]
    }
}
