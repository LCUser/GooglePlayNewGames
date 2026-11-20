import SwiftUI

struct AppDependencies {
    let makeRootView: @MainActor () -> AnyView
    let credentialStore: any CredentialStoring

    init(
        makeRootView: @escaping @MainActor () -> AnyView,
        credentialStore: any CredentialStoring = EncryptedCredentialStore()
    ) {
        self.makeRootView = makeRootView
        self.credentialStore = credentialStore
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
