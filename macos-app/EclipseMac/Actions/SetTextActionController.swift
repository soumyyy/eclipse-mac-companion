import Combine
import Foundation

@MainActor
protocol SetTextActionControlling: AnyObject {
    var pendingPresentation: SetTextActionPresentation? { get }
    func prepareAction(text: String) throws
}

@MainActor
final class SetTextActionController: ObservableObject {
    static let demoText = "Hello from Eclipse Mac"

    @Published private(set) var pendingAction: PendingSetTextAction?
    @Published private(set) var result: SetTextActionResult?
    @Published private(set) var errorMessage: String?

    private let executor: SetTextActionExecutor

    var pendingPresentation: SetTextActionPresentation? {
        pendingAction?.presentation
    }

    init(executor: SetTextActionExecutor = SetTextActionExecutor()) {
        self.executor = executor
    }

    func prepareDemoAction() throws {
        try prepareAction(text: Self.demoText)
    }

    func prepareAction(text: String) throws {
        errorMessage = nil
        result = nil
        pendingAction = try executor.prepare(proposedText: text)
    }

    @discardableResult
    func approve() throws -> SetTextActionResult? {
        guard let pendingAction else { return nil }
        errorMessage = nil
        let actionResult = try executor.execute(pendingAction)
        result = actionResult
        self.pendingAction = nil
        return actionResult
    }

    func cancel() {
        pendingAction = nil
        errorMessage = nil
    }

    func record(error: Error) {
        pendingAction = nil
        result = nil
        errorMessage = error.localizedDescription
    }

    func reset() {
        pendingAction = nil
        result = nil
        errorMessage = nil
    }
}

extension SetTextActionController: SetTextActionControlling {}
