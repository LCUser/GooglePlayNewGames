import Foundation

struct ReleaseDateWindow: Equatable, Sendable {
    let startInclusive: Date
    let endExclusive: Date

    init?(now: Date, calendar: Calendar, timeZone: TimeZone) {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        guard let today = localCalendar.dateInterval(of: .day, for: now)?.start,
              let start = localCalendar.date(byAdding: .day, value: -15, to: today),
              let end = localCalendar.date(byAdding: .day, value: -6, to: today),
              start < end else {
            return nil
        }
        startInclusive = start
        endExclusive = end
    }

    func contains(_ date: Date) -> Bool {
        startInclusive <= date && date < endExclusive
    }

    func apiDateRange() -> (since: String, until: String)? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let first = utc.date(byAdding: .day, value: -1, to: utc.startOfDay(for: startInclusive)),
              let lastBase = utc.date(byAdding: .nanosecond, value: -1, to: endExclusive),
              let last = utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: lastBase)) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: first), formatter.string(from: last))
    }
}

struct GameSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let iconURL: URL
    let categoryID: String
    let categoryName: String
    let releasedAt: Date
}

protocol GameCatalogProviding: Sendable {
    func loadGames(now: Date) async throws -> [GameSummary]
}

enum GameCatalogError: Error, Equatable {
    case invalidDateWindow
    case invalidPagination
    case resultLimitExceeded
}

actor GameCatalog: GameCatalogProviding {
    private static let pageSize = 100
    private static let maximumResults = 10_000

    private let pageFetcher: any GamePageFetching
    private let calendar: Calendar
    private let timeZone: TimeZone
    private var loadGeneration: UInt64 = 0

    init(
        pageFetcher: any GamePageFetching,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.pageFetcher = pageFetcher
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func loadGames(now: Date = Date()) async throws -> [GameSummary] {
        loadGeneration &+= 1
        let generation = loadGeneration
        try Task.checkCancellation()

        guard let window = ReleaseDateWindow(now: now, calendar: calendar, timeZone: timeZone),
              let apiRange = window.apiDateRange() else {
            throw GameCatalogError.invalidDateWindow
        }

        do {
            async let puzzle = Self.fetchAllPages(
                using: pageFetcher,
                category: .puzzle,
                since: apiRange.since,
                until: apiRange.until
            )
            async let casual = Self.fetchAllPages(
                using: pageFetcher,
                category: .casual,
                since: apiRange.since,
                until: apiRange.until
            )
            let combined = try await puzzle + casual
            try Task.checkCancellation()
            guard generation == loadGeneration else { throw CancellationError() }

            var uniqueByID: [String: GameSummary] = [:]
            for item in combined where window.contains(item.released) {
                guard let iconURL = URL(string: item.icon), iconURL.scheme == "https" else {
                    throw GameAPIError.contractViolation
                }
                let summary = GameSummary(
                    id: item.id,
                    title: item.title,
                    iconURL: iconURL,
                    categoryID: item.category.id,
                    categoryName: item.category.name,
                    releasedAt: item.released
                )
                if let current = uniqueByID[item.id] {
                    if summary.releasedAt > current.releasedAt {
                        uniqueByID[item.id] = summary
                    }
                } else {
                    uniqueByID[item.id] = summary
                }
            }
            return uniqueByID.values.sorted {
                if $0.releasedAt != $1.releasedAt {
                    return $0.releasedAt > $1.releasedAt
                }
                return $0.id < $1.id
            }
        } catch {
            if generation != loadGeneration || Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private nonisolated static func fetchAllPages(
        using pageFetcher: any GamePageFetching,
        category: GameCategory,
        since: String,
        until: String
    ) async throws -> [GameSummaryDTO] {
        let first = try await pageFetcher.fetchPage(
            category: category,
            since: since,
            until: until,
            page: 1,
            per: pageSize
        )
        try Task.checkCancellation()
        guard first.page == 1,
              first.per == pageSize,
              first.total >= 0,
              first.total <= maximumResults else {
            if first.total > maximumResults {
                throw GameCatalogError.resultLimitExceeded
            }
            throw GameCatalogError.invalidPagination
        }
        let expectedPages = first.total == 0 ? 0 : (first.total + pageSize - 1) / pageSize
        guard first.pages == expectedPages,
              first.results.count == min(pageSize, first.total) else {
            throw GameCatalogError.invalidPagination
        }

        var results = first.results
        guard expectedPages > 1 else { return results }

        for pageNumber in 2...expectedPages {
            try Task.checkCancellation()
            let page = try await pageFetcher.fetchPage(
                category: category,
                since: since,
                until: until,
                page: pageNumber,
                per: pageSize
            )
            try Task.checkCancellation()
            let expectedCount = min(pageSize, first.total - (pageNumber - 1) * pageSize)
            guard page.page == pageNumber,
                  page.per == first.per,
                  page.total == first.total,
                  page.pages == first.pages,
                  page.results.count == expectedCount else {
                throw GameCatalogError.invalidPagination
            }
            results.append(contentsOf: page.results)
        }
        guard results.count == first.total else {
            throw GameCatalogError.invalidPagination
        }
        return results
    }
}
