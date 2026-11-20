import Foundation
import XCTest
@testable import GooglePlayNewGames

final class GameAPIClientTests: XCTestCase {
    func testListUsesSingleCasualFirstPageRequestAndAuthenticationHeader() async throws {
        let transport = StubTransport(body: listBody(category: GameCategory.casual.rawValue), status: 200)
        let client = GameAPIClient(credentialStore: StubCredentialStore(value: "fake-key"), transport: transport)
        let page = try await client.fetchPage(
            category: .casual,
            page: 1,
            per: 100
        )
        let request = try XCTUnwrap(transport.lastRequest)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "playapi.info")
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.path, "/api/v1/new")
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value!) }),
            ["category": "GAME_CASUAL", "page": "1", "per": "100"]
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "fake-key")
        XCTAssertEqual(page.results.first?.category.id, GameCategory.casual.rawValue)
    }

    func testAuthenticationFailureIsClassifiedWithoutLeakingCredential() async {
        let key = "fake-secret-never-return"
        let client = GameAPIClient(
            credentialStore: StubCredentialStore(value: key),
            transport: StubTransport(body: Data("secret response".utf8), status: 401)
        )

        do {
            _ = try await client.fetchPage(category: .casual, page: 1, per: 1)
            XCTFail("Expected authentication error")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .authentication)
            XCTAssertFalse(String(describing: error).contains(key))
            XCTAssertFalse(String(describing: error).contains("secret response"))
        }
    }

    func testInvalidCategoryAndMalformedResponseFailAsContractOrDecodeError() async {
        let invalidCategory = Data(#"{"ok":true,"total":1,"page":1,"per":1,"pages":1,"results":[{"id":"x","title":"X","icon":"https://example.com/i","category":{"id":"GAME_ARCADE","name":"Arcade"},"released":"2026-11-12T00:00:00Z"}]}"#.utf8)
        let invalidClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: invalidCategory, status: 200))
        do {
            _ = try await invalidClient.fetchPage(category: .puzzle, page: 1, per: 1)
            XCTFail("Expected contract violation")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .contractViolation)
        }

        let wrongType = Data(#"{"ok":true,"total":"one","page":1,"per":1,"pages":1,"results":[]}"#.utf8)
        let wrongTypeClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: wrongType, status: 200))
        do {
            _ = try await wrongTypeClient.fetchPage(category: .puzzle, page: 1, per: 1)
            XCTFail("Expected decoding error")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .decoding)
        }

        let missingFieldClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: Data(#"{"ok":true,"results":[]}"#.utf8), status: 200))
        do {
            _ = try await missingFieldClient.fetchPage(category: .puzzle, page: 1, per: 1)
            XCTFail("Expected contract violation")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .contractViolation)
        }
    }

    func testDetailSuccessValidatesRequestedIDAnd404IsDistinct() async throws {
        let detail = Data(#"{"ok":true,"app":{"id":"pkg.sample","title":"Sample","title_lang":"en","summary":"S","description":"D","recent_changes":null,"category":{"id":"GAME_CASUAL","name":"Casual"},"released":"2026-11-12T00:00:00Z","updated":"2026-11-13T00:00:00Z","version":"1","android_min":"8","developer":{},"installs":{},"rating":{},"status":{},"pricing":{},"content_rating":{},"media":{}}}"#.utf8)
        let client = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: detail, status: 200))
        let loadedDetail = try await client.fetchDetail(id: "pkg.sample")
        XCTAssertEqual(loadedDetail.id, "pkg.sample")
        XCTAssertNil(loadedDetail.recentChanges)

        let wrongID = Data(String(decoding: detail, as: UTF8.self).replacingOccurrences(of: "pkg.sample", with: "other.sample").utf8)
        let wrongClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: wrongID, status: 200))
        do {
            _ = try await wrongClient.fetchDetail(id: "pkg.sample")
            XCTFail("Expected ID mismatch")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .contractViolation)
        }

        let notFoundClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: Data(), status: 404))
        do {
            _ = try await notFoundClient.fetchDetail(id: "pkg.missing")
            XCTFail("Expected not found")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .notFound)
        }

        let serverErrorClient = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: StubTransport(body: Data(), status: 503))
        do {
            _ = try await serverErrorClient.fetchDetail(id: "pkg.sample")
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .httpStatus(503))
        }
    }

    func testCancellationPropagatesAndMissingCredentialDoesNotRequest() async {
        let transport = StubTransport(body: listBody(), status: 200, failure: URLError(.cancelled))
        let client = GameAPIClient(credentialStore: StubCredentialStore(value: "key"), transport: transport)
        do {
            _ = try await client.fetchPage(category: .puzzle, page: 1, per: 1)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let noCredentialTransport = StubTransport(body: listBody(), status: 200)
        let noCredentialClient = GameAPIClient(credentialStore: StubCredentialStore(value: nil), transport: noCredentialTransport)
        do {
            _ = try await noCredentialClient.fetchPage(category: .puzzle, page: 1, per: 1)
            XCTFail("Expected missing credential")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .missingCredential)
            XCTAssertNil(noCredentialTransport.lastRequest)
        }
    }

    private func listBody(category: String = "GAME_PUZZLE") -> Data {
        let name = category == "GAME_PUZZLE" ? "Puzzle" : "Casual"
        return Data(#"{"ok":true,"total":1,"page":1,"per":1,"pages":1,"results":[{"id":"pkg.sample","title":"Sample","icon":"https://example.com/icon.png","category":{"id":"\#(category)","name":"\#(name)"},"released":"2026-11-12T00:00:00Z"}]}"#.utf8)
    }
}

private struct StubCredentialStore: CredentialStoring {
    let value: String?
    func save(_ credential: String) throws {}
    func load() throws -> String? { value }
}

private final class StubTransport: GameAPITransport, @unchecked Sendable {
    private let lock = NSLock()
    private let body: Data
    private let status: Int
    private let failure: Error?
    private var storedRequest: URLRequest?

    init(body: Data, status: Int, failure: Error? = nil) {
        self.body = body
        self.status = status
        self.failure = failure
    }

    var lastRequest: URLRequest? {
        lock.withLock { storedRequest }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        record(request)
        if let failure { throw failure }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }

    private func record(_ request: URLRequest) {
        lock.withLock { storedRequest = request }
    }
}
