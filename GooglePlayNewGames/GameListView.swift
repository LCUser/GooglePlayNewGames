import Combine
import SwiftUI

@MainActor
final class GameListViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([GameSummary])
        case empty
        case failed
    }

    @Published private(set) var state: State = .loading

    private let gameCatalog: any GameCatalogProviding
    private var hasStartedLoading = false

    init(gameCatalog: any GameCatalogProviding) {
        self.gameCatalog = gameCatalog
    }

    func loadOnColdLaunch() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true

        do {
            let games = try await gameCatalog.loadGames(now: Date())
            state = games.isEmpty ? .empty : .loaded(games)
        } catch is CancellationError {
            state = .failed
        } catch {
            state = .failed
        }
    }
}

struct GameListView: View {
    @StateObject private var viewModel: GameListViewModel

    init(gameCatalog: any GameCatalogProviding) {
        _viewModel = StateObject(wrappedValue: GameListViewModel(gameCatalog: gameCatalog))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(games):
                List(games) { game in
                    NavigationLink {
                        GameDetailPlaceholderView(gameID: game.id)
                    } label: {
                        GameRowView(game: game)
                    }
                }
                .listStyle(.plain)
            case .empty:
                Text("No games found")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                Text("Unable to load games")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("New Games")
        .task {
            await viewModel.loadOnColdLaunch()
        }
    }
}

private struct GameRowView: View {
    let game: GameSummary

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: game.iconURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(game.categoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(game.releasedAt, format: .dateTime.year().month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        GameListView(gameCatalog: PreviewGameCatalog())
    }
}

private struct PreviewGameCatalog: GameCatalogProviding {
    func loadGames(now: Date) async throws -> [GameSummary] {
        []
    }
}
