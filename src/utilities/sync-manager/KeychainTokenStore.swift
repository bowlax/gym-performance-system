import Foundation
import Security

/// Minimal Keychain string store for session secrets (#17).
///
/// Access and refresh tokens must not live in UserDefaults. Non-secret
/// connection metadata stays in `MemberConnectionStore`'s UserDefaults.
enum KeychainTokenStore {
    static let service = "com.gymperformance.memberConnection"

    static var accessTokenAccount = "accessToken"
    static var refreshTokenAccount = "refreshToken"

    /// Test override — when set, reads/writes go here instead of the Keychain.
    static var testStore: InMemoryTokenStore?

    static func string(forAccount account: String) -> String? {
        if let testStore {
            return testStore.string(forAccount: account)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func setString(_ value: String?, forAccount account: String) {
        if let testStore {
            testStore.setString(value, forAccount: account)
            return
        }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            return
        }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func clearSessionTokens() {
        setString(nil, forAccount: accessTokenAccount)
        setString(nil, forAccount: refreshTokenAccount)
    }
}

/// In-memory stand-in for Keychain in unit tests.
final class InMemoryTokenStore: @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func string(forAccount account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func setString(_ value: String?, forAccount account: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value, !value.isEmpty {
            values[account] = value
        } else {
            values.removeValue(forKey: account)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}
