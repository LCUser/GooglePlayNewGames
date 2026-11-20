import SwiftUI

struct AppDependencies {
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
        _ = LocalCredentialBootstrap.importEnvironmentCredential(into: credentialStore)
        return Self(
            makeRootView: { AnyView(AppRootView()) },
            credentialStore: credentialStore
        )
    }
}

struct AppRootView: View {
    var body: some View {
        NavigationStack {
            GameListPlaceholderView()
        }
    }
}
