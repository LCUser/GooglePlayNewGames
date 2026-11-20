import SwiftUI
import os

struct AppDependencies {
    private static let localAPIKey = "PLAYAPI_KEY="

    let makeRootView: @MainActor () -> AnyView
    let credentialStore: any CredentialStoring
    let gameAPIClient: GameAPIClient
    let gameCatalog: any GameCatalogProviding

    init(
        makeRootView: @escaping @MainActor () -> AnyView,
        credentialStore: any CredentialStoring = EncryptedCredentialStore(),
        gameAPIClient: GameAPIClient? = nil,
        gameCatalog: (any GameCatalogProviding)? = nil
    ) {
        let resolvedAPIClient = gameAPIClient ?? GameAPIClient(credentialStore: credentialStore)
        self.makeRootView = makeRootView
        self.credentialStore = credentialStore
        self.gameAPIClient = resolvedAPIClient
        self.gameCatalog = gameCatalog ?? GameCatalog(pageFetcher: resolvedAPIClient)
    }

    static var live: Self {
        let credentialStore = EncryptedCredentialStore()
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "GooglePlayNewGames",
            category: "CredentialBootstrap"
        )
        do {
            let apiKey = localAPIKey.hasPrefix("PLAYAPI_KEY=")
                ? String(localAPIKey.dropFirst("PLAYAPI_KEY=".count))
                : localAPIKey
            try credentialStore.save(apiKey)
            logger.info("Local API credential saved into encrypted storage")
        } catch {
            logger.error("Local API credential save failed: \(String(describing: error), privacy: .public)")
        }
        let apiClient = GameAPIClient(credentialStore: credentialStore)
        let catalog = GameCatalog(pageFetcher: apiClient)
        return Self(
            makeRootView: { AnyView(AppRootView(gameCatalog: catalog)) },
            credentialStore: credentialStore,
            gameAPIClient: apiClient,
            gameCatalog: catalog
        )
    }
}

struct AppRootView: View {
    let gameCatalog: any GameCatalogProviding

    var body: some View {
        NavigationStack {
            GameListView(gameCatalog: gameCatalog)
        }
    }
}
