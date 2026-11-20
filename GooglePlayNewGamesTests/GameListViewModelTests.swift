import XCTest
@testable import GooglePlayNewGames

@MainActor
final class GameListViewModelTests: XCTestCase {
    func testColdLaunchLoadsOnceAndPublishesGames() async throws {
        let game = GameSummary(
            id: "sample.game",
            title: "Sample Game",
            iconURL: try XCTUnwrap(URL(string: "https://example.com/icon.png")),
            categoryID: "GAME_PUZZLE",
            categoryName: "Puzzle",
            releasedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let catalog = StubGameCatalog(result: .success([game]))
        let viewModel = GameListViewModel(gameCatalog: catalog)

        await viewModel.loadOnColdLaunch()
        await viewModel.loadOnColdLaunch()

        XCTAssertEqual(viewModel.state, .loaded([game]))
        let count = await catalog.loadCount
        XCTAssertEqual(count, 1)
    }

    func testSuccessfulEmptyLoadPublishesEmptyState() async {
        let catalog = StubGameCatalog(result: .success([]))
        let viewModel = GameListViewModel(gameCatalog: catalog)

        await viewModel.loadOnColdLaunch()

        XCTAssertEqual(viewModel.state, .empty)
        let count = await catalog.loadCount
        XCTAssertEqual(count, 1)
    }

    func testFailedLoadPublishesFailureState() async {
        let catalog = StubGameCatalog(result: .failure(StubError.failed))
        let viewModel = GameListViewModel(gameCatalog: catalog)

        await viewModel.loadOnColdLaunch()

        XCTAssertEqual(viewModel.state, .failed)
        let count = await catalog.loadCount
        XCTAssertEqual(count, 1)
    }
}

private enum StubError: Error {
    case failed
}

private actor StubGameCatalog: GameCatalogProviding {
    private let result: Result<[GameSummary], StubError>
    private(set) var loadCount = 0

    init(result: Result<[GameSummary], StubError>) {
        self.result = result
    }

    func loadGames(now: Date) async throws -> [GameSummary] {
        loadCount += 1
        return try result.get()
    }
}
