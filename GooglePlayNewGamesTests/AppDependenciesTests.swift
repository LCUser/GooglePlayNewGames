import SwiftUI
import XCTest
@testable import GooglePlayNewGames

@MainActor
final class AppDependenciesTests: XCTestCase {
    func testRootViewFactoryCanBeReplaced() {
        var factoryWasCalled = false
        let dependencies = AppDependencies {
            factoryWasCalled = true
            return AnyView(Text("Test root"))
        }

        _ = dependencies.makeRootView()

        XCTAssertTrue(factoryWasCalled)
    }
}
