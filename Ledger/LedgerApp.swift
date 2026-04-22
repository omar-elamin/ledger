import SwiftUI
import SwiftData

@main
struct LedgerApp: App {
    private let appEnvironment = LedgerAppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            ContentView(appEnvironment: appEnvironment)
        }
        .modelContainer(appEnvironment.modelContainer)
    }
}
