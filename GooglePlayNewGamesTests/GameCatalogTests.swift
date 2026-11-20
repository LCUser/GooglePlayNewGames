import Foundation
import XCTest
@testable import GooglePlayNewGames

final class GameCatalogTests: XCTestCase {
    func testWindowUsesLocalCalendarDaysAndHalfOpenBounds() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let window = try XCTUnwrap(ReleaseDateWindow(now: now, calendar: calendar, timeZone: timeZone))
        let expectedStart = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T16:00:00Z"))
        let expectedEnd = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-13T16:00:00Z"))

        XCTAssertEqual(window.startInclusive, expectedStart)
        XCTAssertEqual(window.endExclusive, expectedEnd)
        XCTAssertTrue(window.contains(expectedStart))
        XCTAssertTrue(window.contains(expectedEnd.addingTimeInterval(-0.001)))
        XCTAssertFalse(window.contains(expectedStart.addingTimeInterval(-0.001)))
        XCTAssertFalse(window.contains(expectedEnd))

        let range = try XCTUnwrap(window.apiDateRange())
        XCTAssertEqual(range.since, "2026-11-03")
        XCTAssertEqual(range.until, "2026-11-14")
    }

    func testWindowUsesCalendarArithmeticAcrossDaylightSavingTransition() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-15T16:00:00Z"))
        let window = try XCTUnwrap(
            ReleaseDateWindow(now: now, calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
        )
        let actualDuration = window.endExclusive.timeIntervalSince(window.startInclusive)
        let expectedDuration: TimeInterval = 9 * 24 * 60 * 60 - 60 * 60
        XCTAssertEqual(actualDuration, expectedDuration, accuracy: 0.001)
    }

    func testLoadRequestsOnlyCasualOnceThenFiltersAndSorts() async throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T16:00:00Z"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-13T16:00:00Z"))
        let casual = [
            summary("duplicate", released: start.addingTimeInterval(300), category: .casual),
            summary("same-a", released: start.addingTimeInterval(200), category: .casual),
            summary("same-b", released: start.addingTimeInterval(200), category: .casual),
            summary("last-valid", released: end.addingTimeInterval(-1), category: .casual),
            summary("old", released: start.addingTimeInterval(-1), category: .casual),
            summary("end", released: end, category: .casual)
        ]
        let fetcher = StubPageFetcher(responses: [
            PageKey(category: .casual, page: 1): page(category: .casual, results: casual)
        ])
        let catalog = GameCatalog(
            pageFetcher: fetcher,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )

        let games = try await catalog.loadGames(now: now)

        XCTAssertEqual(games.map(\.id), ["last-valid", "duplicate", "same-a", "same-b"])
        XCTAssertEqual(games.first(where: { $0.id == "duplicate" })?.categoryID, GameCategory.casual.rawValue)
        XCTAssertEqual(Set(games.map(\.id)).count, games.count)
        let requests = await fetcher.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.category, .casual)
        XCTAssertEqual(requests.first?.page, 1)
        XCTAssertTrue(requests.allSatisfy { $0.since == "2026-11-03" && $0.until == "2026-11-14" })
    }

    func testLoadsOnlyCasualFirstPageWhenMorePagesExist() async {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let released = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let records = (0..<101).map {
            summary("casual-\($0)", released: released, category: .casual)
        }
        let fetcher = StubPageFetcher(responses: [
            PageKey(category: .casual, page: 1): page(category: .casual, results: Array(records.prefix(100)), total: 101),
            PageKey(category: .casual, page: 2): page(category: .casual, number: 2, results: Array(records.suffix(1)), total: 101)
        ])
        let catalog = GameCatalog(pageFetcher: fetcher, timeZone: timeZone)

        do {
            let games = try await catalog.loadGames(now: now)
            XCTAssertEqual(games.count, 100)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await fetcher.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.category, .casual)
        XCTAssertEqual(requests.first?.page, 1)
    }

    func testCasualRequestFailureFailsTheLoad() async {
        let failingFetcher = StubPageFetcher(
            responses: [:],
            failures: [PageKey(category: .casual, page: 1)]
        )
        let catalog = GameCatalog(pageFetcher: failingFetcher, timeZone: TimeZone(secondsFromGMT: 0)!)
        do {
            _ = try await catalog.loadGames(now: Date())
            XCTFail("Expected a category failure")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .transport)
        }
    }

    func testCancellationAndSupersededLoadCannotReturnResults() async throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let oldNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let fetcher = SupersedingPageFetcher()
        let catalog = GameCatalog(pageFetcher: fetcher, timeZone: timeZone)
        let oldLoad = Task {
            try await catalog.loadGames(now: oldNow)
        }
        await fetcher.waitUntilOldLoadIsBlocked()

        let newerNow = oldNow.addingTimeInterval(24 * 60 * 60)
        let newerGames = try await catalog.loadGames(now: newerNow)
        XCTAssertTrue(newerGames.isEmpty)
        await fetcher.releaseOldLoad()
        do {
            _ = try await oldLoad.value
            XCTFail("A superseded load must not return stale results")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let immediateCatalog = GameCatalog(
            pageFetcher: StubPageFetcher(responses: [
                PageKey(category: .casual, page: 1): page(category: .casual, results: [], total: 0)
            ]),
            timeZone: timeZone
        )
        let cancelled = Task {
            try await immediateCatalog.loadGames(now: oldNow)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled load must not return")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func page(
        category: GameCategory,
        number: Int = 1,
        results: [GameSummaryDTO],
        total: Int? = nil
    ) -> GamePageDTO {
        let resolvedTotal = total ?? results.count
        let pages = resolvedTotal == 0 ? 0 : (resolvedTotal + 99) / 100
        return GamePageDTO(
            results: results,
            total: resolvedTotal,
            page: number,
            per: 100,
            pages: pages
        )
    }

    private func summary(_ id: String, released: Date, category: GameCategory) -> GameSummaryDTO {
        GameSummaryDTO(
            id: id,
            title: id,
            icon: "https://example.com/\(id).png",
            category: GameCategoryDTO(id: category.rawValue, name: category == .puzzle ? "Puzzle" : "Casual"),
            released: released
        )
    }
}

