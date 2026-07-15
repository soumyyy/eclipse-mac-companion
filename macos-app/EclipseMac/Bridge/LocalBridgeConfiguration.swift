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
    private let tokenStore: any BridgeTokenStoring

    init(
        defaults: UserDefaults = .standard,
        tokenStore: any BridgeTokenStoring = KeychainBridgeTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    func load() -> LocalBridgeConfiguration {
        let token = tokenStore.loadToken()
        let migratedToken = token.isEmpty ? defaults.string(forKey: Self.bearerTokenKey) ?? "" : token
        if token.isEmpty, !migratedToken.isEmpty {
            try? tokenStore.saveToken(migratedToken)
            defaults.removeObject(forKey: Self.bearerTokenKey)
        }

        return LocalBridgeConfiguration(
            baseURLString: defaults.string(forKey: Self.baseURLKey) ?? LocalBridgeConfiguration.defaultBaseURLString,
            bearerToken: migratedToken
        )
    }

    func save(_ configuration: LocalBridgeConfiguration) throws {
        defaults.set(configuration.baseURLString, forKey: Self.baseURLKey)
        try tokenStore.saveToken(configuration.bearerToken)
        defaults.removeObject(forKey: Self.bearerTokenKey)
    }
}
