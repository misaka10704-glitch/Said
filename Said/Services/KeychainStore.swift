import Foundation
import Security

enum KeychainStore {
    private static let service = "com.misaka10704.Said"

    enum Key: String, CaseIterable {
        case azureSpeechKey = "AZURE_SPEECH_KEY"
        case azureSpeechRegion = "AZURE_SPEECH_REGION"
        case dashscopeKey = "DASHSCOPE_API_KEY"
        case dashscopeBase = "DASHSCOPE_BASE_URL"
        case ankiWebHostKey = "ANKIWEB_HOST_KEY"
        case ankiWebEndpoint = "ANKIWEB_ENDPOINT"
        case ankiWebAccount = "ANKIWEB_ACCOUNT"
    }

    static func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else {
            return defaultValue(for: key)
        }
        return s
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func exportSnapshot() -> [String: String] {
        var snapshot: [String: String] = [:]
        for key in Key.allCases {
            snapshot[key.rawValue] = get(key)
        }
        return snapshot
    }

    static func importSnapshot(_ snapshot: [String: String]) {
        for key in Key.allCases {
            guard let value = snapshot[key.rawValue] else { continue }
            set(value, for: key)
        }
    }

    private static func defaultValue(for key: Key) -> String {
        switch key {
        case .azureSpeechRegion: return "eastasia"
        case .dashscopeBase: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        default: return ""
        }
    }
}
