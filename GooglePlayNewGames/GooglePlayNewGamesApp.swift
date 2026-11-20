import SwiftUI

@main
struct GooglePlayNewGamesApp: App {
    private let dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            dependencies.makeRootView()
        }
    }
}
