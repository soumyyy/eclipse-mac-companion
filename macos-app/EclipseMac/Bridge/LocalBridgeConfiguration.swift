import Foundation

struct LocalBridgeConfiguration: Equatable, Sendable {
    static let defaultBaseURLString = "http://127.0.0.1:8765"

    var baseURLString: String

    init(baseURLString: String = LocalBridgeConfiguration.defaultBaseURLString) {
        self.baseURLString = baseURLString
    }

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct LocalBridgeConfigurationStore {
    private static let baseURLKey = "localBridge.baseURL"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LocalBridgeConfiguration {
        LocalBridgeConfiguration(
            baseURLString: defaults.string(forKey: Self.baseURLKey) ?? LocalBridgeConfiguration.defaultBaseURLString
        )
    }

    func save(_ configuration: LocalBridgeConfiguration) {
        defaults.set(configuration.baseURLString, forKey: Self.baseURLKey)
    }
}
