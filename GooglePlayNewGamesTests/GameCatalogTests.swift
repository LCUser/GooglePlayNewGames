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

    func testLoadFiltersDeduplicatesAndSortsBothCategories() async throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T16:00:00Z"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-13T16:00:00Z"))
        let puzzle = [
            summary("old", released: start.addingTimeInterval(-1), category: .puzzle),
            summary("duplicate", released: start.addingTimeInterval(100), category: .puzzle),
            summary("same-b", released: start.addingTimeInterval(200), category: .puzzle),
            summary("end", released: end, category: .puzzle)
        ]
        let casual = [
            summary("duplicate", released: start.addingTimeInterval(300), category: .casual),
            summary("same-a", released: start.addingTimeInterval(200), category: .casual),
            summary("last-valid", released: end.addingTimeInterval(-1), category: .casual)
        ]
        let fetcher = StubPageFetcher(responses: [
            PageKey(category: .puzzle, page: 1): page(category: .puzzle, results: puzzle),
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
        XCTAssertEqual(Set(requests.map(\.category)), Set(GameCategory.allCases))
        XCTAssertTrue(requests.allSatisfy { $0.since == "2026-11-03" && $0.until == "2026-11-14" })
    }

    func testPaginationIsSequentialAndRejectsInconsistentMetadata() async {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let records = (0..<101).map {
            summary("puzzle-\($0)", released: Date(timeIntervalSince1970: 1_800_000_000), category: .puzzle)
        }
        let fetcher = StubPageFetcher(responses: [
            PageKey(category: .puzzle, page: 1): page(category: .puzzle, results: Array(records.prefix(100)), total: 101),
            PageKey(category: .puzzle, page: 2): page(category: .puzzle, number: 2, results: Array(records.suffix(1)), total: 101),
            PageKey(category: .casual, page: 1): page(category: .casual, results: [], total: 0)
        ])
        let catalog = GameCatalog(pageFetcher: fetcher, timeZone: timeZone)

        do {
            let games = try await catalog.loadGames(now: Date(timeIntervalSince1970: 1_800_000_000))
            XCTAssertTrue(games.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await fetcher.requests().filter { $0.category == .puzzle }
        XCTAssertEqual(requests.map(\.page), [1, 2])

        let inconsistentFetcher = StubPageFetcher(responses: [
            PageKey(category: .puzzle, page: 1): page(category: .puzzle, results: Array(records.prefix(100)), total: 101),
            PageKey(category: .puzzle, page: 2): GamePageDTO(
                results: Array(records.suffix(1)),
                total: 102,
                page: 2,
                per: 100,
                pages: 2
            ),
            PageKey(category: .casual, page: 1): page(category: .casual, results: [], total: 0)
        ])
        let inconsistentCatalog = GameCatalog(pageFetcher: inconsistentFetcher, timeZone: timeZone)
        do {
            _ = try await inconsistentCatalog.loadGames(now: Date(timeIntervalSince1970: 1_800_000_000))
            XCTFail("Expected inconsistent pagination metadata to fail")
        } catch {
            XCTAssertEqual(error as? GameCatalogError, .invalidPagination)
        }
    }

    func testAnyCategoryFailureFailsTheWholeLoadAndRejectsOverLimit() async {
        let failingFetcher = StubPageFetcher(
            responses: [
                PageKey(category: .puzzle, page: 1): page(
                    category: .puzzle,
                    results: [summary("partial", released: Date(), category: .puzzle)]
                )
            ],
            failures: [PageKey(category: .casual, page: 1)]
        )
        let catalog = GameCatalog(pageFetcher: failingFetcher, timeZone: TimeZone(secondsFromGMT: 0)!)
        do {
            _ = try await catalog.loadGames(now: Date())
            XCTFail("Expected a category failure")
        } catch {
            XCTAssertEqual(error as? GameAPIError, .transport)
        }

        let overLimitFetcher = StubPageFetcher(responses: [
            PageKey(category: .puzzle, page: 1): GamePageDTO(
                results: (0..<100).map {
                    summary("over-\($0)", released: Date(), category: .puzzle)
                },
                total: 10_001,
                page: 1,
                per: 100,
                pages: 100
            ),
            PageKey(category: .casual, page: 1): page(category: .casual, results: [], total: 0)
        ])
        let overLimitCatalog = GameCatalog(pageFetcher: overLimitFetcher, timeZone: TimeZone(secondsFromGMT: 0)!)
        do {
            _ = try await overLimitCatalog.loadGames(now: Date())
            XCTFail("Expected the API result limit to fail the whole load")
        } catch {
            XCTAssertEqual(error as? GameCatalogError, .resultLimitExceeded)
        }
    }

    func testCancellationAndSupersededLoadCannotReturnResults() async throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let oldNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let fetcher = SupersedingPageFetcher(blockedSince: "2026-11-04")
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
                PageKey(category: .puzzle, page: 1): page(category: .puzzle, results: [], total: 0),
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
    var since: String = ""
    var until: String = ""
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
        since: String,
        until: String,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO {
        let key = PageKey(category: category, page: page, since: since, until: until)
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
    private let blockedSince: String
    private var blockedRequests = 0
    private var waitingRequests: [CheckedContinuation<GamePageDTO, Error>] = []
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(blockedSince: String) {
        self.blockedSince = blockedSince
    }

    func fetchPage(
        category: GameCategory,
        since: String,
        until: String,
        page: Int,
        per: Int
    ) async throws -> GamePageDTO {
        guard since == blockedSince else {
            return GamePageDTO(results: [], total: 0, page: 1, per: 100, pages: 0)
        }
        return try await withCheckedThrowingContinuation { continuation in
            blockedRequests += 1
            waitingRequests.append(continuation)
            if blockedRequests == 2 {
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
    }

    func waitUntilOldLoadIsBlocked() async {
        guard blockedRequests < 2 else { return }
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
