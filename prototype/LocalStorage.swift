import Foundation
import Security

enum MaieError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct LocalSizeLimitError: LocalizedError {
    var errorDescription: String? { "Local data exceeds the supported size." }
}

enum LocalStorage {
    static let defaultReadLimit = 8_000_000
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["MAIE_DATA_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultRoot
    }
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Maie", isDirectory: true)
    }
    static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func write<T: Encodable>(_ value: T, to url: URL, limit: Int? = nil) throws {
        let data = try JSONEncoder().encode(value)
        if let limit, data.count > limit { throw LocalSizeLimitError() }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read<T: Decodable>(_ type: T.Type, at url: URL, limit: Int = defaultReadLimit) throws -> T {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw MaieError.message("Local data exceeds the supported size.") }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum CredentialVault {
    static let service = "local.maie.prototype.openai"
    static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else {
                throw MaieError.message("Could not save credentials in macOS Keychain.")
            }
        } else if status != errSecSuccess { throw MaieError.message("Could not update macOS Keychain.") }
    }
    static func read(account: String) throws -> Data? {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MaieError.message("Could not read macOS Keychain.") }
        return result as? Data
    }
    static func delete(account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MaieError.message("Could not remove credentials from macOS Keychain.")
        }
    }
}
