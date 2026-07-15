import Foundation
import Security

protocol BridgeTokenStoring {
    func loadToken() -> String
    func saveToken(_ token: String) throws
}

struct KeychainBridgeTokenStore: BridgeTokenStoring {
    private let service = "com.soumya.eclipse-mac.bridge"
    private let account = "bearer-token"

    func loadToken() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw BridgeTokenStoreError.keychain(status: updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw BridgeTokenStoreError.keychain(status: addStatus)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum BridgeTokenStoreError: LocalizedError, Equatable {
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Could not save the bridge token to Keychain. Status: \(status)."
        }
    }
}

struct InMemoryBridgeTokenStore: BridgeTokenStoring {
    private final class Box {
        var token: String

        init(token: String) {
            self.token = token
        }
    }

    private let box: Box

    init(token: String = "") {
        box = Box(token: token)
    }

    func loadToken() -> String {
        box.token
    }

    func saveToken(_ token: String) throws {
        box.token = token
    }
}
