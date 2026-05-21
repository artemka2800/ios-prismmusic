//
//  KeychainStore.swift
//  PrismMusic
//
//  Thin wrapper over the Security framework for storing sensitive strings
//  (currently just the Yandex token). Synchronous on purpose — the values
//  are tiny so the convenience of `let token = KeychainStore.get(...)`
//  outweighs the cost.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.prism.music"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Delete any existing item first so we don't have to choose between Add and Update.
        SecItemDelete(query as CFDictionary)

        if value.isEmpty {
            return  // empty value == "clear the slot"
        }
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
