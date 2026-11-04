import Foundation
import Security

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return L.t("Keychain error: \(text)", "Error del Llavero: \(text)")
    }
}

public enum Keychain {
    public static let service = "Gatebar"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func password(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let value = String(decoding: data, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    public static func hasPassword(for account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    public static func setPassword(_ password: String, for account: String) throws {
        let data = Data(password.utf8)
        let update = SecItemUpdate(baseQuery(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Gatebar: \(account)"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public static func deletePassword(for account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
