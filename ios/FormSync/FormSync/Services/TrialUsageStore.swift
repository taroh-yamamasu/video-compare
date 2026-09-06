import Foundation
import Security

protocol TrialUsageStoring {
    func loadUsedUses() -> Int?

    @discardableResult
    func saveUsedUses(_ usedUses: Int) -> Bool
}

struct TrialUsageStore: TrialUsageStoring {
    private let service: String
    private let account = "full-feature-trial-used-uses"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.yamamasutaro.formsync") {
        self.service = service
    }

    func loadUsedUses() -> Int? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              let usedUses = Int(value) else {
            return nil
        }

        return usedUses
    }

    @discardableResult
    func saveUsedUses(_ usedUses: Int) -> Bool {
        let data = Data(String(usedUses).utf8)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
