import Foundation
import os

enum GameCategory: String, CaseIterable, Sendable {
    case puzzle = "GAME_PUZZLE"
    case casual = "GAME_CASUAL"
}

enum GameAPIError: Error, Equatable {
    case missingCredential
    case authentication
    case notFound
    case httpStatus(Int)
    case transport
    case decoding
    case contractViolation
}

indirect enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

struct GameCategoryDTO: Decodable, Sendable {
    let id: String
    let name: String
}

struct GameSummaryDTO: Decodable, Sendable {
    let id: String
    let title: String
    let icon: String
    let category: GameCategoryDTO
    let released: Date
}

struct GamePageDTO: Decodable, Sendable {
    let results: [GameSummaryDTO]
    let total: Int
    let page: Int
    let per: Int
    let pages: Int
}

struct GameDetailDTO: Decodable, Sendable {
    let id: String
    let title: String
    let titleLanguage: String
    let summary: String
    let description: String
    let recentChanges: String?
    let category: GameCategoryDTO
    let released: Date
    let updated: Date
    let version: String
    let minimumAndroid: String
    let developer: JSONValue
    let installs: JSONValue
    let rating: JSONValue
    let status: JSONValue
    let pricing: JSONValue
    let contentRating: JSONValue
    let media: JSONValue

    enum CodingKeys: String, CodingKey {
        case id, title, summary, description, category, released, updated, version, developer, installs, rating, status, pricing, media
        case titleLanguage = "title_lang"
        case recentChanges = "recent_changes"
        case contentRating = "content_rating"
        case minimumAndroid = "android_min"
    }
}

private struct ListEnvelope: Decodable {
    let ok: Bool
    let results: [GameSummaryDTO]?
    let total: Int?
    let page: Int?
    let per: Int?
    let pages: Int?
}

private struct DetailEnvelope: Decodable {
    let ok: Bool
    let app: GameDetailDTO?
}

protocol GameAPITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

protocol GamePageFetching: Sendable {
    func fetchPage(
        category: GameCategory,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO
}

struct URLSessionGameAPITransport: GameAPITransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct GameAPIClient: GamePageFetching, Sendable {
    static let baseURL = URL(string: "https://playapi.info/api/v1")!
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "GooglePlayNewGames",
        category: "GameAPI"
    )

    private let credentialStore: any CredentialStoring
    private let transport: any GameAPITransport

    init(
        credentialStore: any CredentialStoring,
        transport: any GameAPITransport = URLSessionGameAPITransport()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
        }
        return decoder
    }

    func fetchPage(
        category: GameCategory,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO {
        guard (1...100).contains(per), page > 0 else {
            throw GameAPIError.contractViolation
        }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "category", value: category.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per", value: String(per))
        ]
        guard let url = components.url else { throw GameAPIError.contractViolation }
        let data = try await load(url: url)
        let envelope: ListEnvelope
        do {
            envelope = try Self.makeDecoder().decode(ListEnvelope.self, from: data)
        } catch {
            Self.logger.error("Response decoding failed for /new category=\(category.rawValue, privacy: .public) page=\(page, privacy: .public)")
            throw GameAPIError.decoding
        }
        guard envelope.ok,
              let results = envelope.results,
              let total = envelope.total,
              let responsePage = envelope.page,
              let responsePer = envelope.per,
              let pages = envelope.pages,
              results.allSatisfy({
                  $0.category.id == category.rawValue &&
                  !$0.category.name.isEmpty &&
                  !$0.id.isEmpty &&
                  !$0.title.isEmpty
              }) else {
            Self.logger.error("Response contract validation failed for /new category=\(category.rawValue, privacy: .public) page=\(page, privacy: .public)")
            throw GameAPIError.contractViolation
        }
        Self.logger.info("Request succeeded endpoint=/new category=\(category.rawValue, privacy: .public) page=\(page, privacy: .public) items=\(results.count, privacy: .public)")
        print("GameAPI response endpoint=/new category=\(category.rawValue)\n\(String(decoding: data, as: UTF8.self))")
        return GamePageDTO(results: results, total: total, page: responsePage, per: responsePer, pages: pages)
    }

    func fetchDetail(id: String) async throws -> GameDetailDTO {
        guard !id.isEmpty else { throw GameAPIError.contractViolation }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("app"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { throw GameAPIError.contractViolation }
        let data = try await load(url: url)
        let envelope: DetailEnvelope
        do {
            envelope = try Self.makeDecoder().decode(DetailEnvelope.self, from: data)
        } catch {
            Self.logger.error("Response decoding failed for /app")
            throw GameAPIError.decoding
        }
        guard envelope.ok, let app = envelope.app else {
            Self.logger.error("Response contract validation failed for /app")
            throw GameAPIError.contractViolation
        }
        guard app.id == id else {
            Self.logger.error("Response identity validation failed for /app")
            throw GameAPIError.contractViolation
        }
        guard GameCategory(rawValue: app.category.id) != nil,
              !app.category.name.isEmpty,
              !app.title.isEmpty,
              isObject(app.developer),
              isObject(app.installs),
              isObject(app.rating),
              isObject(app.status),
              isObject(app.pricing),
              isObject(app.contentRating),
              isObject(app.media) else {
            Self.logger.error("Response contract validation failed for /app")
            throw GameAPIError.contractViolation
        }
        Self.logger.info("Request succeeded endpoint=/app")
        return app
    }

    private func isObject(_ value: JSONValue) -> Bool {
        if case .object = value { return true }
        return false
    }

    private func load(url: URL) async throws -> Data {
        let endpoint = url.path
        let credential: String?
        do {
            credential = try credentialStore.load()
        } catch {
            Self.logger.error("Credential store read failed; request not sent endpoint=\(endpoint, privacy: .public)")
            throw GameAPIError.missingCredential
        }
        guard let credential, !credential.isEmpty else {
            Self.logger.error("Credential missing; request not sent endpoint=\(endpoint, privacy: .public)")
            throw GameAPIError.missingCredential
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(credential, forHTTPHeaderField: "X-API-Key")
        Self.logger.info("Request started method=GET endpoint=\(endpoint, privacy: .public)")
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
        } catch is CancellationError {
            Self.logger.info("Request cancelled endpoint=\(endpoint, privacy: .public)")
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            Self.logger.info("Request cancelled endpoint=\(endpoint, privacy: .public)")
            throw CancellationError()
        } catch let error as URLError {
            Self.logger.error("Request failed endpoint=\(endpoint, privacy: .public) reason=transport urlErrorCode=\(error.code.rawValue, privacy: .public)")
            throw GameAPIError.transport
        } catch {
            Self.logger.error("Request failed endpoint=\(endpoint, privacy: .public) reason=transport")
            throw GameAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("Request failed endpoint=\(endpoint, privacy: .public) reason=invalidResponse")
            throw GameAPIError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            Self.logger.error("Request failed endpoint=\(endpoint, privacy: .public) reason=httpStatus status=\(http.statusCode, privacy: .public)")
            if http.statusCode == 401 { throw GameAPIError.authentication }
            if http.statusCode == 404 { throw GameAPIError.notFound }
            throw GameAPIError.httpStatus(http.statusCode)
        }
        Self.logger.info("HTTP request succeeded endpoint=\(endpoint, privacy: .public) status=\(http.statusCode, privacy: .public)")
        return data
    }
}