private struct PageKey: Hashable, Sendable {
    let category: GameCategory
    let page: Int
}

private actor StubPageFetcher: GamePageFetching {
    private let responses: [PageKey: GamePageDTO]
    private let failures: Set<PageKey>
    private var recordedRequests: [PageKey] = []

    init(responses: [PageKey: GamePageDTO], failures: Set<PageKey> = []) {
        self.responses = responses
        self.failures = failures
    }

    func fetchPage(
        category: GameCategory,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO {
        let key = PageKey(category: category, page: page)
        recordedRequests.append(key)
        let responseKey = PageKey(category: category, page: page)
        if failures.contains(responseKey) { throw GameAPIError.transport }
        guard per == 100, let response = responses[responseKey] else {
            throw GameCatalogError.invalidPagination
        }
        return response
    }

    func requests() -> [PageKey] {
        recordedRequests
    }
}

private actor SupersedingPageFetcher: GamePageFetching {
    private var blockedRequests = 0
    private var waitingRequests: [CheckedContinuation<GamePageDTO, Error>] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func fetchPage(
        category: GameCategory,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO {
        guard page == 1, category == .casual, blockedRequests == 0 else {
            return GamePageDTO(results: [], total: 0, page: 1, per: 100, pages: 0)
        }
        return try await withCheckedThrowingContinuation { continuation in
            blockedRequests += 1
            waitingRequests.append(continuation)
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilOldLoadIsBlocked() async {
        guard blockedRequests < 1 else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func releaseOldLoad() {
        let response = GamePageDTO(results: [], total: 0, page: 1, per: 100, pages: 0)
        waitingRequests.forEach { $0.resume(returning: response) }
        waitingRequests.removeAll()
    }
}
