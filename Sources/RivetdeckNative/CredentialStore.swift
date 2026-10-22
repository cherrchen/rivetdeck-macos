import Foundation
import Security

/// Credentials stay in the login Keychain. Never place keys in UserDefaults or diagnostics.
enum CredentialStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.rivetdeck.native", kSecAttrAccount as String: "deepseek-official"] }
    static func save(_ key: String) throws {
        let value = Data(key.utf8), status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = value
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    static func load() throws -> String? {
        var item = query; item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
