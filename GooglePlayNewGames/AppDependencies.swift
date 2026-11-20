import SwiftUI

struct AppDependencies {
    let makeRootView: @MainActor () -> AnyView
    let credentialStore: any CredentialStoring
    let gameAPIClient: GameAPIClient

    init(
        makeRootView: @escaping @MainActor () -> AnyView,
        credentialStore: any CredentialStoring = EncryptedCredentialStore(),
        gameAPIClient: GameAPIClient? = nil
    ) {
        self.makeRootView = makeRootView
        self.credentialStore = credentialStore
        self.gameAPIClient = gameAPIClient ?? GameAPIClient(credentialStore: credentialStore)
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
