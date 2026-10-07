import Foundation

#if canImport(Security) && !CONNECTION_TESTS
    import Security

    enum Credentials {
        private static func query(id: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.quby.client.server",
                kSecAttrAccount as String: id == "legacy" ? "connection" : "connection-\(id)",
            ]
        }
        static func load(id: String) -> SavedConnection? {
            var q = query(id: id)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
                let data = result as? Data
            else { return nil }
            return try? JSONDecoder().decode(SavedConnection.self, from: data)
        }
        static func save(_ connection: SavedConnection, id: String) throws {
            let data = try JSONEncoder().encode(connection)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let key = query(id: id)
            let status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var q = key
                for (attribute, value) in attributes { q[attribute] = value }
                guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CredentialError.save }
            } else if status != errSecSuccess {
                throw CredentialError.save
            }
        }
        static func remove(id: String) { SecItemDelete(query(id: id) as CFDictionary) }
        enum CredentialError: LocalizedError {
            case save
            var errorDescription: String? {
                "The login could not be saved in Keychain. Re-enter it next time."
            }
        }
    }
#endif
