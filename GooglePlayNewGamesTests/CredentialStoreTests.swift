import Foundation
import XCTest
@testable import GooglePlayNewGames

final class CredentialStoreTests: XCTestCase {
    func testCredentialIsEncryptedAndCanBeReadBack() throws {
        let backend = MemorySecureDataStore()
        let store = EncryptedCredentialStore(secureDataStore: backend)
        let credential = "test-api-key-not-real"

        try store.save(credential)

        XCTAssertEqual(try store.load(), credential)
        XCTAssertNotEqual(backend.values["encrypted-api-key"], Data(credential.utf8))
        XCTAssertNotNil(backend.values["api-key-encryption-key"])
    }

    func testMissingCredentialReturnsNil() throws {
        let store = EncryptedCredentialStore(secureDataStore: MemorySecureDataStore())

        XCTAssertNil(try store.load())
    }

    func testEmptyCredentialIsRejected() {
        let store = EncryptedCredentialStore(secureDataStore: MemorySecureDataStore())

        XCTAssertThrowsError(try store.save("")) { error in
            XCTAssertEqual(error as? CredentialStoreError, .invalidConfiguration)
        }
    }

    func testCorruptedCiphertextReturnsSanitizedError() throws {
        let backend = MemorySecureDataStore()
        try backend.write(Data("invalid".utf8), account: "encrypted-api-key")
        try backend.write(Data(repeating: 1, count: 32), account: "api-key-encryption-key")
        let store = EncryptedCredentialStore(secureDataStore: backend)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? CredentialStoreError, .secureStorageFailure)
            XCTAssertFalse(String(describing: error).contains("invalid"))
        }
    }

    func testLocalConfigurationRequiresOneNonemptyLine() throws {
        XCTAssertEqual(try LocalCredentialBootstrap.validate("local-test-key"), "local-test-key")
        XCTAssertThrowsError(try LocalCredentialBootstrap.validate(""))
        XCTAssertThrowsError(try LocalCredentialBootstrap.validate("first\nsecond"))
    }
}

private final class MemorySecureDataStore: SecureDataStoring {
    var values: [String: Data] = [:]

    func read(account: String) throws -> Data? {
        values[account]
    }

    func write(_ data: Data, account: String) throws {
        values[account] = data
    }
}
