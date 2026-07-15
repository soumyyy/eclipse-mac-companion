import Combine
import Foundation

@MainActor
final class SetTextActionController: ObservableObject {
    static let demoText = "Hello from Eclipse Mac"

    @Published private(set) var pendingAction: PendingSetTextAction?
    @Published private(set) var result: SetTextActionResult?
    @Published private(set) var errorMessage: String?

    private let executor: SetTextActionExecutor

    init(executor: SetTextActionExecutor = SetTextActionExecutor()) {
        self.executor = executor
    }

    func prepareDemoAction() throws {
        errorMessage = nil
        result = nil
        pendingAction = try executor.prepare(proposedText: Self.demoText)
    }

    func approve() throws {
        guard let pendingAction else { return }
        errorMessage = nil
        result = try executor.execute(pendingAction)
        self.pendingAction = nil
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
