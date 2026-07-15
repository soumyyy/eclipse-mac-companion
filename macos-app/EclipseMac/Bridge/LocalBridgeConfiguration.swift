import Foundation

struct LocalBridgeConfiguration: Equatable, Sendable {
    static let defaultBaseURLString = "http://127.0.0.1:8765"

    var baseURLString: String
    var bearerToken: String

    init(
        baseURLString: String = LocalBridgeConfiguration.defaultBaseURLString,
        bearerToken: String = ""
    ) {
        self.baseURLString = baseURLString
        self.bearerToken = bearerToken
    }

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var normalizedBearerToken: String? {
        let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct LocalBridgeConfigurationStore {
    private static let baseURLKey = "localBridge.baseURL"
    private static let bearerTokenKey = "localBridge.bearerToken"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LocalBridgeConfiguration {
        LocalBridgeConfiguration(
            baseURLString: defaults.string(forKey: Self.baseURLKey) ?? LocalBridgeConfiguration.defaultBaseURLString,
            bearerToken: defaults.string(forKey: Self.bearerTokenKey) ?? ""
        )
    }

    func save(_ configuration: LocalBridgeConfiguration) {
        defaults.set(configuration.baseURLString, forKey: Self.baseURLKey)
        defaults.set(configuration.bearerToken, forKey: Self.bearerTokenKey)
    }
}
