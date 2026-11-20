import SwiftUI

struct AppDependencies {
    let makeRootView: @MainActor () -> AnyView

    static var live: Self {
        Self(makeRootView: { AnyView(AppRootView()) })
    }
}

struct AppRootView: View {
    var body: some View {
        NavigationStack {
            GameListPlaceholderView()
        }
    }
}
