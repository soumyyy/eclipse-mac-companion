import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let defaultBaseURLString = "http://127.0.0.1:8642/v1"
    static let defaultConversationID = "eclipse-mac-main"

    @Published var hermesBaseURLString: String {
        didSet { defaults.set(hermesBaseURLString, forKey: Self.baseURLDefaultsKey) }
    }
    @Published var conversationID: String {
        didSet { defaults.set(conversationID, forKey: Self.conversationIDDefaultsKey) }
    }
    @Published private(set) var apiToken: String
    @Published private(set) var tokenStatus: String

    private let defaults: UserDefaults
    private let keychain: any KeychainStoring

    private static let baseURLDefaultsKey = "hermes.baseURL"
    private static let conversationIDDefaultsKey = "hermes.conversationID"
    private static let keychainService = "com.soumya.eclipse-mac.hermes"
    private static let keychainAccount = "api-server-key"

    init(
        defaults: UserDefaults = .standard,
        keychain: any KeychainStoring = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        hermesBaseURLString = defaults.string(forKey: Self.baseURLDefaultsKey) ?? Self.defaultBaseURLString
        conversationID = defaults.string(forKey: Self.conversationIDDefaultsKey) ?? Self.defaultConversationID
        do {
            let savedToken = try keychain.string(service: Self.keychainService, account: Self.keychainAccount) ?? ""
            apiToken = savedToken
            tokenStatus = savedToken.isEmpty ? "No API token saved" : "API token loaded from Keychain"
        } catch {
            apiToken = ""
            tokenStatus = error.localizedDescription
        }
    }

    var hermesBaseURL: URL? {
        URL(string: hermesBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var trimmedConversationID: String {
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultConversationID : trimmed
    }

    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(service: Self.keychainService, account: Self.keychainAccount)
            apiToken = ""
            tokenStatus = "API token removed from Keychain"
            return
        }
        try keychain.save(trimmed, service: Self.keychainService, account: Self.keychainAccount)
        apiToken = trimmed
        tokenStatus = "API token saved to Keychain"
    }

    func makeHermesClient(session: URLSession = .shared) throws -> HermesClient {
        guard let baseURL = hermesBaseURL else {
            throw HermesClientError.invalidBaseURL
        }
        return HermesClient(
            baseURL: baseURL,
            apiTokenProvider: { [weak self] in
                await MainActor.run { self?.apiToken ?? "" }
            },
            conversationIDProvider: { [weak self] in
                await MainActor.run { self?.trimmedConversationID ?? Self.defaultConversationID }
            },
            session: session
        )
    }
}
