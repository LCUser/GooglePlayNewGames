import CryptoKit
import Darwin
import Foundation
import Security

enum CredentialStoreError: Error, Equatable {
    case invalidConfiguration
    case secureStorageFailure
    case encryptionFailure
}

protocol CredentialStoring: Sendable {
    func save(_ credential: String) throws
    func load() throws -> String?
}

protocol SecureDataStoring: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
}

struct EncryptedCredentialStore: CredentialStoring {
    private let secureDataStore: SecureDataStoring
    private let keyAccount = "api-key-encryption-key"
    private let credentialAccount = "encrypted-api-key"

    init(secureDataStore: SecureDataStoring = KeychainDataStore()) {
        self.secureDataStore = secureDataStore
    }

    func save(_ credential: String) throws {
        guard !credential.isEmpty, let plaintext = credential.data(using: .utf8) else {
            throw CredentialStoreError.invalidConfiguration
        }

        do {
            let key: SymmetricKey
            if let keyData = try secureDataStore.read(account: keyAccount) {
                key = SymmetricKey(data: keyData)
            } else {
                key = SymmetricKey(size: .bits256)
                try secureDataStore.write(key.withUnsafeBytes { Data($0) }, account: keyAccount)
            }

            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw CredentialStoreError.encryptionFailure
            }
            try secureDataStore.write(combined, account: credentialAccount)
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.secureStorageFailure
        }
    }

    func load() throws -> String? {
        do {
            guard let encryptedData = try secureDataStore.read(account: credentialAccount) else {
                return nil
            }
            guard let keyData = try secureDataStore.read(account: keyAccount) else {
                throw CredentialStoreError.secureStorageFailure
            }

            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
            guard let credential = String(data: plaintext, encoding: .utf8), !credential.isEmpty else {
                throw CredentialStoreError.invalidConfiguration
            }
            return credential
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.secureStorageFailure
        }
    }
}

struct KeychainDataStore: SecureDataStoring {
    private let service = "com.local.GooglePlayNewGames.credentials"

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.secureStorageFailure
        }
        return data
    }

    func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw CredentialStoreError.secureStorageFailure
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.secureStorageFailure
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum LocalCredentialBootstrap {
    static let environmentVariable = "PLAYAPI_KEY"

    static func validate(_ credential: String) throws -> String {
        guard !credential.isEmpty, !credential.contains(where: \.isNewline) else {
            throw CredentialStoreError.invalidConfiguration
        }
        return credential
    }

    static func importEnvironmentCredential(into store: CredentialStoring) -> CredentialStoreError? {
        guard let rawValue = getenv(environmentVariable) else {
            return nil
        }
        defer { _ = unsetenv(environmentVariable) }

        do {
            try store.save(validate(String(cString: rawValue)))
            return nil
        } catch let error as CredentialStoreError {
            return error
        } catch {
            return .secureStorageFailure
        }
    }
}
